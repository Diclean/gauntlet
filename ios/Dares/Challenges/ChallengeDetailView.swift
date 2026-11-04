import SwiftUI

struct ChallengeDetailView: View {
    let challengeID: String
    let model: GroupViewModel

    @Environment(AppState.self) private var appState
    @State private var showingCapture = false

    private var challenge: Challenge? {
        model.challenges.first { $0.id == challengeID }
    }

    var body: some View {
        ScrollView {
            if let challenge {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(challenge.title)
                            .font(.title2.bold())
                        HStack(spacing: 8) {
                            DifficultyBadge(difficulty: challenge.difficulty)
                            PointsBadge(points: challenge.points)
                            StatusChip(title: challenge.myStatus.title, color: challenge.myStatus.color)
                        }
                        Text(challenge.description)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    if challenge.myStatus == .accepted {
                        Label("challenge.already_accepted", systemImage: "checkmark.seal.fill")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                    } else if challenge.myStatus == .pending {
                        Label("challenge.already_submitted", systemImage: "hourglass")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }

                    Button {
                        showingCapture = true
                    } label: {
                        Label("challenge.prove_it", systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(challenge.myStatus == .accepted)

                    VStack(alignment: .leading, spacing: 6) {
                        Label("challenge.camera_only", systemImage: "lock.shield")
                        Label("challenge.limits", systemImage: "info.circle")
                    }
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                }
                .padding()
            } else {
                ProgressView()
                    .padding()
            }
        }
        .navigationTitle("challenge.title")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingCapture, onDismiss: {
            Task { await model.load(api: appState.api, myUserID: appState.user?.id ?? "") }
        }) {
            if let challenge {
                ProofCaptureView(challenge: challenge)
            }
        }
    }
}

#Preview("Challenge") {
    NavigationStack {
        ChallengeDetailView(challengeID: MockData.challenges[0].id, model: .preview())
            .environment(AppState.preview())
    }
}
