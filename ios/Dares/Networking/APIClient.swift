import Foundation

enum APIError: LocalizedError, Sendable {
    case invalidURL
    case invalidResponse
    case missingToken
    case unauthorized
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

    init(baseURL: URL, vault: TokenVault) {
        self.baseURL = baseURL
        self.vault = vault

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
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
    func mediaURL(for path: String) -> URL {
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path) ?? baseURL
        }
        return baseURL.appending(path: path)
    }

    /// Downloads raw bytes for a media path, using the bearer token.
    func mediaData(for path: String) async throws -> Data {
        let endpoint = Endpoint(method: .get, path: path)
        var request = try await makeRequest(for: endpoint)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return data
    }

    // MARK: - Helpers

    private func makeRequest(for endpoint: Endpoint) async throws -> URLRequest {
        let url = baseURL.appending(path: endpoint.path)
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        if !endpoint.query.isEmpty {
            components.queryItems = endpoint.query
        }
        guard let finalURL = components.url else {
            throw APIError.invalidURL
        }

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
        case 401, 403:
            throw APIError.unauthorized
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
}
