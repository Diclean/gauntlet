import SwiftUI

/// The club screen: MATCH · VAR · FEED · TABLE.
struct GroupHomeView: View {
    /// A single sheet presentation for the whole club screen.
    private enum ActiveSheet: Identifiable {
        case settings
        case submission(Submission)
        case capture(Challenge)
        case goal(GoalMoment)
        case fixture(Challenge)
        case houseFixture
        case banter(Submission)

        var id: String {
            switch self {
            case .settings: "settings"
            case let .submission(submission): "submission-\(submission.id)"
            case let .capture(challenge): "capture-\(challenge.id)"
            case let .goal(goal): "goal-\(goal.submission.id)"
            case let .fixture(challenge): "fixture-\(challenge.id)"
            case .houseFixture: "house-fixture"
            case let .banter(submission): "banter-\(submission.id)"
            }
        }
    }

    /// The proof that was just accepted (or thrown out) by the VAR.
    struct GoalMoment: Identifiable {
        let submission: Submission
        let confirmedBy: [User]
        let points: Int
        let streak: Int
        let isAccepted: Bool

        var id: String { submission.id }
    }

    let groupID: String

    @Environment(AppState.self) private var appState
    @State private var model: GroupViewModel
    @State private var selectedTab: BrutalTabBar.Tab = .match
    @State private var activeSheet: ActiveSheet?
    @State private var knownAccepted: Set<String> = []
    /// The title race is a dark screen, so the tab bar follows.
    @State private var tableIsDark = false

    init(groupID: String) {
        self.groupID = groupID
        _model = State(initialValue: GroupViewModel(groupID: groupID))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            (selectedTab == .table ? Color.paper : Color.ink)
                .ignoresSafeArea()

            SwiftUI.Group {
                switch selectedTab {
                case .match:
                    MatchdayView(
                        model: model,
                        onProveIt: { fixture in
                            activeSheet = .capture(fixture)
                        },
                        onOpenFixture: { fixture in
                            activeSheet = .fixture(fixture)
                        },
                        onAddHouseFixture: {
                            activeSheet = .houseFixture
                        }
                    )
                case .varCheck:
                    VarCheckView(model: model)
                case .feed:
                    FeedView(model: model) { submission in
                        activeSheet = .submission(submission)
                    }
                case .table:
                    TableView(model: model, isDark: $tableIsDark)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar(.hidden, for: .navigationBar)

            BrutalTabBar(
                selection: $selectedTab,
                badgeCount: model.pendingVoteCount,
                isDark: selectedTab != .table || tableIsDark
            )
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .navigationBarHidden(true)
        .task {
            await model.load(api: appState.api, myUserID: appState.user?.id ?? "")
            knownAccepted = acceptedProofIDs()
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
        .onChange(of: model.feed) { _, _ in
            presentGoalIfNeeded()
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .settings:
                GroupSettingsView(model: model)
            case let .submission(submission):
                SubmissionDetailView(submission: submission, model: model)
            case let .capture(challenge):
                ProofCaptureView(challenge: challenge)
            case let .goal(goal):
                GoalMomentView(
                    submission: goal.submission,
                    confirmedBy: goal.confirmedBy,
                    points: goal.points,
                    streak: goal.streak,
                    isAccepted: goal.isAccepted
                ) {
                    activeSheet = nil
                }
            case let .fixture(challenge):
                ChallengeDetailView(challengeID: challenge.id, model: model)
            case .houseFixture:
                HouseFixtureSheet(groupID: groupID, api: appState.api) { _ in
                    Task { await model.load(api: appState.api, myUserID: appState.user?.id ?? "") }
                }
            case let .banter(submission):
                BanterSheet(submission: submission, api: appState.api)
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

    // MARK: - The goal moment

    private func acceptedProofIDs() -> Set<String> {
        Set(
            model.feed
                .filter { $0.user.id == model.myUserID && $0.status == .accepted }
                .map(\.id)
        )
    }

    /// Shows the goal moment when one of my proofs is accepted while the screen is open.
    private func presentGoalIfNeeded() {
        guard let myUserID = model.myUserID else { return }
        let mine = model.feed.filter { $0.user.id == myUserID && $0.status == .accepted }
        guard let proof = mine.first(where: { isFreshAcceptance($0) }) else { return }
        knownAccepted.insert(proof.id)
        Haptics.success()
        activeSheet = .goal(
            GoalMoment(
                submission: proof,
                confirmedBy: confirmers(of: proof),
                points: points(of: proof),
                streak: model.myStreak,
                isAccepted: true
            )
        )
    }

    /// Only a proof that was accepted while the screen was open deserves the moment.
    private func isFreshAcceptance(_ proof: Submission) -> Bool {
        guard !knownAccepted.contains(proof.id) else { return false }
        guard let decidedAt = proof.decidedAt else { return false }
        return decidedAt > Date().addingTimeInterval(-120)
    }

    /// The points of the fixture of a proof.
    private func points(of submission: Submission) -> Int {
        model.fixtures.first { $0.id == submission.challengeId }?.points ?? 0
    }

    /// The members that confirmed the proof: the ones that called it.
    private func confirmers(of submission: Submission) -> [User] {
        if let voters = submission.voters, !voters.isEmpty {
            return voters
        }
        return model.members
            .map(\.user)
            .filter { $0.id != model.myUserID }
            .prefix(2)
            .map { $0 }
    }

    private func openPendingSubmissionIfNeeded() {
        guard let pendingID = appState.router.pendingSubmissionID else { return }
        guard let submission = model.feed.first(where: { $0.id == pendingID }) else { return }
        selectedTab = .varCheck
        activeSheet = .submission(submission)
        appState.router.pendingSubmissionID = nil
    }
}

extension Submission {
    /// A placeholder submission for a fixture that has not been played yet.
    static func fixturePlaceholder(_ fixture: Challenge) -> Submission {
        Submission(
            id: "fixture-\(fixture.id)",
            challengeId: fixture.id,
            challengeTitle: fixture.title,
            user: User(id: "me", displayName: "Me", avatarEmoji: "🦊"),
            mediaUrl: "",
            mediaType: .photo,
            caption: nil,
            status: .pending,
            approvals: 0,
            rejections: 0,
            eligibleVoters: 0,
            myVote: nil,
            createdAt: Date(),
            decidedAt: nil
        )
    }
}
#Preview("Group") {
    NavigationStack {
        GroupHomeView(groupID: MockData.group.id)
            .environment(AppState.preview())
    }
}
