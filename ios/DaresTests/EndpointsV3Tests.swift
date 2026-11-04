import XCTest
@testable import Dares

/// Tests for the endpoints of v3 (SPEC.md, section 6).
final class EndpointsV3Tests: XCTestCase {
    func testTheHouseRulesEndpoint() {
        XCTAssertEqual(Endpoint.acceptTerms.method, .post)
        XCTAssertEqual(Endpoint.acceptTerms.path, "/me/accept-terms")
        XCTAssertTrue(Endpoint.acceptTerms.requiresAuth)
    }

    func testTheNotificationSwitchesEndpoints() {
        XCTAssertEqual(Endpoint.notificationPrefs.method, .get)
        XCTAssertEqual(Endpoint.notificationPrefs.path, "/me/notification-prefs")
        XCTAssertEqual(Endpoint.updateNotificationPrefs.method, .patch)
        XCTAssertEqual(Endpoint.updateNotificationPrefs.path, "/me/notification-prefs")
        XCTAssertTrue(Endpoint.updateNotificationPrefs.query.isEmpty)
    }

    func testTheBlockEndpoints() {
        XCTAssertEqual(Endpoint.myBlocks.method, .get)
        XCTAssertEqual(Endpoint.myBlocks.path, "/me/blocks")
        XCTAssertEqual(Endpoint.blockUser("u_9").method, .post)
        XCTAssertEqual(Endpoint.blockUser("u_9").path, "/users/u_9/block")
        XCTAssertEqual(Endpoint.unblockUser("u_9").method, .delete)
        XCTAssertEqual(Endpoint.unblockUser("u_9").path, "/users/u_9/block")
    }

    func testTheReportAndDeleteEndpoints() {
        XCTAssertEqual(Endpoint.deleteSubmission("s_1").method, .delete)
        XCTAssertEqual(Endpoint.deleteSubmission("s_1").path, "/submissions/s_1")
        XCTAssertEqual(Endpoint.reportSubmission("s_1").method, .post)
        XCTAssertEqual(Endpoint.reportSubmission("s_1").path, "/submissions/s_1/report")
        XCTAssertEqual(Endpoint.reportComment("c_1").method, .post)
        XCTAssertEqual(Endpoint.reportComment("c_1").path, "/comments/c_1/report")
        XCTAssertEqual(Endpoint.deleteComment("c_1").method, .delete)
        XCTAssertEqual(Endpoint.deleteComment("c_1").path, "/comments/c_1")
    }

    func testTheBanterEndpoints() {
        XCTAssertEqual(Endpoint.comments("s_1").method, .get)
        XCTAssertEqual(Endpoint.comments("s_1").path, "/submissions/s_1/comments")
        XCTAssertEqual(Endpoint.addComment("s_1").method, .post)
        XCTAssertEqual(Endpoint.addComment("s_1").path, "/submissions/s_1/comments")
        XCTAssertEqual(Endpoint.reactions("s_1").method, .post)
        XCTAssertEqual(Endpoint.reactions("s_1").path, "/submissions/s_1/reactions")
    }

    func testTheVetoCaptainAndHouseFixtureEndpoints() {
        XCTAssertEqual(Endpoint.vetoChallenge("c_1").method, .post)
        XCTAssertEqual(Endpoint.vetoChallenge("c_1").path, "/challenges/c_1/veto")
        XCTAssertEqual(Endpoint.setCaptain(groupID: "g_1").method, .put)
        XCTAssertEqual(Endpoint.setCaptain(groupID: "g_1").path, "/groups/g_1/week/captain")
        XCTAssertEqual(Endpoint.addHouseFixture(groupID: "g_1").method, .post)
        XCTAssertEqual(Endpoint.addHouseFixture(groupID: "g_1").path, "/groups/g_1/week/house-fixture")
    }

    func testTheMemberEndpoints() {
        XCTAssertEqual(Endpoint.removeMember(groupID: "g_1", userID: "u_9").method, .post)
        XCTAssertEqual(Endpoint.removeMember(groupID: "g_1", userID: "u_9").path, "/groups/g_1/members/u_9/remove")
        XCTAssertEqual(Endpoint.unbanMember(groupID: "g_1", userID: "u_9").method, .delete)
        XCTAssertEqual(Endpoint.unbanMember(groupID: "g_1", userID: "u_9").path, "/groups/g_1/members/u_9/ban")
        XCTAssertEqual(Endpoint.bans(groupID: "g_1").method, .get)
        XCTAssertEqual(Endpoint.bans(groupID: "g_1").path, "/groups/g_1/bans")
    }

    func testTheInviteLinkEndpoint() {
        // The app asks the API for the JSON of the club (SPEC.md, section 6.9).
        // `GET /join/:code` stays the HTML page of the browser.
        XCTAssertEqual(Endpoint.joinPreview(code: "K7M2PQ").method, .get)
        XCTAssertEqual(Endpoint.joinPreview(code: "K7M2PQ").path, "/groups/preview/K7M2PQ")
        XCTAssertTrue(Endpoint.joinPreview(code: "K7M2PQ").requiresAuth)
    }

    /// The ids of the API are untrusted input: they stay inside their own path segment.
    func testThePathComponentsAreEncoded() {
        XCTAssertEqual(Endpoint.joinPreview(code: "../admin").path, "/groups/preview/..%2Fadmin")
        XCTAssertEqual(Endpoint.group("../admin").path, "/groups/..%2Fadmin")
        XCTAssertEqual(Endpoint.submission("a b").path, "/submissions/a%20b")
        XCTAssertEqual(PathComponent.encode("a/b"), "a%2Fb")
    }

    // MARK: - The invite links of the app

    func testTheCustomSchemeOfTheInviteLink() throws {
        let url = try XCTUnwrap(URL(string: "gauntlet://join/K7M2PQ"))
        XCTAssertEqual(InviteLink.code(from: url), "K7M2PQ")
    }

    func testTheUniversalLinkOfTheInviteLink() throws {
        let url = try XCTUnwrap(URL(string: "https://dares.example.workers.dev/join/K7M2PQ"))
        XCTAssertEqual(InviteLink.code(from: url), "K7M2PQ")
    }

    func testALinkThatIsNoInviteHasNoCode() throws {
        let url = try XCTUnwrap(URL(string: "https://dares.example.workers.dev/groups/g_1"))
        XCTAssertNil(InviteLink.code(from: url))
    }
}
