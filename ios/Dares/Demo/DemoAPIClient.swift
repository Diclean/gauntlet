import Foundation

/// The offline twin of `APIClient`: it answers every endpoint of `APIClientProtocol` from an
/// in-memory world that follows the rules of SPEC.md (voting thresholds, the point ledger,
/// streaks, one active submission per challenge).
///
/// The demo never touches the network and never touches the Keychain.
actor DemoAPIClient: APIClientProtocol {
    private var store: DemoStore
    private let autoSimulate: Bool
    private let simulationDelay: TimeInterval
    private var didStartSimulations = false

    init(now: Date = Date(), autoSimulate: Bool = true, simulationDelay: TimeInterval = 3) {
        var store = DemoStore()
        store.seed(now: now, simulationDelay: simulationDelay)
        self.store = store
        self.autoSimulate = autoSimulate
        self.simulationDelay = simulationDelay
    }

    // MARK: - Account

    func authenticate(_ request: AppleAuthRequest) async throws -> AuthResponse {
        guard let user = store.users[store.currentUserID] else { throw APIError.unauthorized }
        return AuthResponse(token: "demo-session-token", user: user)
    }

    func currentUser() async throws -> MeResponse {
        startSimulationsIfNeeded()
        guard let user = store.users[store.currentUserID] else {
            throw APIError.server(code: "no_user", message: "This demo account is gone.", status: 404)
        }
        return MeResponse(user: user)
    }

    /// The demo has no server and no session to delete.
    func logout() async throws -> OKResponse {
        OKResponse(ok: true)
    }

    func updateProfile(_ request: UpdateMeRequest) async throws -> MeResponse {
        let user = store.updateUser(displayName: request.displayName, avatarEmoji: request.avatarEmoji)
        return MeResponse(user: user)
    }

    func deleteAccount() async throws -> OKResponse {
        store.removeCurrentUser()
        return OKResponse(ok: true)
    }

    func registerDevice(token: String) async throws -> OKResponse {
        // The demo has no push notifications.
        OKResponse(ok: true)
    }

    // MARK: - Groups

    func groups() async throws -> GroupsResponse {
        startSimulationsIfNeeded()
        return GroupsResponse(groups: store.groups(for: store.currentUserID))
    }

    func createGroup(_ request: CreateGroupRequest) async throws -> GroupResponse {
        let group = try store.createGroup(
            name: request.name,
            challengesPerWeek: request.challengesPerWeek ?? 5,
            theme: request.theme,
            language: request.language ?? "en",
            timezone: request.timezone ?? TimeZone.current.identifier,
            ownerID: store.currentUserID
        )
        return GroupResponse(group: group)
    }

    func joinGroup(_ request: JoinGroupRequest) async throws -> GroupResponse {
        let group = try store.joinGroup(inviteCode: request.inviteCode, userID: store.currentUserID)
        return GroupResponse(group: group)
    }

    func groupDetail(id: String) async throws -> GroupDetailResponse {
        startSimulationsIfNeeded()
        guard let group = store.group(id: id),
              store.memberIDs[id]?.contains(store.currentUserID) == true
        else {
            throw APIError.server(
                code: "not_a_member",
                message: "You are not a member of this group.",
                status: 403
            )
        }
        return GroupDetailResponse(group: group, members: store.members(of: id))
    }

    func updateGroup(id: String, request: UpdateGroupRequest) async throws -> GroupResponse {
        let group = try store.updateGroup(id: id, request: request, userID: store.currentUserID)
        return GroupResponse(group: group)
    }

    func leaveGroup(id: String) async throws -> OKResponse {
        store.leaveGroup(id: id, userID: store.currentUserID)
        return OKResponse(ok: true)
    }

    func currentWeek(groupID: String) async throws -> WeekResponse {
        startSimulationsIfNeeded()
        guard let week = store.apiWeek(groupID: groupID, viewerID: store.currentUserID) else {
            throw APIError.server(code: "not_found", message: "That group does not exist.", status: 404)
        }
        return WeekResponse(
            week: week,
            challenges: store.challenges(groupID: groupID, viewerID: store.currentUserID),
            houseFixture: store.houseFixtureInfo(groupID: groupID, viewerID: store.currentUserID)
        )
    }

    func feed(groupID: String, cursor: String?) async throws -> FeedResponse {
        startSimulationsIfNeeded()
        let page = store.feed(groupID: groupID, cursor: cursor, viewerID: store.currentUserID)
        return FeedResponse(items: page.items, nextCursor: page.nextCursor)
    }

    func pendingVotes(groupID: String) async throws -> PendingVotesResponse {
        startSimulationsIfNeeded()
        return PendingVotesResponse(items: store.pendingVotes(groupID: groupID, viewerID: store.currentUserID))
    }

    func leaderboard(groupID: String, scope: LeaderboardScope) async throws -> LeaderboardResponse {
        startSimulationsIfNeeded()
        let entries = store.leaderboard(groupID: groupID, scope: scope)
        return LeaderboardResponse(entries: entries)
    }

    // MARK: - v2: Sunday League

    func race(groupID: String) async throws -> RaceResponse {
        startSimulationsIfNeeded()
        return store.race(groupID: groupID, viewerID: store.currentUserID)
    }

    func weeks(groupID: String, limit: Int) async throws -> [Week] {
        startSimulationsIfNeeded()
        let list = store.weeks[groupID] ?? []
        return Array(list.suffix(limit).reversed())
    }

    func receipt(groupID: String, weekID: String) async throws -> ReceiptResponse {
        startSimulationsIfNeeded()
        guard let receipt = store.receipt(
            groupID: groupID,
            weekID: weekID,
            viewerID: store.currentUserID
        ) else {
            throw APIError.server(
                code: "not_found",
                message: "That matchweek does not exist.",
                status: 404
            )
        }
        return receipt
    }

    func awards(groupID: String, month: String?) async throws -> AwardsResponse {
        startSimulationsIfNeeded()
        return store.awards(groupID: groupID, month: month)
    }

    func awardMonths(groupID: String) async throws -> [String] {
        startSimulationsIfNeeded()
        return store.awardMonthList()
    }

    func trophies() async throws -> [Trophy] {
        startSimulationsIfNeeded()
        return store.trophies(userID: store.currentUserID)
    }

    // MARK: - Submissions

    func createSubmission(
        challengeID: String,
        media: ProofUpload,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> SubmissionResponse {
        onProgress(0)
        let mediaKey = "demo-upload/\(UUID().uuidString)"
        store.uploads[mediaKey] = media.data
        let submission = try store.createSubmission(
            challengeID: challengeID,
            mediaType: media.mediaType,
            caption: media.caption,
            mediaKey: mediaKey
        )
        onProgress(1)
        scheduleSimulation(for: submission)
        return SubmissionResponse(submission: store.makeSubmission(submission, viewerID: store.currentUserID))
    }

    func submission(id: String) async throws -> SubmissionResponse {
        guard let submission = store.submission(id: id) else {
            throw APIError.server(code: "not_found", message: "That proof does not exist.", status: 404)
        }
        return SubmissionResponse(submission: store.makeSubmission(submission, viewerID: store.currentUserID))
    }

    func vote(submissionID: String, approve: Bool) async throws -> SubmissionResponse {
        let updated = try store.vote(submissionID: submissionID, approve: approve)
        return SubmissionResponse(submission: store.makeSubmission(updated, viewerID: store.currentUserID))
    }

    // MARK: - Media

    func mediaData(for path: String) async throws -> Data {
        if let data = store.uploads[path] {
            return data
        }
        if let data = DemoMedia.data(for: path) {
            return data
        }
        throw APIError.server(
            code: "media_not_found",
            message: "The demo media could not be found.",
            status: 404
        )
    }

    // MARK: - v3: safety, banter, captain, house fixture

    func acceptTerms() async throws -> MeResponse {
        let user = store.acceptTerms()
        return MeResponse(user: user)
    }

    func notificationPrefs() async throws -> NotificationPrefs {
        store.notificationPrefs(for: store.currentUserID)
    }

    func updateNotificationPrefs(_ prefs: NotificationPrefs) async throws -> NotificationPrefs {
        store.notificationPrefs[store.currentUserID] = prefs
        return prefs
    }

    func blockedUsers() async throws -> [User] {
        store.blockedUsers(for: store.currentUserID)
    }

    func blockUser(_ id: String) async throws -> OKResponse {
        store.block(userID: id, by: store.currentUserID)
        return OKResponse(ok: true)
    }

    func unblockUser(_ id: String) async throws -> OKResponse {
        store.unblock(userID: id, by: store.currentUserID)
        return OKResponse(ok: true)
    }

    func deleteSubmission(id: String) async throws -> OKResponse {
        try store.deleteSubmission(id: id, by: store.currentUserID)
        return OKResponse(ok: true)
    }

    func reportSubmission(id: String, request: ReportRequest) async throws -> OKResponse {
        try store.report(
            targetType: .submission,
            targetID: id,
            reporterID: store.currentUserID,
            reason: request.reason,
            note: request.note,
            groupID: store.submission(id: id)?.groupID ?? ""
        )
        return OKResponse(ok: true)
    }

    func reportComment(id: String, request: ReportRequest) async throws -> OKResponse {
        let groupID = store.groupID(ofComment: id) ?? ""
        try store.report(
            targetType: .comment,
            targetID: id,
            reporterID: store.currentUserID,
            reason: request.reason,
            note: request.note,
            groupID: groupID
        )
        return OKResponse(ok: true)
    }

    func deleteComment(id: String) async throws -> OKResponse {
        try store.deleteComment(id: id, by: store.currentUserID)
        return OKResponse(ok: true)
    }

    func comments(submissionID: String) async throws -> [Comment] {
        let groupID = store.submission(id: submissionID)?.groupID ?? ""
        return store.commentList(submissionID: submissionID, viewerID: store.currentUserID, groupID: groupID)
    }

    func addComment(submissionID: String, text: String) async throws -> Comment {
        let comment = try store.addComment(
            submissionID: submissionID,
            text: text,
            userID: store.currentUserID
        )
        guard let user = store.user(id: comment.userID) else {
            throw APIError.server(code: "not_found", message: "That comment does not exist.", status: 404)
        }
        let groupID = store.submission(id: submissionID)?.groupID ?? ""
        let ownerID = store.ownerID(of: groupID)
        return Comment(
            id: comment.id,
            user: user,
            text: comment.text,
            createdAt: comment.createdAt,
            canDelete: comment.userID == store.currentUserID || ownerID == store.currentUserID
        )
    }

    func toggleReaction(submissionID: String, emoji: ReactionEmoji) async throws -> Submission {
        let submission = try store.toggleReaction(
            submissionID: submissionID,
            emoji: emoji,
            userID: store.currentUserID
        )
        return store.makeSubmission(submission, viewerID: store.currentUserID)
    }

    func vetoChallenge(id: String) async throws -> VetoResponse {
        let result = try store.veto(challengeID: id, by: store.currentUserID)
        return VetoResponse(challenge: result.challenge, replaced: result.replaced)
    }

    func setCaptain(groupID: String, challengeID: String) async throws -> CaptainResponse {
        let week = try store.setCaptain(groupID: groupID, challengeID: challengeID, by: store.currentUserID)
        let challenge = store.challenges(groupID: groupID, viewerID: store.currentUserID)
            .first { $0.id == challengeID }
        return CaptainResponse(week: week, challenge: challenge)
    }

    func addHouseFixture(groupID: String, request: HouseFixtureRequest) async throws -> Challenge {
        try store.addHouseFixture(groupID: groupID, request: request, by: store.currentUserID)
    }

    func removeMember(groupID: String, userID: String) async throws -> OKResponse {
        try store.removeMember(groupID: groupID, userID: userID, by: store.currentUserID)
        return OKResponse(ok: true)
    }

    func bannedMembers(groupID: String) async throws -> [BannedMember] {
        store.bannedMembers(groupID: groupID)
    }

    func unbanMember(groupID: String, userID: String) async throws -> OKResponse {
        try store.unbanMember(groupID: groupID, userID: userID, by: store.currentUserID)
        return OKResponse(ok: true)
    }

    func joinPreview(code: String) async throws -> Group {
        let wanted = code.uppercased()
        guard let id = store.groups.values.first(where: { $0.inviteCode.uppercased() == wanted })?.id,
              let group = store.group(id: id)
        else {
            throw APIError.server(
                code: "not_found",
                message: "That invite code does not match any club.",
                status: 404
            )
        }
        return group
    }

    // MARK: - Simulated votes

    /// The demo plays the other members: a short while after a proof is sent, they vote
    /// on it, so the accept flow can be seen without a second person.
    private func scheduleSimulation(for submission: DemoSubmission) {
        let approvalsNeeded = min(2, submission.eligibleVoters)
        guard approvalsNeeded > 0 else { return }
        let voters = Array(store.voters(groupID: submission.groupID, excluding: submission.userID).prefix(approvalsNeeded))
        guard !voters.isEmpty else { return }
        enqueue(
            DemoSimulation(
                id: "demo-simulation-\(UUID().uuidString)",
                submissionID: submission.id,
                votes: voters.map { DemoSimulatedVote(voterID: $0, approve: true) },
                delay: simulationDelay
            )
        )
    }

    private func enqueue(_ simulation: DemoSimulation) {
        store.pendingSimulations.append(simulation)
        guard autoSimulate else { return }
        let delay = simulation.delay
        Task.detached { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            await self?.applySimulation(simulation.id)
        }
    }

    private func applySimulation(_ id: String) {
        guard let index = store.pendingSimulations.firstIndex(where: { $0.id == id }) else { return }
        let simulation = store.pendingSimulations.remove(at: index)
        for vote in simulation.votes {
            store.castVote(
                submissionID: simulation.submissionID,
                voterID: vote.voterID,
                approve: vote.approve,
                at: Date()
            )
        }
    }

    private func startSimulationsIfNeeded() {
        guard !didStartSimulations else { return }
        didStartSimulations = true
        let pending = store.pendingSimulations
        store.pendingSimulations = []
        for simulation in pending {
            enqueue(simulation)
        }
    }

    // MARK: - Test hooks

    /// Acts as another member of the demo.
    func actAs(_ userID: String) {
        store.setCurrentUser(userID)
    }

    /// Adds a member to a group.
    func addMember(groupID: String, user: User) {
        store.addMember(groupID: groupID, user: user)
    }

    /// Casts a vote as another member.
    func castVoteAs(voterID: String, approve: Bool, submissionID: String) {
        store.castVote(submissionID: submissionID, voterID: voterID, approve: approve, at: Date())
    }

    /// The point ledger of a group.
    func pointEvents(groupID: String) -> [DemoPointEvent] {
        store.pointEvents(groupID: groupID)
    }

    /// Plays every scheduled vote right now.
    func applyScheduledSimulations() {
        let pending = store.pendingSimulations
        store.pendingSimulations = []
        for simulation in pending {
            for vote in simulation.votes {
                store.castVote(
                    submissionID: simulation.submissionID,
                    voterID: vote.voterID,
                    approve: vote.approve,
                    at: Date()
                )
            }
        }
    }
}
