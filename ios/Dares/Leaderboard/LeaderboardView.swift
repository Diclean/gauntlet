import SwiftUI

struct LeaderboardView: View {
    let model: GroupViewModel

    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            Picker("leaderboard.scope", selection: $model.scope) {
                Text("leaderboard.this_week").tag(LeaderboardScope.week)
                Text("leaderboard.all_time").tag(LeaderboardScope.all)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            List {
                if model.leaderboard.isEmpty {
                    EmptyStateView(
                        icon: "trophy",
                        title: String(localized: "leaderboard.empty.title"),
                        message: String(localized: "leaderboard.empty.message")
                    )
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(model.leaderboard) { entry in
                        LeaderboardRow(entry: entry, isMe: entry.user.id == model.myUserID)
                    }
                }
            }
            .listStyle(.plain)
        }
        .onChange(of: model.scope) { _, _ in
            Task { await model.reloadLeaderboard(api: appState.api) }
        }
        .refreshable {
            await model.reloadLeaderboard(api: appState.api)
        }
    }
}

private struct LeaderboardRow: View {
    let entry: LeaderboardEntry
    let isMe: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("\(entry.rank)")
                .font(.headline.monospacedDigit())
                .frame(width: 32)
                .foregroundStyle(entry.rank <= 3 ? Color.accentColor : .secondary)

            AvatarView(emoji: entry.user.avatarEmoji, size: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.user.displayName)
                    .font(.subheadline.weight(isMe ? .bold : .regular))
                if entry.streak > 0 {
                    Text("🔥 \(entry.streak)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text("\(entry.points)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(Color.accentColor)
        }
        .padding(.vertical, 4)
        .listRowBackground(isMe ? Color.accentColor.opacity(0.08) : Color.clear)
    }
}

#Preview("Leaderboard") {
    NavigationStack {
        LeaderboardView(model: .preview())
            .environment(AppState.preview())
    }
}
