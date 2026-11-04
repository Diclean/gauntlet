import SwiftUI

struct GroupHomeView: View {
    enum Tab: Hashable {
        case challenges, votes, feed, leaderboard
    }

    /// A single sheet presentation for the whole group screen.
    private enum ActiveSheet: Identifiable {
        case settings
        case submission(Submission)

        var id: String {
            switch self {
            case .settings: "settings"
            case let .submission(submission): "submission-\(submission.id)"
            }
        }
    }

    let groupID: String

    @Environment(AppState.self) private var appState
    @State private var model: GroupViewModel
    @State private var selectedTab: Tab = .challenges
    @State private var activeSheet: ActiveSheet?

    init(groupID: String) {
        self.groupID = groupID
        _model = State(initialValue: GroupViewModel(groupID: groupID))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ChallengesView(model: model)
                .tabItem { Label("tab.challenges", systemImage: "target") }
                .tag(Tab.challenges)

            VoteView(model: model) { submission in
                activeSheet = .submission(submission)
            }
            .tabItem { Label("tab.vote", systemImage: "hand.thumbsup") }
            .badge(model.pendingVoteCount > 0 ? Text("\(model.pendingVoteCount)") : nil)
            .tag(Tab.votes)

            FeedView(model: model) { submission in
                activeSheet = .submission(submission)
            }
            .tabItem { Label("tab.feed", systemImage: "square.stack") }
            .tag(Tab.feed)

            LeaderboardView(model: model)
                .tabItem { Label("tab.leaderboard", systemImage: "trophy") }
                .tag(Tab.leaderboard)
        }
        .navigationTitle(model.group?.name ?? String(localized: "group.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if appState.isDemoMode {
                ToolbarItem(placement: .topBarLeading) {
                    DemoBadge()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    activeSheet = .settings
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel(Text("group.settings.title"))
            }
        }
        .task {
            await model.load(api: appState.api, myUserID: appState.user?.id ?? "")
            openPendingSubmissionIfNeeded()
        }
        .task {
            // In the demo the other members vote on their own, so the screen refreshes itself.
            if appState.isDemoMode {
                model.startLiveUpdates(api: appState.api)
            }
        }
        .onChange(of: appState.router.pendingSubmissionID) { _, _ in
            openPendingSubmissionIfNeeded()
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .settings:
                GroupSettingsView(model: model)
            case let .submission(submission):
                SubmissionDetailView(submission: submission, model: model)
            }
        }
        .alert(
            Text("alert.error.title"),
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            ),
            actions: { Button("alert.ok") { model.errorMessage = nil } },
            message: { Text(model.errorMessage ?? "") }
        )
    }

    private func openPendingSubmissionIfNeeded() {
        guard let pendingID = appState.router.pendingSubmissionID else { return }
        guard let submission = model.feed.first(where: { $0.id == pendingID }) else { return }
        selectedTab = .votes
        activeSheet = .submission(submission)
        appState.router.pendingSubmissionID = nil
    }
}

#Preview("Group") {
    NavigationStack {
        GroupHomeView(groupID: MockData.group.id)
            .environment(AppState.preview())
    }
}
