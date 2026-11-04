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
        }
    }
}
