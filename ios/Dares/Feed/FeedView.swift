import SwiftUI

/// The feed of the club: the proofs of the matchweek, newest first.
struct FeedView: View {
    let model: GroupViewModel
    let onSelect: (Submission) -> Void

    @Environment(AppState.self) private var appState

    @State private var menuSubmission: Submission?
    @State private var banterSubmission: Submission?
    @State private var toast = ToastModel()

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    /// The feed stays blurred until the player posted a proof in this matchweek.
    private var hasPosted: Bool {
        guard let myUserID = model.myUserID else { return false }
        return model.feed.contains { $0.user.id == myUserID && $0.status != .expired }
    }

    var body: some View {
        ZStack {
            Color.ink.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Feed")
                        .displayStyle(34)
                        .foregroundStyle(Color.paper)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    if model.feed.isEmpty {
                        emptyState
                            .padding(.top, 40)
                    } else {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(model.feed) { submission in
                                FeedCard(
                                    submission: submission,
                                    isBlurred: !hasPosted,
                                    onMenu: { menuSubmission = submission },
                                    onToggleReaction: { emoji in
                                        toggleReaction(submission, emoji: emoji)
                                    },
                                    onOpenBanter: { banterSubmission = submission }
                                )
                                .contentShape(Rectangle())
                                .onTapGesture { onSelect(submission) }
                                .onAppear {
                                    guard submission.id == model.feed.last?.id else { return }
                                    Task { await model.loadMore(api: appState.api) }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    }

                    if model.isLoadingMore {
                        ProgressView()
                            .tint(Color.card)
                            .padding(.vertical, 20)
                    }

                    Spacer(minLength: 110)
                }
            }
            .scrollIndicators(.hidden)
        }
        .refreshable {
            await model.load(api: appState.api, myUserID: appState.user?.id ?? "")
        }
        .brutalToast(toast, bottomPadding: 104)
        .sheet(item: $menuSubmission) { submission in
            ProofMenuSheet(
                submission: submission,
                myUserID: model.myUserID ?? "",
                api: appState.api,
                onDeleted: {
                    Task { await model.load(api: appState.api, myUserID: appState.user?.id ?? "") }
                    toast.show("Proof deleted. The points are gone.")
                },
                onReported: {
                    Task { await model.load(api: appState.api, myUserID: appState.user?.id ?? "") }
                    toast.show("Reported. It's hidden for you.")
                },
                onBlocked: {
                    Task { await model.load(api: appState.api, myUserID: appState.user?.id ?? "") }
                    toast.show("Blocked. You won't see them anymore.")
                }
            )
        }
        .sheet(item: $banterSubmission) { submission in
            BanterSheet(submission: submission, api: appState.api)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("Nothing yet")
                .displayStyle(24)
                .foregroundStyle(Color.paper)
            Text("The proofs of the matchweek show up here.")
                .font(.subheadline)
                .foregroundStyle(Color.paper.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .overlay {
            Rectangle().stroke(Color.paper.opacity(0.3), lineWidth: 1.5)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Actions

    private func toggleReaction(_ submission: Submission, emoji: ReactionEmoji) {
        Task {
            let updated = await model.toggleReaction(on: submission, emoji: emoji, api: appState.api)
            guard updated != nil else { return }
            Haptics.selection()
        }
    }
}

/// One proof of the feed.
private struct FeedCard: View {
    let submission: Submission
    let isBlurred: Bool
    var onMenu: () -> Void
    var onToggleReaction: (ReactionEmoji) -> Void
    var onOpenBanter: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                ProofMediaView(submission: submission, contentMode: .fill)
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .blur(radius: isBlurred ? 10 : 0)

                if isBlurred {
                    Text("POST A PROOF TO SEE THE FEED")
                        .labelStyle(7)
                        .foregroundStyle(Color.paper)
                        .multilineTextAlignment(.center)
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.45))
                }

                StatusPill(kind: StatusPill.Kind(submission.status))
                    .padding(6)

                VStack {
                    HStack {
                        Spacer(minLength: 0)
                        Button {
                            onMenu()
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.paper)
                                .frame(width: 28, height: 28)
                                .background(Color.black.opacity(0.55))
                                .overlay {
                                    Rectangle().stroke(Color.paper.opacity(0.6), lineWidth: 1.5)
                                }
                        }
                        .buttonStyle(.plain)
                        .padding(6)
                        .accessibilityLabel(Text("More"))
                    }
                    Spacer(minLength: 0)
                }
            }
            .overlay {
                Rectangle().stroke(Color.paper.opacity(0.35), lineWidth: 1.5)
            }

            HStack(spacing: 5) {
                Text(submission.user.avatarEmoji ?? "🙂")
                    .font(.system(size: 12))
                Text(submission.user.displayName.uppercased())
                    .labelStyle(8)
                    .foregroundStyle(Color.paper)
                    .lineLimit(1)
                Spacer(minLength: 2)
            }

            Text(submission.challengeTitle.uppercased())
                .labelStyle(7.5)
                .foregroundStyle(Color.paper.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if !submission.reactions.isEmpty || submission.commentCount > 0 {
                BanterBar(
                    submission: submission,
                    compact: true,
                    onToggleReaction: onToggleReaction,
                    onOpenBanter: onOpenBanter
                )
            }
        }
        .accessibilityElement(children: .contain)
    }
}

extension StatusPill.Kind {
    init(_ status: SubmissionStatus) {
        switch status {
        case .accepted: self = .fullTime
        case .pending: self = .inVAR
        case .rejected, .removed: self = .red
        case .expired: self = .toPlay
        }
    }
}

#Preview("Feed") {
    NavigationStack {
        FeedView(model: .preview()) { _ in }
            .environment(AppState.preview())
    }
}
