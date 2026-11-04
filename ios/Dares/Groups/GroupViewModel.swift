import Foundation
import Observation

/// One row of The Table.
struct TableRow: Identifiable, Hashable, Sendable {
    let user: User
    let rank: Int
    /// The movement against the previous matchweek: positive is up.
    let movement: Int
    /// The number of matchweeks won.
    let wins: Int
    /// The last five matchweeks.
    let form: [FormSquares.Result]
    let points: Int

    var id: String { user.id }
}

/// Loads and caches everything that belongs to a single club.
@MainActor
@Observable
final class GroupViewModel {
    let groupID: String

    var group: Group?
    var members: [Member] = []
    var week: Week?
    var fixtures: [Challenge] = []
    var feed: [Submission] = []
    var nextCursor: String?
    /// Pending submissions of others that still need my vote (the server knows best).
    var pendingVotes: [Submission] = []
    var leaderboard: [LeaderboardEntry] = []
    var scope: LeaderboardScope = .week
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?
    var myUserID: String?

    // MARK: v2

    /// The title race: the points of every member, matchweek by matchweek.
    var race: RaceResponse?
    /// The full-time receipt of the matchweek that is shown.
    var receipt: ReceiptResponse?
    /// The awards of the ceremony month.
    var awards: AwardsResponse?
    /// The months that have an awards ceremony.
    var awardMonths: [String] = []
    /// The trophy cabinet of the signed in player.
    var trophies: [Trophy] = []
    /// The matchweek of the receipt that is open.
    var receiptWeekID: String?
    /// The past matchweeks, newest first.
    var pastWeeks: [Week] = []

    // MARK: v3

    /// The house fixture of the matchweek (v3, SPEC.md section 6.7).
    var houseFixture: HouseFixtureInfo?
    /// The fixture I chose as my captain fixture.
    var myCaptainChallengeID: String?

    /// Keeps the screen up to date while the club screen is open (the demo plays the other
    /// members, so the state changes on its own).
    private var liveUpdatesTask: Task<Void, Never>?

    init(groupID: String) {
        self.groupID = groupID
    }

    static func preview(groupID: String = MockData.group.id) -> GroupViewModel {
        let model = GroupViewModel(groupID: groupID)
        model.group = MockData.group
        model.members = MockData.members
        model.week = MockData.week
        model.fixtures = MockData.challenges
        model.feed = MockData.submissions
        model.pendingVotes = MockData.submissions.filter { $0.status == .pending }
        model.nextCursor = nil
        model.leaderboard = MockData.leaderboard
        model.myUserID = MockData.me.id
        return model
    }

    var isOwner: Bool {
        guard let group, let myUserID else { return false }
        return group.ownerId == myUserID
    }

    var pendingVoteCount: Int { pendingVotes.count }

    var myFixtures: [Challenge] {
        fixtures.sorted { $0.position < $1.position }
    }

    /// The number of fixtures of the current matchweek.
    var fixtureCount: Int {
        max(myFixtures.count, 1)
    }

    /// How many of my fixtures are already accepted.
    var scoredCount: Int {
        myFixtures.filter { $0.myStatus == .accepted }.count
    }

    /// The next fixture that still has to be played.
    var nextFixture: Challenge? {
        myFixtures.first { $0.myStatus == .todo || $0.myStatus == .rejected }
            ?? myFixtures.first
    }

    /// My captain fixture — the armband of the matchweek.
    var captainFixture: Challenge? {
        guard let myCaptainChallengeID else { return nil }
        return fixtures.first { $0.id == myCaptainChallengeID }
    }

    /// The number of vetoes that replaced a fixture this matchweek.
    var usedReplacements: Int {
        fixtures.filter(\.isNew).count
    }

    /// The rank of the signed in player in the current matchweek.
    var myRank: Int {
        guard let myUserID else { return 0 }
        return leaderboard.first { $0.user.id == myUserID }?.rank ?? 0
    }

    var myStreak: Int {
        guard let myUserID else { return 0 }
        return leaderboard.first { $0.user.id == myUserID }?.streak ?? 0
    }

    // MARK: - Loading

