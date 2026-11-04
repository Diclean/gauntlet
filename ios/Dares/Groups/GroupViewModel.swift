import Foundation
import Observation

/// Loads and caches everything that belongs to a single group.
@MainActor
@Observable
final class GroupViewModel {
    let groupID: String

    var group: Group?
    var members: [Member] = []
    var week: Week?
    var challenges: [Challenge] = []
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

    /// Keeps the screen up to date while the group is open (the demo plays the other
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
        model.challenges = MockData.challenges
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

    var myChallenges: [Challenge] {
        challenges.sorted { $0.position < $1.position }
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

            let (detailResponse, weekResponse, feedResponse, boardResponse, pendingResponse) =
                try await (detailTask, weekTask, feedTask, boardTask, pendingTask)

            self.myUserID = myUserID
            group = detailResponse.group
            members = detailResponse.members
            week = weekResponse.week
            challenges = weekResponse.challenges.sorted { $0.position < $1.position }
            feed = feedResponse.items
            nextCursor = feedResponse.nextCursor
            leaderboard = boardResponse.entries
            pendingVotes = pendingResponse.items
            errorMessage = nil
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Reloads what can change while the group screen is open: the week, the proofs that
    /// wait for my vote and the leaderboard.
    func refreshLiveState(api: any APIClientProtocol) async {
        do {
            async let weekTask = api.currentWeek(groupID: groupID)
            async let pendingTask = api.pendingVotes(groupID: groupID)
            async let boardTask = api.leaderboard(groupID: groupID, scope: scope)
            let (weekResponse, pendingResponse, boardResponse) = try await (weekTask, pendingTask, boardTask)
            week = weekResponse.week
            challenges = weekResponse.challenges.sorted { $0.position < $1.position }
            pendingVotes = pendingResponse.items
            leaderboard = boardResponse.entries
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Starts the periodic refresh of the group. It lives in the model, so it keeps
    /// running while a screen is pushed on top of the group.
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
        api: any APIClientProtocol
    ) async -> Bool {
        do {
            let request = UpdateGroupRequest(
                name: name,
                challengesPerWeek: challengesPerWeek,
                theme: theme,
                language: language,
                timezone: timezone
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

    private func replaceInFeed(_ submission: Submission) {
        guard let index = feed.firstIndex(where: { $0.id == submission.id }) else {
            feed.insert(submission, at: 0)
            return
        }
        feed[index] = submission
    }
}
