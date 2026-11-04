import SwiftUI

struct FeedView: View {
    let model: GroupViewModel
    let onSelect: (Submission) -> Void

    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            if model.feed.isEmpty {
                EmptyStateView(
                    icon: "square.stack",
                    title: String(localized: "feed.empty.title"),
                    message: String(localized: "feed.empty.message")
                )
                .listRowSeparator(.hidden)
            } else {
                ForEach(model.feed) { submission in
                    Button {
                        onSelect(submission)
                    } label: {
                        SubmissionRow(submission: submission)
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        guard submission.id == model.feed.last?.id else { return }
                        Task { await model.loadMore(api: appState.api) }
                    }
                }

                if model.isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }
        }
        .refreshable {
            await model.load(api: appState.api, myUserID: appState.user?.id ?? "")
        }
    }
}

/// One row of the feed / vote list.
struct SubmissionRow: View {
    let submission: Submission
    var showsVoteButtons = true

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(emoji: submission.user.avatarEmoji, size: 38)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(submission.user.displayName)
                        .font(.subheadline.weight(.semibold))
                    Text("•")
                        .foregroundStyle(.tertiary)
                    Text(Formatting.relative(submission.createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    StatusChip(title: submission.status.title, color: submission.status.color)
                }

                Text(submission.challengeTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let caption = submission.caption, !caption.isEmpty {
                    Text(caption)
                        .font(.footnote)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    Label(submission.mediaType.rawValue.capitalized, systemImage: submission.mediaType.iconName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if submission.status == .pending {
                        Label(
                            "\(submission.approvals)/\(submission.approvalsNeeded)",
                            systemImage: "hand.thumbsup"
                        )
                        .font(.caption2)
                        .foregroundStyle(.green)
                        Label(
                            "\(submission.rejections)/\(submission.rejectionsNeeded)",
                            systemImage: "hand.thumbsdown"
                        )
                        .font(.caption2)
                        .foregroundStyle(.red)
                    }
                    Spacer()
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
    }
}

#Preview("Feed") {
    NavigationStack {
        FeedView(model: .preview()) { _ in }
            .environment(AppState.preview())
    }
}
