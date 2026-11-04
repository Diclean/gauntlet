import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        ZStack {
            switch appState.phase {
            case .loading:
                ProgressView()
                    .controlSize(.large)
            case .signedOut:
                SignInView()
                    .transition(.opacity)
            case .signedIn:
                GroupsListView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.phase)
        .alert(
            Text("alert.error.title"),
            isPresented: Binding(
                get: { appState.errorMessage != nil },
                set: { if !$0 { appState.errorMessage = nil } }
            ),
            actions: {
                Button("alert.ok") { appState.errorMessage = nil }
            },
            message: {
                Text(appState.errorMessage ?? "")
            }
        )
    }
}
