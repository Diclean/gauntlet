import Foundation

enum APIError: LocalizedError, Sendable {
    case invalidURL
    case invalidResponse
    case missingToken
    /// The server refused the session (401). The token is dead.
    case unauthorized
    /// The server knows the session but refuses the call (403). The token is still good.
    case forbidden
    case server(code: String, message: String, status: Int)
    case decoding(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return String(localized: "error.invalid_url")
        case .invalidResponse:
            return String(localized: "error.invalid_response")
        case .missingToken:
            return String(localized: "error.missing_token")
        case .unauthorized:
            return String(localized: "error.unauthorized")
        case .forbidden:
            return String(localized: "error.forbidden")
        case let .server(_, message, _):
            return message
        case .decoding:
            return String(localized: "error.decoding")
        case let .transport(message):
            return message
        }
    }
}

/// Bridges any `Encodable` existential into `JSONEncoder`.
private struct AnyEncodable: Encodable {
    private let encodeValue: (any Encoder) throws -> Void

    init(_ value: any Encodable) {
        encodeValue = { encoder in try value.encode(to: encoder) }
    }

    func encode(to encoder: any Encoder) throws {
        try encodeValue(encoder)
    }
}

struct APIClient: Sendable {
    let baseURL: URL
    let vault: TokenVault

    private let session: URLSession

