import XCTest
@testable import Dares

/// A Keychain that only lives in the memory: the tests never touch the real one.
final class InMemoryKeychain: KeychainStoring, @unchecked Sendable {
    private var value: String?
    private let lock = NSLock()

    func save(_ newValue: String) throws {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }

    func read() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func delete() throws {
        lock.lock()
        defer { lock.unlock() }
        value = nil
    }
}

/// A `URLProtocol` that answers every request with the same result.
final class StubURLProtocol: URLProtocol {
    enum Behaviour {
        case failure(Error)
        case response(status: Int, body: Data)
    }

    nonisolated(unsafe) static var behaviour: Behaviour = .failure(URLError(.notConnectedToInternet))

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        switch Self.behaviour {
        case let .failure(error):
            client?.urlProtocol(self, didFailWithError: error)
        case let .response(status, body):
            guard let url = request.url,
                  let response = HTTPURLResponse(
                      url: url,
                      statusCode: status,
                      httpVersion: "HTTP/1.1",
                      headerFields: ["Content-Type": "application/json"]
                  )
            else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}

    /// A session that answers with the stub.
    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 5
        return URLSession(configuration: configuration)
    }
}

// MARK: - The media on the disk

final class MediaStoreTests: XCTestCase {
    func testTheMediaStoreDeletesItsFilesOnPurge() async throws {
        let store = MediaStore()
        let client = DemoAPIClient(autoSimulate: false)

        let url = try await store.videoURL(for: DemoMedia.videoKey, using: client)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let videosBefore = await store.cachedVideoCount
        XCTAssertEqual(videosBefore, 1)

        // The file of a video of the club is protected: it is unreadable while the
        // device is locked. The simulator does not know the complete protection — it
        // always reports "until the first unlock" — but the attribute is set.
        let values = try url.resourceValues(forKeys: [.fileProtectionKey])
        XCTAssertNotNil(values.fileProtection)
        XCTAssertNotEqual(values.fileProtection, .none)

        _ = try await store.data(for: DemoMedia.photoKey(1), using: client)
        let imagesBefore = await store.cachedImageCount
        XCTAssertEqual(imagesBefore, 1)

        await store.purge()

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let videosAfter = await store.cachedVideoCount
        let imagesAfter = await store.cachedImageCount
        XCTAssertEqual(videosAfter, 0)
        XCTAssertEqual(imagesAfter, 0)
    }

    func testThePurgeOfAnEmptyStoreIsHarmless() async {
        let store = MediaStore()
        await store.purge()
        let videos = await store.cachedVideoCount
        XCTAssertEqual(videos, 0)
    }
}

// MARK: - The ids of the deep links

final class DeepLinkIdentifierTests: XCTestCase {
    func testOnlyTheWellFormedIdsAreAccepted() {
        XCTAssertTrue(SafeIdentifier.isValid("g_1"))
        XCTAssertTrue(SafeIdentifier.isValid("abc-123_XYZ"))
        XCTAssertTrue(SafeIdentifier.isValid("a"))

        XCTAssertFalse(SafeIdentifier.isValid(""))
        XCTAssertFalse(SafeIdentifier.isValid("../admin"))
        XCTAssertFalse(SafeIdentifier.isValid("a/b"))
        XCTAssertFalse(SafeIdentifier.isValid("a b"))
        XCTAssertFalse(SafeIdentifier.isValid("a?b=c"))
        XCTAssertFalse(SafeIdentifier.isValid(String(repeating: "a", count: 65)))

        XCTAssertNil(SafeIdentifier.valid(nil))
        XCTAssertEqual(SafeIdentifier.valid("g_1"), "g_1")
    }

    @MainActor
    func testTheRouterRefusesAHostileId() {
        let router = AppRouter()

        router.open(groupID: "../admin")
        XCTAssertTrue(router.path.isEmpty)

        router.open(groupID: "g_1", submissionID: "s 1")
        XCTAssertEqual(router.path, [.group("g_1")])
        XCTAssertNil(router.pendingSubmissionID)

        router.open(groupID: "g_1", submissionID: "s_1")
        XCTAssertEqual(router.pendingSubmissionID, "s_1")
    }

    @MainActor
    func testTheDeepLinkRouterDropsAHostileId() {
        let router = DeepLinkRouter()
        var received: (String?, String?)?
        router.handler = { received = ($0, $1) }

        router.handle(groupID: "../admin", submissionID: "s_1")
        XCTAssertNil(received?.0)
        XCTAssertEqual(received?.1, "s_1")

        router.handle(groupID: "g_1", submissionID: nil)
        XCTAssertEqual(received?.0, "g_1")
        XCTAssertNil(received?.1)
    }

    func testAnInviteLinkWithAHostileCodeHasNoCode() throws {
        let url = try XCTUnwrap(URL(string: "gauntlet://join/..%2F.."))
        XCTAssertNil(InviteLink.code(from: url))

        let good = try XCTUnwrap(URL(string: "gauntlet://join/K7M2PQ"))
        XCTAssertEqual(InviteLink.code(from: good), "K7M2PQ")
    }
}

// MARK: - The session

@MainActor
final class SessionTests: XCTestCase {
    private func makeVault() -> TokenVault {
        TokenVault(keychain: InMemoryKeychain(), appleKeychain: InMemoryKeychain())
    }

    private func makeClient(vault: TokenVault) -> APIClient {
        APIClient(
            baseURL: URL(string: "https://api.example.com")!,
            vault: vault,
            session: StubURLProtocol.session()
        )
    }

