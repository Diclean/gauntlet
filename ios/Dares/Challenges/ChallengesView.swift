import SwiftUI

struct ChallengesView: View {
    let model: GroupViewModel

    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            if let week = model.week {
                Section {
                    HStack {
                        Label {
                            Text("challenges.week.label")
                        } icon: {
                            Image(systemName: "calendar")
                        }
                        Spacer()
                        CountdownLabel(deadline: week.endsAt, prefix: "closes ")
                    }
                    .font(.subheadline)
                }
            }

            Section("challenges.section") {
                ForEach(model.myChallenges) { challenge in
                    // A destination link: the navigation stack of the group screen is bound to
                    // its own route type, so a value of another type would never be resolved.
                    NavigationLink {
                        ChallengeDetailView(challengeID: challenge.id, model: model)
                    } label: {
                        ChallengeRow(challenge: challenge)
                    }
                }
            }
        }
        .overlay {
            if model.isLoading && model.challenges.isEmpty {
                ProgressView()
            }
        }
        .refreshable {
            await model.load(api: appState.api, myUserID: appState.user?.id ?? "")
        }
    }
}

private struct ChallengeRow: View {
    let challenge: Challenge

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(challenge.title)
                    .font(.headline)
                Spacer(minLength: 8)
                PointsBadge(points: challenge.points)
            }

            Text(challenge.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                DifficultyBadge(difficulty: challenge.difficulty)
                StatusChip(title: challenge.myStatus.title, color: challenge.myStatus.color)
                if challenge.acceptedCount > 0 {
                    Label {
                        Text("\(challenge.acceptedCount)")
                    } icon: {
                        Image(systemName: "checkmark.seal.fill")
                    }
                    .font(.caption)
                    .foregroundStyle(.green)
                }
                Spacer()
            }
        }
        .padding(.vertical, 6)
    }
}

#Preview("Challenges") {
    NavigationStack {
        ChallengesView(model: .preview())
            .environment(AppState.preview())
    }
}