    func load(api: any APIClientProtocol, myUserID: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let detailTask = api.groupDetail(id: groupID)
            async let weekTask = api.currentWeek(groupID: groupID)
            async let feedTask = api.feed(groupID: groupID, cursor: nil)
            async let boardTask = api.leaderboard(groupID: groupID, scope: scope)
            async let pendingTask = api.pendingVotes(groupID: groupID)
            async let raceTask = api.race(groupID: groupID)
            async let weeksTask = api.weeks(groupID: groupID, limit: 10)
            async let monthsTask = api.awardMonths(groupID: groupID)
            async let awardsTask = api.awards(groupID: groupID, month: nil)

            let (
                detailResponse,
                weekResponse,
                feedResponse,
                boardResponse,
                pendingResponse,
                raceResponse,
                weeksList,
                months,
                awardsResponse
            ) = try await (
                detailTask,
                weekTask,
                feedTask,
                boardTask,
                pendingTask,
                raceTask,
                weeksTask,
                monthsTask,
                awardsTask
            )

            self.myUserID = myUserID
            group = detailResponse.group
            members = detailResponse.members
            week = weekResponse.week
            fixtures = weekResponse.challenges.sorted { $0.position < $1.position }
            houseFixture = weekResponse.houseFixture
            myCaptainChallengeID = weekResponse.week.myCaptainChallengeId
            feed = feedResponse.items
            nextCursor = feedResponse.nextCursor
            leaderboard = boardResponse.entries
            pendingVotes = pendingResponse.items
            race = raceResponse
            awardMonths = months
            awards = awardsResponse
            pastWeeks = weeksList
            receiptWeekID = receiptWeekID ?? weekResponse.week.id
            if receipt == nil, let receiptWeekID {
                receipt = try? await api.receipt(groupID: groupID, weekID: receiptWeekID)
            }
            errorMessage = nil
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Reloads what can change while the club screen is open: the matchweek, the proofs
    /// that wait for my vote and the table.
    func refreshLiveState(api: any APIClientProtocol) async {
        do {
            async let weekTask = api.currentWeek(groupID: groupID)
            async let pendingTask = api.pendingVotes(groupID: groupID)
            async let boardTask = api.leaderboard(groupID: groupID, scope: scope)
            async let raceTask = api.race(groupID: groupID)
            async let feedTask = api.feed(groupID: groupID, cursor: nil)
            let (weekResponse, pendingResponse, boardResponse, raceResponse, feedResponse) = try await (
                weekTask,
                pendingTask,
                boardTask,
                raceTask,
                feedTask
            )
            week = weekResponse.week
            fixtures = weekResponse.challenges.sorted { $0.position < $1.position }
            houseFixture = weekResponse.houseFixture
            myCaptainChallengeID = weekResponse.week.myCaptainChallengeId
            pendingVotes = pendingResponse.items
            leaderboard = boardResponse.entries
            race = raceResponse
            feed = feedResponse.items
            if let receiptWeekID {
                receipt = try? await api.receipt(groupID: groupID, weekID: receiptWeekID)
            }
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Starts the periodic refresh of the club. It lives in the model, so it keeps
    /// running while a screen is pushed on top of the club.
    func startLiveUpdates(api: any APIClientProtocol, every seconds: TimeInterval = 3) {
        guard liveUpdatesTask == nil else { return }
        liveUpdatesTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled, let self else { return }
                await self.refreshLiveState(api: api)
            }
        }
    }

    func stopLiveUpdates() {
        liveUpdatesTask?.cancel()
        liveUpdatesTask = nil
    }

    func loadMore(api: any APIClientProtocol) async {
        guard let cursor = nextCursor, !cursor.isEmpty, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let response = try await api.feed(groupID: groupID, cursor: cursor)
            let known = Set(feed.map(\.id))
            feed.append(contentsOf: response.items.filter { !known.contains($0.id) })
            nextCursor = response.nextCursor
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func reloadLeaderboard(api: any APIClientProtocol) async {
        do {
            let response = try await api.leaderboard(groupID: groupID, scope: scope)
            leaderboard = response.entries
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Loads the receipt of another matchweek.
    func loadReceipt(weekID: String, api: any APIClientProtocol) async {
        receiptWeekID = weekID
        receipt = try? await api.receipt(groupID: groupID, weekID: weekID)
    }

    /// Loads the trophy cabinet of the signed in player.
    func loadTrophies(api: any APIClientProtocol) async {
        trophies = (try? await api.trophies()) ?? []
    }

    // MARK: - The Table

    /// The rows of The Table, built from the title race.
    func tableRows(scope: LeaderboardScope) -> [TableRow] {
        guard let race, !race.series.isEmpty else {
            return leaderboard.map {
                TableRow(user: $0.user, rank: $0.rank, movement: 0, wins: 0, form: [], points: $0.points)
            }
        }
        let memberCount = max(race.series.count, 1)
        let topHalf = max(1, memberCount / 2)

        // The points of every member, matchweek by matchweek.
        var perWeek: [String: [Int]] = [:]
        for series in race.series {
            perWeek[series.user.id] = series.perWeek
        }

        // The rank of every member in every matchweek.
        var ranks: [String: [Int]] = [:]
        for (index, _) in race.weeks.enumerated() {
            let points = race.series.map { ($0.user.id, $0.user.displayName, $0.perWeek.indices.contains(index) ? $0.perWeek[index] : 0) }
            for entry in points {
                let better = points.filter { $0.2 > entry.2 }.count
                ranks[entry.0, default: []].append(better + 1)
            }
        }

        let lastIndex = max(race.weeks.count - 1, 0)
        var rows: [TableRow] = []
        for series in race.series {
            let userID = series.user.id
            let userRanks = ranks[userID] ?? []
            let currentRank = userRanks.indices.contains(lastIndex) ? userRanks[lastIndex] : 0
            let previousRank = userRanks.indices.contains(lastIndex - 1) ? userRanks[lastIndex - 1] : currentRank
            let movement = previousRank - currentRank

            // The matchweeks won: the ones where the player finished first with points.
            let wins = userRanks.enumerated().reduce(0) { total, entry in
                guard entry.element == 1 else { return total }
                let points = series.perWeek.indices.contains(entry.offset) ? series.perWeek[entry.offset] : 0
                return total + (points > 0 ? 1 : 0)
            }

            // The form: the last five matchweeks, the running one included.
            let formIndices = race.weeks.indices.suffix(5)
            let form = formIndices.map { index -> FormSquares.Result in
                let points = series.perWeek.indices.contains(index) ? series.perWeek[index] : 0
                guard points > 0 else { return .loss }
                let rank = userRanks.indices.contains(index) ? userRanks[index] : 0
                return rank <= topHalf ? .win : .draw
            }

            let points: Int
            switch scope {
            case .week:
                points = series.perWeek.indices.contains(lastIndex) ? series.perWeek[lastIndex] : 0
            case .all:
                points = series.cumulative.last ?? 0
            }

            rows.append(
                TableRow(
                    user: series.user,
                    rank: currentRank,
                    movement: movement,
                    wins: wins,
                    form: form,
                    points: points
                )
            )
        }

        rows.sort { lhs, rhs in
            if lhs.points != rhs.points { return lhs.points > rhs.points }
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            return lhs.user.displayName.localizedCaseInsensitiveCompare(rhs.user.displayName) == .orderedAscending
        }
        return rows
    }

    /// The club form: the number of consecutive matchweeks in which everybody scored.
    func clubForm() -> Int {
        guard let race, race.weeks.count > 1 else { return 0 }
        let open = race.weeks.firstIndex { $0.id == week?.id }
        let indices = race.weeks.indices.filter { index in
            guard let open else { return true }
            return index != open
        }
        var count = 0
        for index in indices.reversed() {
            let everybody = race.series.allSatisfy { series in
                series.perWeek.indices.contains(index) && series.perWeek[index] > 0
            }
            guard everybody else { break }
            count += 1
        }
        return count
    }

    /// The matchweek in which the title changed hands for the last time — `nil` when
    /// the leader never changed.
    func leadChangeWeek() -> Int? {
        guard let race else { return nil }
        return LeadChange.week(of: race)
    }

    /// The rival of the signed in player: the member directly above or below.
    func rival() -> RaceSeries? {
        guard let race, let myUserID else { return nil }
        let mine = race.series.first { $0.user.id == myUserID }
        guard let mine else { return nil }
        let others = race.series.filter { $0.user.id != myUserID }
        guard let closest = others.min(by: { lhs, rhs in
            let left = abs((lhs.cumulative.last ?? 0) - (mine.cumulative.last ?? 0))
            let right = abs((rhs.cumulative.last ?? 0) - (mine.cumulative.last ?? 0))
            return left < right
        }) else { return nil }
        return closest
    }

    // MARK: - Actions

    func vote(on submission: Submission, approve: Bool, api: any APIClientProtocol) async -> Submission? {
        do {
            let response = try await api.vote(submissionID: submission.id, approve: approve)
            replaceInFeed(response.submission)
            pendingVotes.removeAll { $0.id == submission.id }
            return response.submission
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    func updateGroup(
        name: String?,
        challengesPerWeek: Int?,
        theme: String?,
        language: String?,
        timezone: String?,
        forfeit: String?,
        api: any APIClientProtocol
    ) async -> Bool {
        do {
            let request = UpdateGroupRequest(
                name: name,
                challengesPerWeek: challengesPerWeek,
                theme: theme,
                language: language,
                timezone: timezone,
                forfeit: forfeit
            )
            let response = try await api.updateGroup(id: groupID, request: request)
            group = response.group
            errorMessage = nil
            return true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func leave(api: any APIClientProtocol) async -> Bool {
        do {
            _ = try await api.leaveGroup(id: groupID)
            return true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    // MARK: - v3 actions

    /// Toggles one of the six reactions of a proof.
    func toggleReaction(
        on submission: Submission,
        emoji: ReactionEmoji,
        api: any APIClientProtocol
    ) async -> Submission? {
        do {
            let updated = try await api.toggleReaction(submissionID: submission.id, emoji: emoji)
            replaceInFeed(updated)
            return updated
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    /// Vetoes a fixture — it is replaced when the club has the majority.
    func veto(
        challengeID: String,
        api: any APIClientProtocol
    ) async -> VetoResponse? {
        do {
            let response = try await api.vetoChallenge(id: challengeID)
            await load(api: api, myUserID: myUserID ?? "")
            errorMessage = nil
            return response
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    /// Chooses the captain fixture of the matchweek.
    func setCaptain(challengeID: String, api: any APIClientProtocol) async -> Bool {
        do {
            let response = try await api.setCaptain(groupID: groupID, challengeID: challengeID)
            myCaptainChallengeID = response.week?.myCaptainChallengeId ?? challengeID
            if let challenge = response.challenge,
               let index = fixtures.firstIndex(where: { $0.id == challenge.id })
            {
                fixtures[index] = challenge
            }
            errorMessage = nil
            return true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    /// Writes the house fixture of the matchweek.
    func addHouseFixture(
        title: String,
        description: String,
        difficulty: Difficulty,
        api: any APIClientProtocol
    ) async -> Challenge? {
        do {
            let challenge = try await api.addHouseFixture(
                groupID: groupID,
                request: HouseFixtureRequest(
                    title: title,
                    description: description,
                    difficulty: difficulty
                )
            )
            await load(api: api, myUserID: myUserID ?? "")
            errorMessage = nil
            return challenge
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    /// Deletes my own proof.
    func deleteSubmission(id: String, api: any APIClientProtocol) async -> Bool {
        do {
            _ = try await api.deleteSubmission(id: id)
            feed.removeAll { $0.id == id }
            pendingVotes.removeAll { $0.id == id }
            errorMessage = nil
            return true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    /// Reports a proof — it is hidden for me at once.
    func report(submissionID: String, reason: ReportReason, note: String?, api: any APIClientProtocol) async -> Bool {
        do {
            _ = try await api.reportSubmission(
                id: submissionID,
                request: ReportRequest(reason: reason, note: note)
            )
            feed.removeAll { $0.id == submissionID }
            pendingVotes.removeAll { $0.id == submissionID }
            errorMessage = nil
            return true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    /// Blocks a member — their proofs disappear for me.
    func block(userID: String, api: any APIClientProtocol) async -> Bool {
        do {
            _ = try await api.blockUser(userID)
            feed.removeAll { $0.user.id == userID }
            pendingVotes.removeAll { $0.user.id == userID }
            errorMessage = nil
            return true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    private func replaceInFeed(_ submission: Submission) {
        guard let index = feed.firstIndex(where: { $0.id == submission.id }) else {
            feed.insert(submission, at: 0)
            return
        }
        feed[index] = submission
    }
}
