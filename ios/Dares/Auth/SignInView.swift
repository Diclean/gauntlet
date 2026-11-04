import AuthenticationServices
import SwiftUI

struct SignInView: View {
    @Environment(AppState.self) private var appState
    @State private var isWorking = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 24)

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 96, height: 96)
                Image(systemName: "flame.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text("signin.title")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("signin.subtitle")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            AppleSignInButton { result in
                switch result {
                case let .success(appleResult):
                    isWorking = true
                    Task {
                        await appState.signIn(with: appleResult)
                        isWorking = false
                    }
                case let .failure(error):
                    if (error as? ASAuthorizationError)?.code == .canceled { return }
                    appState.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
            .frame(maxWidth: 420)
            .opacity(isWorking ? 0.6 : 1)
            .disabled(isWorking)

            if isWorking {
                ProgressView()
            }

            VStack(spacing: 8) {
                Button {
                    Task { await appState.enterDemoMode() }
                } label: {
                    Label("demo.try", systemImage: "play.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isWorking)

                Text("demo.try.hint")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 420)

            Spacer(minLength: 12)

            Text("signin.legal")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(.horizontal, 24)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

#Preview("Sign in") {
    SignInView()
        .environment(AppState.preview())
}
