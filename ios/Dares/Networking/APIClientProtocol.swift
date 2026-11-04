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
}
