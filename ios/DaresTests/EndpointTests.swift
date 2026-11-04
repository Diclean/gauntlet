import XCTest
@testable import Dares

/// Tests for the request plumbing: endpoints, multipart bodies and URL building.
final class EndpointTests: XCTestCase {
    func testEndpointPathsAndMethods() {
        XCTAssertEqual(Endpoint.health.method, .get)
        XCTAssertEqual(Endpoint.health.path, "/health")
        XCTAssertFalse(Endpoint.health.requiresAuth)

        XCTAssertEqual(Endpoint.appleAuth.path, "/auth/apple")
        XCTAssertFalse(Endpoint.appleAuth.requiresAuth)

        XCTAssertEqual(Endpoint.logout.method, .post)
        XCTAssertEqual(Endpoint.logout.path, "/auth/logout")
        XCTAssertTrue(Endpoint.logout.requiresAuth)

        XCTAssertEqual(Endpoint.me.path, "/me")
        XCTAssertEqual(Endpoint.updateMe.method, .patch)
        XCTAssertEqual(Endpoint.deleteMe.method, .delete)
        XCTAssertEqual(Endpoint.registerDevice.path, "/devices")

        XCTAssertEqual(Endpoint.groups.path, "/groups")
        XCTAssertEqual(Endpoint.createGroup.method, .post)
        XCTAssertEqual(Endpoint.joinGroup.path, "/groups/join")

        XCTAssertEqual(Endpoint.group("g_1").path, "/groups/g_1")
        XCTAssertEqual(Endpoint.updateGroup("g_1").method, .patch)
        XCTAssertEqual(Endpoint.leaveGroup("g_1").path, "/groups/g_1/leave")
        XCTAssertEqual(Endpoint.groupWeek("g_1").path, "/groups/g_1/week")

        XCTAssertEqual(Endpoint.groupFeed("g_1").path, "/groups/g_1/feed")
        XCTAssertTrue(Endpoint.groupFeed("g_1").query.isEmpty)
        XCTAssertEqual(Endpoint.groupFeed("g_1", cursor: "abc").query.first?.value, "abc")

        XCTAssertEqual(Endpoint.groupLeaderboard("g_1", scope: .week).path, "/groups/g_1/leaderboard")
        XCTAssertEqual(Endpoint.groupLeaderboard("g_1", scope: .all).query.first?.value, "all")

        XCTAssertEqual(Endpoint.groupPendingVotes("g_1").method, .get)
        XCTAssertEqual(Endpoint.groupPendingVotes("g_1").path, "/groups/g_1/votes/pending")
        XCTAssertTrue(Endpoint.groupPendingVotes("g_1").query.isEmpty)

        XCTAssertEqual(Endpoint.createSubmission(challengeID: "c_1").path, "/challenges/c_1/submissions")
        XCTAssertEqual(Endpoint.submission("s_1").path, "/submissions/s_1")
        XCTAssertEqual(Endpoint.vote("s_1").path, "/submissions/s_1/vote")
        XCTAssertEqual(Endpoint.media("key").path, "/media/key")
    }

    func testTheSundayLeagueEndpoints() {
        XCTAssertEqual(Endpoint.groupRace("g_1").method, .get)
        XCTAssertEqual(Endpoint.groupRace("g_1").path, "/groups/g_1/stats/race")
        XCTAssertTrue(Endpoint.groupRace("g_1").query.isEmpty)

        XCTAssertEqual(Endpoint.groupWeeks("g_1").path, "/groups/g_1/weeks")
        XCTAssertEqual(Endpoint.groupWeeks("g_1").query.first?.name, "limit")
        XCTAssertEqual(Endpoint.groupWeeks("g_1", limit: 5).query.first?.value, "5")

        XCTAssertEqual(Endpoint.groupReceipt("g_1", weekID: "w_12").method, .get)
        XCTAssertEqual(Endpoint.groupReceipt("g_1", weekID: "w_12").path, "/groups/g_1/weeks/w_12/receipt")

        XCTAssertEqual(Endpoint.groupAwards("g_1", month: "2026-11").path, "/groups/g_1/awards")
        XCTAssertEqual(Endpoint.groupAwards("g_1", month: "2026-11").query.first?.name, "month")
        XCTAssertEqual(Endpoint.groupAwards("g_1", month: "2026-11").query.first?.value, "2026-11")
        XCTAssertTrue(Endpoint.groupAwards("g_1", month: nil).query.isEmpty)

        XCTAssertEqual(Endpoint.groupAwardMonths("g_1").path, "/groups/g_1/awards/months")

        XCTAssertEqual(Endpoint.myTrophies.method, .get)
        XCTAssertEqual(Endpoint.myTrophies.path, "/me/trophies")
        XCTAssertTrue(Endpoint.myTrophies.requiresAuth)
    }

