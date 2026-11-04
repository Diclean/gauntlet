import XCTest
@testable import Dares

/// Tests for the decoding of the v3 models (SPEC.md, section 6). Every new field is
/// optional or has a default, so the payload of an older server still decodes.
final class ModelsV3DecodingTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try APIJSON.decoder().decode(type, from: Data(json.utf8))
    }

    // MARK: - The user and the house rules

    func testTheUserCarriesTheHouseRules() throws {
        let user = try decode(User.self, """
        {
          "id": "u_1",
          "displayName": "Alex",
          "avatarEmoji": "🦊",
          "termsAccepted": true
        }
        """)
        XCTAssertTrue(user.termsAccepted)
    }

    func testAnOlderUserPayloadDecodesWithoutTheHouseRules() throws {
        let user = try decode(User.self, """
        { "id": "u_1", "displayName": "Alex" }
        """)
        XCTAssertFalse(user.termsAccepted)
        XCTAssertEqual(user.displayName, "Alex")
    }

    // MARK: - The fixture

    func testTheFixtureCarriesTheVetoTheCaptainAndTheHouse() throws {
        let challenge = try decode(Challenge.self, """
        {
          "id": "c_1",
          "title": "Score a Panenka",
          "description": "The big one of the week.",
          "difficulty": "hard",
          "points": 50,
          "position": 3,
          "myStatus": "todo",
          "acceptedCount": 0,
          "vetoCount": 2,
          "vetoThreshold": 3,
          "myVeto": true,
          "isNew": true,
          "isHouse": true,
          "createdBy": { "id": "u_2", "displayName": "Jo", "avatarEmoji": "🐢" },
          "isCaptain": true
        }
        """)

        XCTAssertEqual(challenge.vetoCount, 2)
        XCTAssertEqual(challenge.vetoThreshold, 3)
        XCTAssertTrue(challenge.myVeto)
        XCTAssertTrue(challenge.isNew)
        XCTAssertTrue(challenge.isHouse)
        XCTAssertEqual(challenge.createdBy?.displayName, "Jo")
        XCTAssertTrue(challenge.isCaptain)
    }

    func testAnOlderFixturePayloadDecodesWithoutTheV3Fields() throws {
        let challenge = try decode(Challenge.self, """
        {
          "id": "c_1",
          "title": "Sunrise on a hill",
          "difficulty": "easy",
          "points": 10,
          "position": 1,
          "myStatus": "todo",
          "acceptedCount": 0
        }
        """)

        XCTAssertEqual(challenge.vetoCount, 0)
        XCTAssertEqual(challenge.vetoThreshold, 0)
        XCTAssertFalse(challenge.myVeto)
        XCTAssertFalse(challenge.isNew)
        XCTAssertFalse(challenge.isHouse)
        XCTAssertNil(challenge.createdBy)
        XCTAssertFalse(challenge.isCaptain)
    }

    // MARK: - The proof

    func testTheProofCarriesTheReactionsAndTheCommentCount() throws {
        let submission = try decode(Submission.self, """
        {
          "id": "s_1",
          "challengeId": "c_1",
          "challengeTitle": "Score a Panenka",
          "user": { "id": "u_2", "displayName": "Jo" },
          "mediaUrl": "/media/key",
          "mediaType": "photo",
          "caption": "Three hours.",
          "status": "pending",
          "approvals": 1,
          "rejections": 0,
          "eligibleVoters": 4,
          "myVote": null,
          "createdAt": 1,
          "decidedAt": null,
          "reactions": [
            { "emoji": "🔥", "count": 3, "mine": true },
            { "emoji": "😂", "count": 1, "mine": false }
          ],
          "commentCount": 4
        }
        """)

        XCTAssertEqual(submission.reactions.count, 2)
        XCTAssertEqual(submission.reactions.first?.emoji, "🔥")
        XCTAssertEqual(submission.reactions.first?.count, 3)
        XCTAssertTrue(submission.reactions.first?.mine == true)
        XCTAssertEqual(submission.reactions.first?.reaction, .fire)
        XCTAssertEqual(submission.commentCount, 4)
    }

    func testAnOlderProofPayloadDecodesWithoutTheBanter() throws {
        let submission = try decode(Submission.self, """
        {
          "id": "s_1",
          "challengeId": "c_1",
          "challengeTitle": "Sunrise on a hill",
          "user": { "id": "u_2", "displayName": "Jo" },
          "mediaUrl": "/media/key",
          "mediaType": "photo",
          "caption": null,
          "status": "pending",
          "approvals": 0,
          "rejections": 0,
          "eligibleVoters": 4,
          "myVote": null,
          "createdAt": 1,
          "decidedAt": null
        }
        """)

        XCTAssertTrue(submission.reactions.isEmpty)
        XCTAssertEqual(submission.commentCount, 0)
    }

    // MARK: - The matchweek

    func testTheMatchweekCarriesTheCaptainAndTheUsedVetoes() throws {
        let week = try decode(Week.self, """
        {
          "id": "w_12",
          "number": 12,
          "startsAt": 1,
          "endsAt": 2,
          "voteDeadline": 3,
          "status": "open",
          "myCaptainChallengeId": "c_3",
          "vetoesUsed": 1
        }
        """)

        XCTAssertEqual(week.myCaptainChallengeId, "c_3")
        XCTAssertEqual(week.vetoesUsed, 1)
    }

    func testTheMatchweekOfTheWeekCarriesTheHouseFixture() throws {
        let response = try decode(WeekResponse.self, """
        {
          "week": {
            "id": "w_12",
            "number": 12,
            "startsAt": 1,
            "endsAt": 2,
            "voteDeadline": 3,
            "status": "open"
          },
          "challenges": [],
          "houseFixture": {
            "allowed": true,
            "deadline": 1768000000,
            "author": { "id": "u_2", "displayName": "Jo" }
          }
        }
        """)

        XCTAssertEqual(response.houseFixture?.allowed, true)
        XCTAssertEqual(response.houseFixture?.author?.displayName, "Jo")
    }

    func testAnOlderMatchweekPayloadDecodesWithoutTheHouseFixture() throws {
        let response = try decode(WeekResponse.self, """
        {
          "week": {
            "id": "w_12",
            "number": 12,
            "startsAt": 1,
            "endsAt": 2,
            "voteDeadline": 3,
            "status": "open"
          },
          "challenges": []
        }
        """)

        XCTAssertNil(response.houseFixture)
    }

    // MARK: - The club and the invite link

    func testTheClubCarriesTheInviteLink() throws {
        let group = try decode(Group.self, """
        {
          "id": "g_1",
          "name": "Sunday League FC",
          "inviteCode": "K7M2PQ",
          "challengesPerWeek": 5,
          "language": "en",
          "timezone": "Europe/Paris",
          "ownerId": "u_1",
          "memberCount": 5,
          "forfeit": "Buys the round 🍺",
          "inviteUrl": "https://dares.example.workers.dev/join/K7M2PQ"
        }
        """)

        XCTAssertEqual(group.inviteUrl, "https://dares.example.workers.dev/join/K7M2PQ")
    }

    func testAnOlderClubPayloadDecodesWithoutTheInviteLink() throws {
        let group = try decode(Group.self, """
        {
          "id": "g_1",
          "name": "Sunday League FC",
          "inviteCode": "K7M2PQ",
          "challengesPerWeek": 5,
          "language": "en",
          "timezone": "Europe/Paris",
          "ownerId": "u_1",
          "memberCount": 5
        }
        """)

        XCTAssertNil(group.inviteUrl)
        XCTAssertEqual(group.forfeit, Group.defaultForfeit)
    }

    // MARK: - The rest of the v3 shapes

    func testTheNotificationSwitchesAreAllOnByDefault() throws {
        let prefs = try decode(NotificationPrefs.self, "{}")
        XCTAssertTrue(prefs.newWeek)
        XCTAssertTrue(prefs.voteNeeded)
        XCTAssertTrue(prefs.result)
        XCTAssertTrue(prefs.deadline)
        XCTAssertTrue(prefs.awards)
        XCTAssertTrue(prefs.banter)

        let off = try decode(NotificationPrefs.self, """
        { "newWeek": false, "voteNeeded": true, "result": false, "deadline": true, "awards": false, "banter": true }
        """)
        XCTAssertFalse(off.newWeek)
        XCTAssertFalse(off.result)
        XCTAssertFalse(off.awards)
        XCTAssertTrue(off.banter)
    }

    func testACommentCarriesTheAuthorAndThePermission() throws {
        let comment = try decode(Comment.self, """
        {
          "id": "cm_1",
          "user": { "id": "u_2", "displayName": "Jo" },
          "text": "The light though.",
          "createdAt": 1,
          "canDelete": false
        }
        """)

        XCTAssertEqual(comment.text, "The light though.")
        XCTAssertFalse(comment.canDelete)
    }

    func testTheBannedMembersDecode() throws {
        // `GET /groups/:id/bans` → `{users:[User & {bannedAt}]}` (SPEC.md, section 6.9).
        let response = try decode(BannedMembersResponse.self, """
        {
          "users": [
            {
              "id": "u_9",
              "displayName": "Tom",
              "avatarEmoji": "🐯",
              "bannedAt": 1
            }
          ]
        }
        """)

        XCTAssertEqual(response.users.count, 1)
        XCTAssertEqual(response.users.first?.user.id, "u_9")
        XCTAssertEqual(response.users.first?.user.displayName, "Tom")
        XCTAssertEqual(response.users.first?.user.avatarEmoji, "🐯")
        XCTAssertEqual(response.users.first?.bannedAt, Date(timeIntervalSince1970: 1))
    }

    func testAnEmptyBanListDecodes() throws {
        let empty = try decode(BannedMembersResponse.self, "{}")
        XCTAssertTrue(empty.users.isEmpty)
    }

    func testTheBlockedMembersDecode() throws {
        let response = try decode(BlocksResponse.self, """
        { "users": [{ "id": "u_9", "displayName": "Nina" }] }
        """)
        XCTAssertEqual(response.users.first?.displayName, "Nina")

        let empty = try decode(BlocksResponse.self, "{}")
        XCTAssertTrue(empty.users.isEmpty)
    }

    func testTheVetoResponseCarriesTheNewFixture() throws {
        let response = try decode(VetoResponse.self, """
        {
          "challenge": {
            "id": "c_9",
            "title": "Walk 10k without music",
            "difficulty": "easy",
            "points": 10,
            "position": 5,
            "myStatus": "todo",
            "acceptedCount": 0,
            "isNew": true
          },
          "replaced": true
        }
        """)

        XCTAssertTrue(response.replaced)
        XCTAssertTrue(response.challenge.isNew)
        XCTAssertEqual(response.challenge.position, 5)
    }

    func testTheCaptainResponseDecodes() throws {
        let response = try decode(CaptainResponse.self, """
        {
          "week": {
            "id": "w_12",
            "number": 12,
            "startsAt": 1,
            "endsAt": 2,
            "voteDeadline": 3,
            "status": "open",
            "myCaptainChallengeId": "c_3"
          }
        }
        """)

        XCTAssertEqual(response.week?.myCaptainChallengeId, "c_3")
        XCTAssertNil(response.challenge)
    }

    func testTheJoinPreviewDecodes() throws {
        let response = try decode(JoinPreviewResponse.self, """
        {
          "group": {
            "id": "g_1",
            "name": "Sunday League FC",
            "inviteCode": "K7M2PQ",
            "challengesPerWeek": 5,
            "language": "en",
            "timezone": "Europe/Paris",
            "ownerId": "u_1",
            "memberCount": 5
          }
        }
        """)

        XCTAssertEqual(response.group.name, "Sunday League FC")
        XCTAssertEqual(response.group.memberCount, 5)
    }

    func testTheSixReactionsAreTheOnesOfTheSpec() {
        XCTAssertEqual(
            ReactionEmoji.displayOrder.map(\.rawValue),
            ["🔥", "😂", "🤡", "🐐", "😮", "👏"]
        )
        XCTAssertEqual(ReactionEmoji.allCases.count, 6)
    }

    func testTheSixReportReasonsAreTheOnesOfTheSpec() {
        XCTAssertEqual(
            ReportReason.allCases.map(\.rawValue),
            ["nudity", "violence", "harassment", "dangerous", "spam", "other"]
        )
    }
}
