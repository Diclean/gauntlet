import SwiftUI

/// Full screen proof: the media, the caption and the two calls.
struct SubmissionDetailView: View {
    let model: GroupViewModel

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var current: Submission
    @State private var isVoting = false
    @State private var showingMenu = false
    @State private var showingBanter = false
    @State private var toast = ToastModel()

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
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(current.user.avatarEmoji ?? "🙂")
                            .font(.system(size: 20))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(current.user.displayName.uppercased())
                                .displayStyle(16)
                                .foregroundStyle(Color.paper)
                            Text(current.challengeTitle.uppercased())
                                .labelStyle(8)
                                .foregroundStyle(Color.paper.opacity(0.6))
                        }
                        Spacer()
                        StatusPill(kind: StatusPill.Kind(current.status))
                    }

                    if let caption = current.caption, !caption.isEmpty {
                        Text(caption)
                            .font(.subheadline)
                            .foregroundStyle(Color.paper.opacity(0.85))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    BanterBar(
                        submission: current,
                        onToggleReaction: { emoji in
                            toggleReaction(emoji)
                        },
                        onOpenBanter: { showingBanter = true }
                    )
                }

                if current.isSoloGroup {
                    Text("Invite friends to get votes on your proofs.")
                        .labelStyle(9)
                        .foregroundStyle(Color.card)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(voteProgressText)
                        .labelStyle(9)
                        .foregroundStyle(Color.paper.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if current.status == .pending, !current.isSoloGroup {
                    HStack(spacing: 12) {
                        Button {
                            vote(approve: false)
                        } label: {
                            Text("No goal")
                                .displayStyle(17)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(Color.red)
                                .foregroundStyle(Color.paper)
                                .brutalBorder(Color.paper)
                        }
                        .buttonStyle(.plain)
                        .rotationEffect(.degrees(Gauntlet.Rotation.callNoGoal))

                        Button {
                            vote(approve: true)
                        } label: {
                            HStack(spacing: 8) {
                                // The ball is an SF Symbol — no emoji as an icon.
                                Image(systemName: "soccerball")
                                    .font(.system(size: 17, weight: .bold))
                                Text("Goal")
                                    .displayStyle(17)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.pitch)
                            .foregroundStyle(Color.ink)
                            .brutalBorder(Color.paper)
                        }
                        .buttonStyle(.plain)
                        .rotationEffect(.degrees(Gauntlet.Rotation.callGoal))
                    }
                    .disabled(isVoting)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 44)
            .padding(.bottom, 18)
            .background {
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.9)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 8) {
                Button {
                    showingMenu = true
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.paper)
                        .frame(width: 40, height: 40)
                        .background(Color.black.opacity(0.5))
                        .overlay {
                            Rectangle().stroke(Color.paper, lineWidth: 1.5)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("More"))

                Button {
                    dismiss()
                } label: {
                    Text("✕")
                        .displayStyle(18)
                        .foregroundStyle(Color.paper)
                        .frame(width: 40, height: 40)
                        .background(Color.black.opacity(0.5))
                        .overlay {
                            Rectangle().stroke(Color.paper, lineWidth: 1.5)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close"))
            }
            .padding(.top, 8)
            .padding(.trailing, 14)
        }
        .brutalToast(toast, bottomPadding: 140)
        .sheet(isPresented: $showingMenu) {
            ProofMenuSheet(
                submission: current,
                myUserID: model.myUserID ?? "",
                api: appState.api,
                onDeleted: {
                    dismiss()
                },
                onReported: {
                    toast.show("Reported. It's hidden for you.")
                    dismiss()
                },
                onBlocked: {
                    toast.show("Blocked. You won't see them anymore.")
                    dismiss()
                }
            )
        }
        .sheet(isPresented: $showingBanter) {
            BanterSheet(submission: current, api: appState.api)
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

    private func toggleReaction(_ emoji: ReactionEmoji) {
        let submission = current
        Task {
            guard let updated = await model.toggleReaction(
                on: submission,
                emoji: emoji,
                api: appState.api
            ) else { return }
            current = updated
            Haptics.selection()
        }
    }
}

#Preview("Proof") {
    SubmissionDetailView(submission: MockData.submissions[0], model: .preview())
        .environment(AppState.preview())
}
