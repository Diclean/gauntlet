import SwiftUI

/// Full screen proof: media, caption and the voting controls.
struct SubmissionDetailView: View {
    let model: GroupViewModel

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var current: Submission
    @State private var isVoting = false

    init(submission: Submission, model: GroupViewModel) {
        self.model = model
        _current = State(initialValue: submission)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            ProofMediaView(submission: current)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        AvatarView(emoji: current.user.avatarEmoji, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(current.user.displayName)
                                .font(.subheadline.weight(.semibold))
                            Text(current.challengeTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusChip(title: current.status.title, color: current.status.color)
                    }

                    if let caption = current.caption, !caption.isEmpty {
                        Text(caption)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if current.isSoloGroup {
                    Label("vote.solo_group", systemImage: "person.2.slash")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(voteProgressText)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if current.status == .pending && !current.isSoloGroup {
                    HStack(spacing: 12) {
                        Button {
                            vote(approve: false)
                        } label: {
                            Label("vote.reject", systemImage: "xmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)

                        Button {
                            vote(approve: true)
                        } label: {
                            Label("vote.approve", systemImage: "checkmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }
                    .disabled(isVoting)
                }
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.4))
            }
            .padding()
        }
    }

    private var voteProgressText: String {
        String(
            format: String(localized: "vote.progress"),
            current.approvals,
            current.approvalsNeeded,
            current.rejections,
            current.rejectionsNeeded
        )
    }

    private func vote(approve: Bool) {
        isVoting = true
        let submission = current
        Task {
            let updated = await model.vote(on: submission, approve: approve, api: appState.api)
            isVoting = false
            guard let updated else { return }
            Haptics.vote()
            current = updated
            if updated.status != .pending {
                Haptics.success()
                dismiss()
            }
        }
    }
}

#Preview("Submission") {
    SubmissionDetailView(submission: MockData.submissions[0], model: .preview())
        .environment(AppState.preview())
}