    func testMediaURLIsBuiltFromTheBaseURL() throws {
        let client = APIClient(baseURL: URL(string: "https://dares.example.workers.dev")!, vault: TokenVault(keychain: KeychainStore(service: "com.mathys.dares.tests")))
        XCTAssertEqual(
            try client.mediaURL(for: "/media/abc").absoluteString,
            "https://dares.example.workers.dev/media/abc"
        )
    }

    /// The media of a club never leaves the host of the API (SPEC.md, section 2).
    func testTheMediaURLRefusesAForeignHost() throws {
        let client = APIClient(baseURL: URL(string: "https://dares.example.workers.dev")!, vault: TokenVault(keychain: KeychainStore(service: "com.mathys.dares.tests")))

        XCTAssertThrowsError(try client.mediaURL(for: "https://evil.example.net/media/abc"))
        XCTAssertThrowsError(try client.mediaURL(for: "http://dares.example.workers.dev/media/abc"))
        XCTAssertThrowsError(try client.mediaURL(for: "/media/../../etc/passwd"))

        XCTAssertEqual(
            try client.mediaURL(for: "https://dares.example.workers.dev/media/abc").absoluteString,
            "https://dares.example.workers.dev/media/abc"
        )
    }

    func testMultipartBodyContainsFieldsAndFile() throws {
        let file = FilePart(fieldName: "media", fileName: "proof.jpg", mimeType: "image/jpeg", data: Data([0x01, 0x02, 0x03]))
        let body = MultipartBody(boundary: "BOUNDARY", fields: ["mediaType": "photo", "caption": "hi"], file: file)

        let text = String(decoding: body.body, as: UTF8.self)
        XCTAssertTrue(text.contains("--BOUNDARY\r\n"))
        XCTAssertTrue(text.contains("Content-Disposition: form-data; name=\"mediaType\""))
        XCTAssertTrue(text.contains("Content-Disposition: form-data; name=\"caption\""))
        XCTAssertTrue(text.contains("Content-Disposition: form-data; name=\"media\"; filename=\"proof.jpg\""))
        XCTAssertTrue(text.contains("Content-Type: image/jpeg"))
        XCTAssertTrue(text.hasSuffix("--BOUNDARY--\r\n"))
        XCTAssertEqual(body.contentType, "multipart/form-data; boundary=BOUNDARY")
    }

    func testMultipartBodyKeepsBinaryFileData() throws {
        let payload = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let file = FilePart(fieldName: "media", fileName: "proof.jpg", mimeType: "image/jpeg", data: payload)
        let body = MultipartBody(boundary: "B", fields: [:], file: file)
        XCTAssertTrue(body.body.range(of: payload) != nil)
    }

    /// A caption or a file name with a line break would break out of its header and
    /// inject another part into the body (multipart injection).
    func testTheMultipartBodyStripsTheLineBreaks() {
        let file = FilePart(
            fieldName: "media",
            fileName: "proof\r\nX-Injected: yes.jpg",
            mimeType: "image/jpeg",
            data: Data([0x01])
        )
        let body = MultipartBody(boundary: "B", fields: ["caption": "hello\r\nworld"], file: file)
        let text = String(decoding: body.body, as: UTF8.self)

        XCTAssertFalse(text.contains("hello\r\nworld"))
        XCTAssertFalse(text.contains("proof\r\n"))
        XCTAssertTrue(text.contains("hello world"))
        XCTAssertTrue(text.contains("filename=\"proof X-Injected: yes.jpg\""))
    }
}

final class AppleNonceTests: XCTestCase {
    func testNonceIsRandomAndHashedWithSHA256() {
        let nonce = AppleNonce.random()
        XCTAssertEqual(nonce.count, 32)
        XCTAssertNotEqual(nonce, AppleNonce.random())

        // SHA-256 of an empty string, the well known reference value.
        XCTAssertEqual(
            AppleNonce.sha256(""),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
    }
}