    init(baseURL: URL, vault: TokenVault, session: URLSession? = nil) {
        self.baseURL = baseURL
        self.vault = vault

        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 120
            configuration.waitsForConnectivity = true
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: configuration)
        }
    }

    // MARK: - Requests

    func send<T: Decodable & Sendable>(
        _ endpoint: Endpoint,
        body: (any Encodable & Sendable)? = nil,
        as type: T.Type = T.self
    ) async throws -> T {
        var request = try await makeRequest(for: endpoint)
        if let body {
            request.httpBody = try JSONEncoder().encode(AnyEncodable(body))
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decode(data, as: type)
    }

    /// Uploads a `multipart/form-data` body, reporting progress in `0...1`.
    func upload<T: Decodable & Sendable>(
        _ endpoint: Endpoint,
        multipart: MultipartBody,
        as type: T.Type = T.self,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> T {
        var request = try await makeRequest(for: endpoint)
        request.setValue(multipart.contentType, forHTTPHeaderField: "Content-Type")

        let delegate = UploadProgressDelegate(onProgress: onProgress)
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 600
        let uploadSession = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { uploadSession.finishTasksAndInvalidate() }

        let (data, response) = try await uploadSession.upload(for: request, from: multipart.body)
        try validate(response: response, data: data)
        return try decode(data, as: type)
    }

    /// Absolute URL for a relative media path such as `/media/<key>`.
    ///
    /// The media of a club never leaves the host of the API: an absolute URL of
    /// another host is refused, so a hostile payload can never make the app send
    /// the bearer token to a stranger.
    func mediaURL(for path: String) throws -> URL {
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            guard
                let url = URL(string: path),
                url.host == baseURL.host,
                url.port == baseURL.port,
                url.scheme?.lowercased() == baseURL.scheme?.lowercased()
            else {
                throw APIError.invalidURL
            }
            return url
        }
        guard path.hasPrefix("/"), !path.contains("..") else {
            throw APIError.invalidURL
        }
        return try makeURL(percentEncodedPath: PathComponent.encodePath(path), query: [])
    }

    /// Downloads raw bytes for a media path, using the bearer token.
    func mediaData(for path: String) async throws -> Data {
        let url = try mediaURL(for: path)
        guard let token = await vault.currentToken() else {
            throw APIError.missingToken
        }
        var request = URLRequest(url: url)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return data
    }

    // MARK: - Helpers

    /// Builds the URL of a request.
    ///
    /// The path is already percent encoded (the ids are encoded in `Endpoint`), so
    /// it is never encoded a second time.
    private func makeURL(percentEncodedPath path: String, query: [URLQueryItem]) throws -> URL {
        var base = baseURL.absoluteString
        while base.hasSuffix("/") {
            base.removeLast()
        }
        let suffix: String
        if path.isEmpty {
            suffix = ""
        } else {
            suffix = path.hasPrefix("/") ? path : "/" + path
        }
        guard var components = URLComponents(string: base + suffix) else {
            throw APIError.invalidURL
        }
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else {
            throw APIError.invalidURL
        }
        return url
    }

    private func makeRequest(for endpoint: Endpoint) async throws -> URLRequest {
        let finalURL = try makeURL(percentEncodedPath: endpoint.path, query: endpoint.query)

        var request = URLRequest(url: finalURL)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if endpoint.requiresAuth {
            guard let token = await vault.currentToken() else {
                throw APIError.missingToken
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        switch httpResponse.statusCode {
        case 200 ..< 300:
            return
        case 401:
            // The session is dead: the app has to sign in again.
            throw APIError.unauthorized
        case 403:
            // The session is good, the call is not allowed.
            throw APIError.forbidden
        default:
            if let envelope = try? APIJSON.decoder().decode(APIErrorEnvelope.self, from: data) {
                throw APIError.server(
                    code: envelope.error.code,
                    message: envelope.error.message,
                    status: httpResponse.statusCode
                )
            }
            throw APIError.server(
                code: "http_\(httpResponse.statusCode)",
                message: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode),
                status: httpResponse.statusCode
            )
        }
    }

    private func decode<T: Decodable>(_ data: Data, as type: T.Type) throws -> T {
        do {
            return try APIJSON.decoder().decode(type, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }
}

/// Reports upload progress for a single multipart request.
final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        let fraction = min(max(Double(totalBytesSent) / Double(totalBytesExpectedToSend), 0), 1)
        lock.lock()
        let handler = onProgress
        lock.unlock()
        handler(fraction)
    }
}

// MARK: - APIClientProtocol

extension APIClient: APIClientProtocol {
    // MARK: Account

    func authenticate(_ request: AppleAuthRequest) async throws -> AuthResponse {
        try await send(.appleAuth, body: request, as: AuthResponse.self)
    }

    func currentUser() async throws -> MeResponse {
        try await send(.me, as: MeResponse.self)
    }

    /// `POST /auth/logout` — the server deletes the session of the bearer token.
    func logout() async throws -> OKResponse {
        try await send(.logout, as: OKResponse.self)
    }

    func updateProfile(_ request: UpdateMeRequest) async throws -> MeResponse {
        try await send(.updateMe, body: request, as: MeResponse.self)
    }

    func deleteAccount() async throws -> OKResponse {
        try await send(.deleteMe, as: OKResponse.self)
    }

    func registerDevice(token: String) async throws -> OKResponse {
        try await send(.registerDevice, body: DeviceRequest(apnsToken: token), as: OKResponse.self)
    }

    // MARK: Groups

    func groups() async throws -> GroupsResponse {
        try await send(.groups, as: GroupsResponse.self)
    }

    func createGroup(_ request: CreateGroupRequest) async throws -> GroupResponse {
        try await send(.createGroup, body: request, as: GroupResponse.self)
    }

    func joinGroup(_ request: JoinGroupRequest) async throws -> GroupResponse {
        try await send(.joinGroup, body: request, as: GroupResponse.self)
    }

    func groupDetail(id: String) async throws -> GroupDetailResponse {
        try await send(.group(id), as: GroupDetailResponse.self)
    }

    func updateGroup(id: String, request: UpdateGroupRequest) async throws -> GroupResponse {
        try await send(.updateGroup(id), body: request, as: GroupResponse.self)
    }

    func leaveGroup(id: String) async throws -> OKResponse {
        try await send(.leaveGroup(id), as: OKResponse.self)
    }

    func currentWeek(groupID: String) async throws -> WeekResponse {
        try await send(.groupWeek(groupID), as: WeekResponse.self)
    }

    func feed(groupID: String, cursor: String?) async throws -> FeedResponse {
        try await send(.groupFeed(groupID, cursor: cursor), as: FeedResponse.self)
    }

    func pendingVotes(groupID: String) async throws -> PendingVotesResponse {
        try await send(.groupPendingVotes(groupID), as: PendingVotesResponse.self)
    }

    func leaderboard(groupID: String, scope: LeaderboardScope) async throws -> LeaderboardResponse {
        try await send(.groupLeaderboard(groupID, scope: scope), as: LeaderboardResponse.self)
    }

    // MARK: v2 — Sunday League

    func race(groupID: String) async throws -> RaceResponse {
        try await send(.groupRace(groupID), as: RaceResponse.self)
    }

    func weeks(groupID: String, limit: Int) async throws -> [Week] {
        try await send(.groupWeeks(groupID, limit: limit), as: WeeksResponse.self).weeks
    }

    func receipt(groupID: String, weekID: String) async throws -> ReceiptResponse {
        try await send(.groupReceipt(groupID, weekID: weekID), as: ReceiptResponse.self)
    }

    func awards(groupID: String, month: String?) async throws -> AwardsResponse {
        try await send(.groupAwards(groupID, month: month), as: AwardsResponse.self)
    }

    func awardMonths(groupID: String) async throws -> [String] {
        try await send(.groupAwardMonths(groupID), as: AwardMonthsResponse.self).months
    }

    func trophies() async throws -> [Trophy] {
        try await send(.myTrophies, as: TrophiesResponse.self).trophies
    }

    // MARK: Submissions

    func createSubmission(
        challengeID: String,
        media: ProofUpload,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> SubmissionResponse {
        let file = FilePart(
            fieldName: "media",
            fileName: media.fileName,
            mimeType: media.mimeType,
            data: media.data
        )
        let multipart = MultipartBody(
            fields: [
                "mediaType": media.mediaType.rawValue,
                "caption": media.caption ?? "",
            ],
            file: file
        )
        return try await upload(
            .createSubmission(challengeID: challengeID),
            multipart: multipart,
            as: SubmissionResponse.self,
            onProgress: onProgress
        )
    }

    func submission(id: String) async throws -> SubmissionResponse {
        try await send(.submission(id), as: SubmissionResponse.self)
    }

    func vote(submissionID: String, approve: Bool) async throws -> SubmissionResponse {
        try await send(.vote(submissionID), body: VoteRequest(approve: approve), as: SubmissionResponse.self)
    }

    // MARK: v3 — safety, banter, captain, house fixture

    func acceptTerms() async throws -> MeResponse {
        try await send(.acceptTerms, as: MeResponse.self)
    }

    func notificationPrefs() async throws -> NotificationPrefs {
        try await send(.notificationPrefs, as: NotificationPrefs.self)
    }

    func updateNotificationPrefs(_ prefs: NotificationPrefs) async throws -> NotificationPrefs {
        try await send(.updateNotificationPrefs, body: prefs, as: NotificationPrefs.self)
    }

    func blockedUsers() async throws -> [User] {
        try await send(.myBlocks, as: BlocksResponse.self).users
    }

    func blockUser(_ id: String) async throws -> OKResponse {
        try await send(.blockUser(id), as: OKResponse.self)
    }

    func unblockUser(_ id: String) async throws -> OKResponse {
        try await send(.unblockUser(id), as: OKResponse.self)
    }

    func deleteSubmission(id: String) async throws -> OKResponse {
        try await send(.deleteSubmission(id), as: OKResponse.self)
    }

    func reportSubmission(id: String, request: ReportRequest) async throws -> OKResponse {
        try await send(.reportSubmission(id), body: request, as: OKResponse.self)
    }

    func reportComment(id: String, request: ReportRequest) async throws -> OKResponse {
        try await send(.reportComment(id), body: request, as: OKResponse.self)
    }

    func deleteComment(id: String) async throws -> OKResponse {
        try await send(.deleteComment(id), as: OKResponse.self)
    }

    func comments(submissionID: String) async throws -> [Comment] {
        try await send(.comments(submissionID), as: CommentsResponse.self).comments
    }

    func addComment(submissionID: String, text: String) async throws -> Comment {
        let response = try await send(
            .addComment(submissionID),
            body: CommentRequest(text: text),
            as: CommentResponse.self
        )
        return response.comment
    }

    func toggleReaction(submissionID: String, emoji: ReactionEmoji) async throws -> Submission {
        let response = try await send(
            .reactions(submissionID),
            body: ReactionRequest(emoji: emoji.rawValue),
            as: SubmissionResponse.self
        )
        return response.submission
    }

    func vetoChallenge(id: String) async throws -> VetoResponse {
        try await send(.vetoChallenge(id), as: VetoResponse.self)
    }

    func setCaptain(groupID: String, challengeID: String) async throws -> CaptainResponse {
        try await send(
            .setCaptain(groupID: groupID),
            body: CaptainRequest(challengeId: challengeID),
            as: CaptainResponse.self
        )
    }

    func addHouseFixture(groupID: String, request: HouseFixtureRequest) async throws -> Challenge {
        let response = try await send(
            .addHouseFixture(groupID: groupID),
            body: request,
            as: ChallengeResponse.self
        )
        return response.challenge
    }

    func removeMember(groupID: String, userID: String) async throws -> OKResponse {
        try await send(.removeMember(groupID: groupID, userID: userID), as: OKResponse.self)
    }

    func bannedMembers(groupID: String) async throws -> [BannedMember] {
        try await send(.bans(groupID: groupID), as: BannedMembersResponse.self).users
    }

    func unbanMember(groupID: String, userID: String) async throws -> OKResponse {
        try await send(.unbanMember(groupID: groupID, userID: userID), as: OKResponse.self)
    }

    func joinPreview(code: String) async throws -> Group {
        try await send(.joinPreview(code: code), as: JoinPreviewResponse.self).group
    }
}