    func testTheTokenSurvivesANetworkError() async throws {
        let vault = makeVault()
        try await vault.store("token-123")

        StubURLProtocol.behaviour = .failure(URLError(.notConnectedToInternet))
        let state = AppState(vault: vault, baseURL: URL(string: "https://api.example.com")!, isDemo: false, api: makeClient(vault: vault))

        await state.bootstrap()

        // The session is still good, only the server was unreachable.
        let token = await vault.currentToken()
        XCTAssertEqual(token, "token-123")
        XCTAssertEqual(state.phase, .signedOut)
        XCTAssertTrue(state.canRetrySession)
        XCTAssertNotNil(state.errorMessage)
    }

    func testTheTokenIsClearedWhenTheServerRefusesIt() async throws {
        let vault = makeVault()
        try await vault.store("token-123")

        StubURLProtocol.behaviour = .response(status: 401, body: Data(#"{"error":{"code":"unauthorized","message":"nope"}}"#.utf8))
        let state = AppState(vault: vault, baseURL: URL(string: "https://api.example.com")!, isDemo: false, api: makeClient(vault: vault))

        await state.bootstrap()

        let token = await vault.currentToken()
        XCTAssertNil(token)
        XCTAssertEqual(state.phase, .signedOut)
        XCTAssertFalse(state.canRetrySession)
    }

    func testTheTokenIsKeptWhenTheServerRefusesTheCall() async throws {
        let vault = makeVault()
        try await vault.store("token-123")

        // A 403 is not a dead session: the token stays.
        StubURLProtocol.behaviour = .response(status: 403, body: Data(#"{"error":{"code":"forbidden","message":"nope"}}"#.utf8))
        let state = AppState(vault: vault, baseURL: URL(string: "https://api.example.com")!, isDemo: false, api: makeClient(vault: vault))

        await state.bootstrap()

        let token = await vault.currentToken()
        XCTAssertEqual(token, "token-123")
        XCTAssertTrue(state.canRetrySession)
    }

    func testTheSignInStoresTheTokenAndTheAppleUserID() async throws {
        let vault = makeVault()

        StubURLProtocol.behaviour = .response(
            status: 200,
            body: Data(#"{"token":"token-123","user":{"id":"u_1","displayName":"Alex"}}"#.utf8)
        )
        let state = AppState(vault: vault, baseURL: URL(string: "https://api.example.com")!, isDemo: false, api: makeClient(vault: vault))

        await state.signIn(
            with: AppleSignInResult(
                identityToken: "identity",
                rawNonce: "nonce",
                displayName: "Alex",
                appleUserID: "apple-user-1"
            )
        )

        let token = await vault.currentToken()
        XCTAssertEqual(token, "token-123")
        let appleUserID = await vault.appleUserID()
        XCTAssertEqual(appleUserID, "apple-user-1")
    }

    func testTheDemoNeverWritesToTheKeychain() async {
        let vault = makeVault()
        let state = AppState(vault: vault, baseURL: URL(string: "https://api.example.com")!, isDemo: true)

        await state.signIn(
            with: AppleSignInResult(
                identityToken: "identity",
                rawNonce: "nonce",
                displayName: "Alex",
                appleUserID: "apple-user-1"
            )
        )

        let token = await vault.currentToken()
        XCTAssertNil(token)
        let appleUserID = await vault.appleUserID()
        XCTAssertNil(appleUserID)
    }

    func testTheSignOutClearsTheKeychain() async throws {
        let vault = makeVault()
        try await vault.store("token-123")
        try await vault.storeAppleUserID("apple-user-1")

        StubURLProtocol.behaviour = .response(status: 200, body: Data(#"{"ok":true}"#.utf8))
        let state = AppState(vault: vault, baseURL: URL(string: "https://api.example.com")!, isDemo: false, api: makeClient(vault: vault))

        await state.signOut()

        let token = await vault.currentToken()
        XCTAssertNil(token)
        let appleUserID = await vault.appleUserID()
        XCTAssertNil(appleUserID)
        XCTAssertEqual(state.phase, .signedOut)
    }
}

// MARK: - The configuration

final class AppConfigTests: XCTestCase {
    func testAReleaseBuildRefusesAPlainHTTPAPI() throws {
        let http = try XCTUnwrap(URL(string: "http://localhost:8787"))
        let https = try XCTUnwrap(URL(string: "https://api.example.com"))
        let other = try XCTUnwrap(URL(string: "ftp://api.example.com"))

        // A release build only talks over https: a plain http URL would send the
        // bearer token of the player in clear.
        XCTAssertFalse(AppConfig.isAllowedBaseURL(http, requiresHTTPS: true))
        XCTAssertFalse(AppConfig.isAllowedBaseURL(other, requiresHTTPS: true))
        XCTAssertTrue(AppConfig.isAllowedBaseURL(https, requiresHTTPS: true))

        // A debug build talks to the laptop of the developer.
        XCTAssertTrue(AppConfig.isAllowedBaseURL(http, requiresHTTPS: false))
        XCTAssertTrue(AppConfig.isAllowedBaseURL(https, requiresHTTPS: false))
        XCTAssertFalse(AppConfig.isAllowedBaseURL(other, requiresHTTPS: false))
    }

    func testTheDemoLaunchArgumentIsADebugTool() {
        #if DEBUG
        XCTAssertTrue(AppConfig.isDemoLaunchArgument || !ProcessInfo.processInfo.arguments.contains("-demo"))
        #else
        XCTAssertFalse(AppConfig.isDemoLaunchArgument)
        #endif
    }
}
