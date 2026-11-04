import AuthenticationServices
import SwiftUI

/// The sign in: the crest, the name of the app and the Apple button.
struct SignInView: View {
    @Environment(AppState.self) private var appState
    @State private var isWorking = false

    var body: some View {
        ZStack {
            Color.ink.ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer(minLength: 24)

                ClubCrest(initials: AppConfig.clubInitials, size: 76)

                VStack(spacing: 8) {
                    Text(AppConfig.appName)
                        .displayStyle(46)
                        .foregroundStyle(Color.paper)
                    Text("Your friends are the club. Every week is a matchweek. Every proof is a VAR call.")
                        .font(.subheadline)
                        .foregroundStyle(Color.paper.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
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
                        .tint(Color.card)
                }

                if appState.canRetrySession {
                    // The session is still there: only the server was unreachable.
                    BrutalOutlineButton(title: "Try again") {
                        Task { await appState.retrySession() }
                    }
                    .disabled(isWorking)
                }

                VStack(spacing: 10) {
                    BrutalButton(title: "Try the demo", trailing: "→") {
                        Task { await appState.enterDemoMode() }
                    }
                    .disabled(isWorking)

                    Text("The demo runs offline with a full club, a title race and an awards night.")
                        .labelStyle(8)
                        .foregroundStyle(Color.paper.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: 420)

                Spacer(minLength: 12)

                Text("By continuing you accept the rules of the club.")
                    .labelStyle(8)
                    .foregroundStyle(Color.paper.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .padding(.horizontal, 24)
        }
    }
}

#Preview("Sign in") {
    SignInView()
        .environment(AppState.preview())
}
