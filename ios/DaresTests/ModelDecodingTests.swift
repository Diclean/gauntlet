import XCTest
@testable import Dares

/// Decoding tests for every model of the REST contract (SPEC.md, section 3).
final class ModelDecodingTests: XCTestCase {
    // MARK: - Fixtures

    private let userJSON = """
    {
      "id": "u_1",
      "displayName": "Alex",
      "avatarEmoji": "🦊"
    }
    """

    private let groupJSON = """
    {
      "id": "g_1",
      "name": "Weekend Warriors",
      "inviteCode": "K7M2PQ",
      "challengesPerWeek": 5,
      "theme": "Outdoors only",
      "language": "en",
      "timezone": "Europe/Paris",
      "ownerId": "u_1",
      "memberCount": 6
    }
    """

    private let weekJSON = """
    {
      "id": "w_1",
      "startsAt": 1735689600,
      "endsAt": 1736294399,
      "voteDeadline": 1736336799,
      "status": "open"
    }
    """

    private let challengeJSON = """
    {
      "id": "c_1",
      "title": "Sunrise on a hill",
      "description": "Catch the sun coming up from a hill.",
      "difficulty": "medium",
      "points": 25,
      "position": 1,
      "myStatus": "pending",
      "acceptedCount": 1
    }
    """

    private let submissionJSON = """
    {
      "id": "s_1",
      "challengeId": "c_1",
      "challengeTitle": "Sunrise on a hill",
      "user": {
        "id": "u_2",
        "displayName": "Sam",
        "avatarEmoji": "🐻"
      },
      "mediaUrl": "/media/6f1a2b3c",
      "mediaType": "photo",
      "caption": "Worth the 5am alarm.",
      "status": "pending",
      "approvals": 1,
      "rejections": 0,
      "eligibleVoters": 3,
      "myVote": null,
      "createdAt": 1735689600,
      "decidedAt": null
    }
    """

    // MARK: - Core models

    func testUserDecodes() throws {
        let user = try APIJSON.decoder().decode(User.self, from: Data(userJSON.utf8))
        XCTAssertEqual(user.id, "u_1")
        XCTAssertEqual(user.displayName, "Alex")
        XCTAssertEqual(user.avatarEmoji, "🦊")
    }

    func testUserDecodesWithoutAvatarEmoji() throws {
        let json = """
        { "id": "u_3", "displayName": "Jo", "avatarEmoji": null }
        """
        let user = try APIJSON.decoder().decode(User.self, from: Data(json.utf8))
        XCTAssertNil(user.avatarEmoji)
        XCTAssertEqual(user.displayName, "Jo")
    }

    func testGroupDecodes() throws {
        let group = try APIJSON.decoder().decode(Group.self, from: Data(groupJSON.utf8))
        XCTAssertEqual(group.id, "g_1")
        XCTAssertEqual(group.name, "Weekend Warriors")
        XCTAssertEqual(group.inviteCode, "K7M2PQ")
        XCTAssertEqual(group.challengesPerWeek, 5)
        XCTAssertEqual(group.theme, "Outdoors only")
        XCTAssertEqual(group.language, "en")
        XCTAssertEqual(group.timezone, "Europe/Paris")
        XCTAssertEqual(group.ownerId, "u_1")
        XCTAssertEqual(group.memberCount, 6)
    }

    func testGroupDecodesWithoutTheme() throws {
        let json = """
        {
          "id": "g_2",
          "name": "Flatmates",
          "inviteCode": "AB12CD",
          "challengesPerWeek": 3,
          "theme": null,
          "language": "en",
          "timezone": "UTC",
          "ownerId": "u_2",
          "memberCount": 2
        }
        """
        let group = try APIJSON.decoder().decode(Group.self, from: Data(json.utf8))
        XCTAssertNil(group.theme)
        XCTAssertEqual(group.challengesPerWeek, 3)
    }

    func testMemberDecodes() throws {
        let json = """
        {
          "user": { "id": "u_2", "displayName": "Sam", "avatarEmoji": null },
          "joinedAt": 1735689600
        }
        """
        let member = try APIJSON.decoder().decode(Member.self, from: Data(json.utf8))
        XCTAssertEqual(member.user.id, "u_2")
        XCTAssertEqual(member.joinedAt, Date(timeIntervalSince1970: 1_735_689_600))
        XCTAssertEqual(member.id, "u_2")
    }

