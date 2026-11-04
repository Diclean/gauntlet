import Foundation

/// Every endpoint the app talks to (SPEC.md, section 3).
///
/// `APIClient` speaks to the real Cloudflare Worker, `DemoAPIClient` answers from an
/// in-memory store. Views only ever see this protocol, so no view ever references a
/// concrete client and demo mode can be swapped in at runtime.
protocol APIClientProtocol: Sendable {
    // MARK: - Account

    func authenticate(_ request: AppleAuthRequest) async throws -> AuthResponse
    func currentUser() async throws -> MeResponse
    /// `POST /auth/logout` — ends the session of the bearer token.
    func logout() async throws -> OKResponse
    func updateProfile(_ request: UpdateMeRequest) async throws -> MeResponse
    func deleteAccount() async throws -> OKResponse
    func registerDevice(token: String) async throws -> OKResponse

    // MARK: - Groups

    func groups() async throws -> GroupsResponse
    func createGroup(_ request: CreateGroupRequest) async throws -> GroupResponse
    func joinGroup(_ request: JoinGroupRequest) async throws -> GroupResponse
    func groupDetail(id: String) async throws -> GroupDetailResponse
    func updateGroup(id: String, request: UpdateGroupRequest) async throws -> GroupResponse
    func leaveGroup(id: String) async throws -> OKResponse
    func currentWeek(groupID: String) async throws -> WeekResponse
    func feed(groupID: String, cursor: String?) async throws -> FeedResponse
    func pendingVotes(groupID: String) async throws -> PendingVotesResponse
    func leaderboard(groupID: String, scope: LeaderboardScope) async throws -> LeaderboardResponse

    // MARK: - v2: Sunday League

    /// The title race: the points of every member, matchweek by matchweek.
    func race(groupID: String) async throws -> RaceResponse
    /// The past matchweeks, newest first.
    func weeks(groupID: String, limit: Int) async throws -> [Week]
    /// The full-time receipt of a matchweek.
    func receipt(groupID: String, weekID: String) async throws -> ReceiptResponse
    /// The awards of a month (`YYYY-MM`). Without a month the latest one is returned.
    func awards(groupID: String, month: String?) async throws -> AwardsResponse
    /// The months that have awards, newest first.
    func awardMonths(groupID: String) async throws -> [String]
    /// The trophy cabinet of the signed in player.
    func trophies() async throws -> [Trophy]

    // MARK: - Submissions

    func createSubmission(
        challengeID: String,
        media: ProofUpload,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> SubmissionResponse

    func submission(id: String) async throws -> SubmissionResponse
    func vote(submissionID: String, approve: Bool) async throws -> SubmissionResponse

    // MARK: - Media

    /// Raw bytes of a proof. The real client streams `/media/<key>` with the bearer token.
    func mediaData(for path: String) async throws -> Data

    // MARK: - v3: safety, banter, captain, house fixture

    /// Accept the house rules (SPEC.md, section 6.1). Required before any write.
    func acceptTerms() async throws -> MeResponse
    /// The push switches of the player (SPEC.md, section 6.4).
    func notificationPrefs() async throws -> NotificationPrefs
    /// Change the push switches of the player (SPEC.md, section 6.4).
    func updateNotificationPrefs(_ prefs: NotificationPrefs) async throws -> NotificationPrefs
    /// The players the signed in player blocked (SPEC.md, section 6.2).
    func blockedUsers() async throws -> [User]
    /// Block a player — their proofs and comments disappear for me (SPEC.md, section 6.2).
    func blockUser(_ id: String) async throws -> OKResponse
    /// Unblock a player (SPEC.md, section 6.2).
    func unblockUser(_ id: String) async throws -> OKResponse
    /// Delete my own proof (SPEC.md, section 6.2).
    func deleteSubmission(id: String) async throws -> OKResponse
    /// Report a proof (SPEC.md, section 6.2).
    func reportSubmission(id: String, request: ReportRequest) async throws -> OKResponse
    /// Report a comment (SPEC.md, section 6.2).
    func reportComment(id: String, request: ReportRequest) async throws -> OKResponse
    /// Delete a comment — the author or the owner of the club (SPEC.md, section 6.5).
    func deleteComment(id: String) async throws -> OKResponse
    /// The comments of a proof, oldest first (SPEC.md, section 6.5).
    func comments(submissionID: String) async throws -> [Comment]
    /// Write a comment (SPEC.md, section 6.5).
    func addComment(submissionID: String, text: String) async throws -> Comment
    /// Toggle one of the six reactions of a proof (SPEC.md, section 6.5).
    func toggleReaction(submissionID: String, emoji: ReactionEmoji) async throws -> Submission
    /// Veto a fixture — it is replaced when the club has the majority (SPEC.md, section 6.3).
    func vetoChallenge(id: String) async throws -> VetoResponse
    /// Choose the captain fixture of the matchweek (SPEC.md, section 6.6).
    func setCaptain(groupID: String, challengeID: String) async throws -> CaptainResponse
    /// Write the house fixture of the matchweek (SPEC.md, section 6.7).
    func addHouseFixture(groupID: String, request: HouseFixtureRequest) async throws -> Challenge
    /// The owner removes a member of the club (SPEC.md, section 6.2).
    func removeMember(groupID: String, userID: String) async throws -> OKResponse
    /// The members the owner removed from the club (SPEC.md, section 6.2).
    func bannedMembers(groupID: String) async throws -> [BannedMember]
    /// The owner lifts the ban of a member (SPEC.md, section 6.2).
    func unbanMember(groupID: String, userID: String) async throws -> OKResponse
    /// The club behind an invite code — the app never joins on its own (SPEC.md, section 6.8).
    func joinPreview(code: String) async throws -> Group
}
