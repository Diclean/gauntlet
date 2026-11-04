import AuthenticationServices
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
    /// True when a session is stored but the server could not be reached: the player
    /// can try again without signing in again.
    private(set) var canRetrySession = false
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
        isDemo: Bool = AppConfig.isDemoLaunchArgument,
        api: (any APIClientProtocol)? = nil
    ) {
        self.vault = vault
        self.baseURL = baseURL
        self.media = MediaStore()
        self.router = AppRouter()
        self.isDemoMode = isDemo
        self.api = api ?? (isDemo ? DemoAPIClient(simulationDelay: AppConfig.demoSimulationDelay)
            : APIClient(baseURL: baseURL, vault: vault))

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

    /// True when the player still has to accept the house rules (v3, SPEC.md section 6.1).
    var needsHouseRules: Bool {
        guard let user else { return false }
        return !user.termsAccepted
    }

    // MARK: - Session

    func bootstrap() async {
        if isDemoMode {
            await startDemoSession()
            return
        }
        guard let token = await vault.currentToken(), !token.isEmpty else {
            phase = .signedOut
            canRetrySession = false
            return
        }

        // A revoked Apple account never keeps a session alive.
        if await isAppleAccountRevoked() {
            await endSession()
            return
        }

        do {
            let response = try await api.currentUser()
            user = response.user
            phase = .signedIn
            canRetrySession = false
            errorMessage = nil
            await loadGroups()
            await registerForPushNotifications()
        } catch {
            await handleBootstrapFailure(error)
        }
    }

    /// Signs in again after a network failure — the token is still there.
    func retrySession() async {
        phase = .loading
        errorMessage = nil
        await bootstrap()
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
            if !isDemoMode {
                // The demo never touches the Keychain.
                try await vault.store(response.token)
                if let appleUserID = result.appleUserID, !appleUserID.isEmpty {
                    try? await vault.storeAppleUserID(appleUserID)
                }
            }
            user = response.user
            phase = .signedIn
            canRetrySession = false
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
        // The server deletes the session first. The app goes out even when the call
        // fails — the token is cleared anyway.
        _ = try? await api.logout()
        await endSession()
    }

    func deleteAccount() async -> Bool {
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await api.deleteAccount()
            await media.purge()
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

    // MARK: - Session helpers

    /// Forgets the session: the Keychain is cleared and the cached media is deleted.
    private func endSession() async {
        await vault.clear()
        await media.purge()
        user = nil
        groups = []
        router.path = []
        router.pendingSubmissionID = nil
        phase = .signedOut
        canRetrySession = false
    }

    /// A network failure keeps the token: the session is still good, only the server
    /// is unreachable. The player gets the retry state instead of the sign in screen.
    private func handleBootstrapFailure(_ error: any Error) async {
        if case APIError.unauthorized = error {
            // The token is dead — the player signs in again and the proofs of the
            // old session leave the disk.
            await endSession()
            return
        }
        phase = .signedOut
        canRetrySession = true
        errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
    }

    /// True when Apple says that the account of the player is gone.
    ///
    /// A revoked (or removed) Apple ID must not keep the session of the club alive.
    private func isAppleAccountRevoked() async -> Bool {
        guard let userID = await vault.appleUserID(), !userID.isEmpty else { return false }
        guard let state = await appleCredentialState(for: userID) else {
            // The lookup itself failed — that is not a revocation.
            return false
        }
        switch state {
        case .revoked, .notFound:
            return true
        case .authorized, .transferred:
            return false
        @unknown default:
            return false
        }
    }

    /// The state of the Apple account — `nil` when Apple cannot answer.
    private func appleCredentialState(
        for userID: String
    ) async -> ASAuthorizationAppleIDProvider.CredentialState? {
        await withCheckedContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { state, error in
                if error != nil {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: state)
                }
            }
        }
    }

    // MARK: - Demo mode

    /// Starts the offline demo. The Keychain and the network are left alone.
    func enterDemoMode() async {
        guard !isDemoMode else { return }
        isDemoMode = true
        api = DemoAPIClient(simulationDelay: AppConfig.demoSimulationDelay)
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

    // MARK: - House rules

    /// Accepts the house rules (v3, SPEC.md section 6.1).
    func acceptTerms() async -> Bool {
        isBusy = true
        defer { isBusy = false }
        do {
            let response = try await api.acceptTerms()
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
        guard !isDemoMode, !AppConfig.isRunningTests else { return }
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