    func testWeekDecodes() throws {
        let week = try APIJSON.decoder().decode(Week.self, from: Data(weekJSON.utf8))
        XCTAssertEqual(week.id, "w_1")
        XCTAssertEqual(week.startsAt, Date(timeIntervalSince1970: 1_735_689_600))
        XCTAssertEqual(week.endsAt, Date(timeIntervalSince1970: 1_736_294_399))
        XCTAssertEqual(week.voteDeadline, Date(timeIntervalSince1970: 1_736_336_799))
        XCTAssertEqual(week.status, .open)
    }

    func testChallengeDecodes() throws {
        let challenge = try APIJSON.decoder().decode(Challenge.self, from: Data(challengeJSON.utf8))
        XCTAssertEqual(challenge.id, "c_1")
        XCTAssertEqual(challenge.title, "Sunrise on a hill")
        XCTAssertEqual(challenge.description, "Catch the sun coming up from a hill.")
        XCTAssertEqual(challenge.difficulty, .medium)
        XCTAssertEqual(challenge.points, 25)
        XCTAssertEqual(challenge.position, 1)
        XCTAssertEqual(challenge.myStatus, .pending)
        XCTAssertEqual(challenge.acceptedCount, 1)
    }

    func testChallengeWithMyStatusTypealiasDecodes() throws {
        let challenge = try APIJSON.decoder().decode(ChallengeWithMyStatus.self, from: Data(challengeJSON.utf8))
        XCTAssertEqual(challenge.myStatus, .pending)
    }

    func testSubmissionDecodes() throws {
        let submission = try APIJSON.decoder().decode(Submission.self, from: Data(submissionJSON.utf8))
        XCTAssertEqual(submission.id, "s_1")
        XCTAssertEqual(submission.challengeId, "c_1")
        XCTAssertEqual(submission.challengeTitle, "Sunrise on a hill")
        XCTAssertEqual(submission.user.displayName, "Sam")
        XCTAssertEqual(submission.mediaUrl, "/media/6f1a2b3c")
        XCTAssertEqual(submission.mediaType, .photo)
        XCTAssertEqual(submission.caption, "Worth the 5am alarm.")
        XCTAssertEqual(submission.status, .pending)
        XCTAssertEqual(submission.approvals, 1)
        XCTAssertEqual(submission.rejections, 0)
        XCTAssertEqual(submission.eligibleVoters, 3)
        XCTAssertNil(submission.myVote)
        XCTAssertEqual(submission.createdAt, Date(timeIntervalSince1970: 1_735_689_600))
        XCTAssertNil(submission.decidedAt)
    }

    func testSubmissionDecodesWithVoteAndDecision() throws {
        let json = """
        {
          "id": "s_2",
          "challengeId": "c_1",
          "challengeTitle": "Sunrise on a hill",
          "user": { "id": "u_1", "displayName": "Alex", "avatarEmoji": null },
          "mediaUrl": "/media/abc",
          "mediaType": "video",
          "caption": null,
          "status": "accepted",
          "approvals": 2,
          "rejections": 0,
          "eligibleVoters": 3,
          "myVote": true,
          "createdAt": 1735689600,
          "decidedAt": 1735700000
        }
        """
        let submission = try APIJSON.decoder().decode(Submission.self, from: Data(json.utf8))
        XCTAssertEqual(submission.mediaType, .video)
        XCTAssertNil(submission.caption)
        XCTAssertEqual(submission.myVote, true)
        XCTAssertEqual(submission.decidedAt, Date(timeIntervalSince1970: 1_735_700_000))
    }

    func testLeaderboardEntryDecodes() throws {
        let json = """
        {
          "user": { "id": "u_2", "displayName": "Sam", "avatarEmoji": "🐻" },
          "points": 120,
          "rank": 1,
          "streak": 4
        }
        """
        let entry = try APIJSON.decoder().decode(LeaderboardEntry.self, from: Data(json.utf8))
        XCTAssertEqual(entry.user.id, "u_2")
        XCTAssertEqual(entry.points, 120)
        XCTAssertEqual(entry.rank, 1)
        XCTAssertEqual(entry.streak, 4)
        XCTAssertEqual(entry.id, "u_2")
    }

    // MARK: - Enumerations

