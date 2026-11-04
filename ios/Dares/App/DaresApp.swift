import SwiftUI

@main
struct DaresApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .task {
                    let state = appState
                    appDelegate.onDeviceToken = { token in
                        Task { await state.registerDevice(token: token) }
                    }
                    await state.bootstrap()
                }
                .onOpenURL { url in
                    // `gauntlet://join/<code>` and `https://<host>/join/<code>` both
                    // open the join confirmation — the club is never joined on its own.
                    guard let code = InviteLink.code(from: url) else { return }
                    appState.router.pendingInviteCode = code
                }
        }
    }
}
