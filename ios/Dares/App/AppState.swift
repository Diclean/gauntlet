import Foundation
import Observation
import UIKit
import UserNotifications

/// Global application state: session, groups, routing and error reporting.
@MainActor
@Observable
final class AppState {
    enum Phase: Equatable {
        case loading
        case signedOut
        case signedIn
    }

    private(set) var phase: Phase = .loading
    private(set) var user: User?
    private(set) var groups: [Group] = []
    private(set) var isBusy = false
    private(set) var isLoadingGroups = false
    /// True while the offline demo mode is running.
    private(set) var isDemoMode: Bool
    var errorMessage: String?
    var banner: String?

    /// The client every view talks to. It is the real Worker client or the offline demo.
    private(set) var api: any APIClientProtocol
    let vault: TokenVault
    let media: MediaStore
    let router: AppRouter

    private let baseURL: URL

    init(
        vault: TokenVault = .shared,
        baseURL: URL = AppConfig.baseURL,
        isDemo: Bool = AppConfig.isDemoLaunchArgument
    ) {
        self.vault = vault
        self.baseURL = baseURL
        self.media = MediaStore()
        self.router = AppRouter()
        self.isDemoMode = isDemo
        self.api = isDemo ? DemoAPIClient() : APIClient(baseURL: baseURL, vault: vault)

        DeepLinkRouter.shared.handler = { [weak self] groupID, submissionID in
            guard let groupID else { return }
            self?.router.open(groupID: groupID, submissionID: submissionID)
        }
    }

    /// Preview-only state, filled with mock data so SwiftUI previews work without a server.
    static func preview() -> AppState {
        let state = AppState()
        state.phase = .signedIn
        state.user = MockData.me
        state.groups = [MockData.group]
        return state
    }

    /// True when the account still needs a display name (first launch after sign in).
    var needsProfileSetup: Bool {
        guard let user else { return false }
        return user.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Session

    func bootstrap() async {
        if isDemoMode {
            await startDemoSession()
            return
        }
        guard let token = await vault.currentToken(), !token.isEmpty else {
            phase = .signedOut
            return
        }
        do {
            let response = try await api.currentUser()
            user = response.user
            phase = .signedIn
            await loadGroups()
            await registerForPushNotifications()
        } catch {
            await vault.clear()
            user = nil
            phase = .signedOut
        }
    }

    func signIn(with result: AppleSignInResult) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let request = AppleAuthRequest(
                identityToken: result.identityToken,
                nonce: result.rawNonce,
                displayName: result.displayName
            )
            let response = try await api.authenticate(request)
            try await vault.store(response.token)
            user = response.user
            phase = .signedIn
            errorMessage = nil
            await loadGroups()
            await registerForPushNotifications()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func signOut() async {
        if isDemoMode {
            await exitDemoMode()
            return
        }
        await vault.clear()
        user = nil
        groups = []
        router.path = []
        phase = .signedOut
    }

    func deleteAccount() async -> Bool {
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await api.deleteAccount()
            if isDemoMode {
                await exitDemoMode()
            } else {
                await signOut()
            }
            return true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    // MARK: - Demo mode

    /// Starts the offline demo. The Keychain and the network are left alone.
    func enterDemoMode() async {
        guard !isDemoMode else { return }
        isDemoMode = true
        api = DemoAPIClient()
        router.path = []
        await startDemoSession()
    }

    /// Leaves the demo and goes back to the real sign in.
    func exitDemoMode() async {
        guard isDemoMode else { return }
        isDemoMode = false
        api = APIClient(baseURL: baseURL, vault: vault)
        user = nil
        groups = []
        router.path = []
        phase = .loading
        await bootstrap()
    }

    private func startDemoSession() async {
        do {
            let response = try await api.currentUser()
            user = response.user
            phase = .signedIn
            errorMessage = nil
            await loadGroups()
        } catch {
            user = nil
            phase = .signedOut
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Profile

    func updateProfile(displayName: String?, avatarEmoji: String?) async -> Bool {
        isBusy = true
        defer { isBusy = false }
        do {
            let request = UpdateMeRequest(displayName: displayName, avatarEmoji: avatarEmoji)
            let response = try await api.updateProfile(request)
            user = response.user
            errorMessage = nil
            return true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    // MARK: - Groups

    func loadGroups() async {
        isLoadingGroups = true
        defer { isLoadingGroups = false }
        do {
            let response = try await api.groups()
            groups = response.groups
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func addGroup(_ group: Group) async {
        if !groups.contains(where: { $0.id == group.id }) {
            groups.append(group)
            groups.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        router.open(groupID: group.id)
    }

    func removeGroup(id: String) {
        groups.removeAll { $0.id == id }
    }

    // MARK: - Push notifications

    func registerForPushNotifications() async {
        guard !isDemoMode else { return }
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        guard granted else { return }
        UIApplication.shared.registerForRemoteNotifications()
        if let token = await PushTokenStore.shared.currentToken() {
            await registerDevice(token: token)
        }
    }

    func registerDevice(token: String) async {
        guard !isDemoMode else { return }
        await PushTokenStore.shared.set(token)
        do {
            _ = try await api.registerDevice(token: token)
        } catch {
            // Push registration is best effort — never block the user because of it.
        }
    }
}