    func testEnumRawValues() {
        XCTAssertEqual(Difficulty.easy.rawValue, "easy")
        XCTAssertEqual(Difficulty.medium.rawValue, "medium")
        XCTAssertEqual(Difficulty.hard.rawValue, "hard")
        XCTAssertEqual(MyChallengeStatus.todo.rawValue, "todo")
        XCTAssertEqual(MyChallengeStatus.pending.rawValue, "pending")
        XCTAssertEqual(MyChallengeStatus.accepted.rawValue, "accepted")
        XCTAssertEqual(MyChallengeStatus.rejected.rawValue, "rejected")
        XCTAssertEqual(SubmissionStatus.pending.rawValue, "pending")
        XCTAssertEqual(SubmissionStatus.accepted.rawValue, "accepted")
        XCTAssertEqual(SubmissionStatus.rejected.rawValue, "rejected")
        XCTAssertEqual(SubmissionStatus.expired.rawValue, "expired")
        XCTAssertEqual(MediaType.photo.rawValue, "photo")
        XCTAssertEqual(MediaType.video.rawValue, "video")
        XCTAssertEqual(WeekStatus.open.rawValue, "open")
        XCTAssertEqual(WeekStatus.closed.rawValue, "closed")
        XCTAssertEqual(LeaderboardScope.week.rawValue, "week")
        XCTAssertEqual(LeaderboardScope.all.rawValue, "all")
    }

    // MARK: - Response envelopes

    func testAuthResponseDecodes() throws {
        let json = """
        {
          "token": "a-session-token",
          "user": { "id": "u_1", "displayName": "Alex", "avatarEmoji": null }
        }
        """
        let response = try APIJSON.decoder().decode(AuthResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.token, "a-session-token")
        XCTAssertEqual(response.user.id, "u_1")
    }

    func testMeResponseDecodes() throws {
        let json = """
        { "user": { "id": "u_1", "displayName": "Alex", "avatarEmoji": "🦊" } }
        """
        let response = try APIJSON.decoder().decode(MeResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.user.avatarEmoji, "🦊")
    }

    func testOKResponseDecodes() throws {
        let response = try APIJSON.decoder().decode(OKResponse.self, from: Data("{ \"ok\": true }".utf8))
        XCTAssertTrue(response.ok)
        let health = try APIJSON.decoder().decode(HealthResponse.self, from: Data("{ \"ok\": true }".utf8))
        XCTAssertTrue(health.ok)
    }

    func testGroupsResponseDecodes() throws {
        let json = """
        { "groups": [ \(groupJSON) ] }
        """
        let response = try APIJSON.decoder().decode(GroupsResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.groups.count, 1)
        XCTAssertEqual(response.groups.first?.inviteCode, "K7M2PQ")
    }

    func testGroupResponseDecodes() throws {
        let json = """
        { "group": \(groupJSON) }
        """
        let response = try APIJSON.decoder().decode(GroupResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.group.id, "g_1")
    }

    func testGroupDetailResponseDecodes() throws {
        let json = """
        {
          "group": \(groupJSON),
          "members": [
            { "user": { "id": "u_1", "displayName": "Alex", "avatarEmoji": null }, "joinedAt": 1735689600 },
            { "user": { "id": "u_2", "displayName": "Sam", "avatarEmoji": null }, "joinedAt": 1735689601 }
          ]
        }
        """
        let response = try APIJSON.decoder().decode(GroupDetailResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.members.count, 2)
        XCTAssertEqual(response.members.last?.user.displayName, "Sam")
    }

    func testWeekResponseDecodes() throws {
        let json = """
        {
          "week": \(weekJSON),
          "challenges": [ \(challengeJSON) ]
        }
        """
        let response = try APIJSON.decoder().decode(WeekResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.week.id, "w_1")
        XCTAssertEqual(response.challenges.first?.myStatus, .pending)
    }

    func testFeedResponseDecodes() throws {
        let json = """
        {
          "items": [ \(submissionJSON) ],
          "nextCursor": "cursor-2"
        }
        """
        let response = try APIJSON.decoder().decode(FeedResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.items.count, 1)
        XCTAssertEqual(response.nextCursor, "cursor-2")
    }

    func testFeedResponseDecodesWithoutCursor() throws {
        let json = """
        { "items": [], "nextCursor": null }
        """
        let response = try APIJSON.decoder().decode(FeedResponse.self, from: Data(json.utf8))
        XCTAssertTrue(response.items.isEmpty)
        XCTAssertNil(response.nextCursor)
    }

    func testPendingVotesResponseDecodes() throws {
        let json = """
        { "items": [ \(submissionJSON) ] }
        """
        let response = try APIJSON.decoder().decode(PendingVotesResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.items.count, 1)
        XCTAssertEqual(response.items.first?.id, "s_1")
    }

    func testLeaderboardResponseDecodes() throws {
        let json = """
        {
          "entries": [
            { "user": { "id": "u_2", "displayName": "Sam", "avatarEmoji": null }, "points": 120, "rank": 1, "streak": 4 }
          ]
        }
        """
        let response = try APIJSON.decoder().decode(LeaderboardResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.entries.count, 1)
        XCTAssertEqual(response.entries.first?.rank, 1)
    }

    func testSubmissionResponseDecodes() throws {
        let json = """
        { "submission": \(submissionJSON) }
        """
        let response = try APIJSON.decoder().decode(SubmissionResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.submission.id, "s_1")
    }

    func testAPIErrorEnvelopeDecodes() throws {
        let json = """
        { "error": { "code": "not_a_member", "message": "You are not a member of this group." } }
        """
        let envelope = try APIJSON.decoder().decode(APIErrorEnvelope.self, from: Data(json.utf8))
        XCTAssertEqual(envelope.error.code, "not_a_member")
        XCTAssertEqual(envelope.error.message, "You are not a member of this group.")
    }

    // MARK: - Request bodies

    func testAppleAuthRequestEncodes() throws {
        let request = AppleAuthRequest(identityToken: "token", nonce: "nonce", displayName: "Alex")
        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["identityToken"] as? String, "token")
        XCTAssertEqual(json["nonce"] as? String, "nonce")
        XCTAssertEqual(json["displayName"] as? String, "Alex")
    }

    func testUpdateMeRequestEncodes() throws {
        let data = try JSONEncoder().encode(UpdateMeRequest(displayName: "Alex", avatarEmoji: "🦊"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["displayName"] as? String, "Alex")
        XCTAssertEqual(json["avatarEmoji"] as? String, "🦊")
    }

    func testCreateGroupRequestEncodes() throws {
        let request = CreateGroupRequest(
            name: "Flatmates",
            challengesPerWeek: 5,
            theme: "Indoors",
            language: "en",
            timezone: "Europe/Paris"
        )
        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["name"] as? String, "Flatmates")
        XCTAssertEqual(json["challengesPerWeek"] as? Int, 5)
        XCTAssertEqual(json["theme"] as? String, "Indoors")
        XCTAssertEqual(json["language"] as? String, "en")
        XCTAssertEqual(json["timezone"] as? String, "Europe/Paris")
    }

    func testUpdateGroupRequestEncodesPartialUpdate() throws {
        let data = try JSONEncoder().encode(UpdateGroupRequest(name: "New name"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["name"] as? String, "New name")
        XCTAssertNil(json["theme"])
    }

    func testJoinGroupRequestEncodes() throws {
        let data = try JSONEncoder().encode(JoinGroupRequest(inviteCode: "K7M2PQ"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["inviteCode"] as? String, "K7M2PQ")
    }

    func testVoteRequestEncodes() throws {
        let data = try JSONEncoder().encode(VoteRequest(approve: true))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["approve"] as? Bool, true)
    }

    func testDeviceRequestEncodes() throws {
        let data = try JSONEncoder().encode(DeviceRequest(apnsToken: "abcd"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["apnsToken"] as? String, "abcd")
    }

    // MARK: - Behaviour derived from the contract

    func testVotingThresholds() throws {
        let submission = try APIJSON.decoder().decode(Submission.self, from: Data(submissionJSON.utf8))
        XCTAssertEqual(submission.eligibleVoters, 3)
        XCTAssertEqual(submission.approvalsNeeded, 2)
        XCTAssertEqual(submission.rejectionsNeeded, 2)
        XCTAssertFalse(submission.isSoloGroup)
    }

    func testSoloGroupThresholds() throws {
        let json = submissionJSON
            .replacingOccurrences(of: "\"eligibleVoters\": 3", with: "\"eligibleVoters\": 0")
        let submission = try APIJSON.decoder().decode(Submission.self, from: Data(json.utf8))
        XCTAssertTrue(submission.isSoloGroup)
        XCTAssertEqual(submission.approvalsNeeded, 0)
    }

    func testTimestampsAreUnixSeconds() throws {
        let week = try APIJSON.decoder().decode(Week.self, from: Data(weekJSON.utf8))
        XCTAssertEqual(week.startsAt.timeIntervalSince1970, 1_735_689_600, accuracy: 0.001)
    }
}
