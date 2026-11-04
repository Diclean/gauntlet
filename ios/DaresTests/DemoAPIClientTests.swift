import XCTest
@testable import Dares

/// Tests for the offline demo client: voting thresholds, the point ledger and the
/// pending votes endpoint (SPEC.md, sections 1 and 3).
final class DemoAPIClientTests: XCTestCase {
    // MARK: - Helpers

    private func makeClient() -> DemoAPIClient {
        DemoAPIClient(autoSimulate: false)
    }

    private var sampleUpload: ProofUpload {
        ProofUpload(
            mediaType: .photo,
            caption: "Test proof",
            data: Data([0xFF, 0xD8, 0xFF, 0xE0]),
            fileName: "proof.jpg",
            mimeType: "image/jpeg"
        )
    }

    /// Creates a group with `memberCount` members (the demo user is always the first one).
    private func makeGroup(
        _ client: DemoAPIClient,
        memberCount: Int
    ) async throws -> (group: Group, members: [String]) {
        let group = try await client.createGroup(
            CreateGroupRequest(name: "Test group \(memberCount)")
        ).group
        var members = [DemoSeed.currentUserID]
        for index in 1 ..< memberCount {
            let user = User(id: "test-member-\(index)", displayName: "Member \(index)", avatarEmoji: "🙂")
            await client.addMember(groupID: group.id, user: user)
            members.append(user.id)
        }
        return (group, members)
    }

    /// Sends a proof as `submitterID` for the first challenge of the current week.
    private func submit(
        _ client: DemoAPIClient,
        groupID: String,
        as submitterID: String
    ) async throws -> Submission {
        await client.actAs(submitterID)
        let week = try await client.currentWeek(groupID: groupID)
        let challenge = try XCTUnwrap(week.challenges.first)
        let response = try await client.createSubmission(
            challengeID: challenge.id,
            media: sampleUpload,
            onProgress: { _ in }
        )
        return response.submission
    }

    // MARK: - Voting thresholds

    func testOneEligibleVoterAcceptsASingleApproval() async throws {
        let client = makeClient()
        let (group, members) = try await makeGroup(client, memberCount: 2)
        let submission = try await submit(client, groupID: group.id, as: members[1])

        XCTAssertEqual(submission.eligibleVoters, 1)
        XCTAssertEqual(submission.approvalsNeeded, 1)
        XCTAssertEqual(submission.rejectionsNeeded, 1)

        await client.actAs(members[0])
        let approved = try await client.vote(submissionID: submission.id, approve: true)
        XCTAssertEqual(approved.submission.status, .accepted)
        XCTAssertEqual(approved.submission.approvals, 1)
    }

    func testOneEligibleVoterRejectsASingleRejection() async throws {
        let client = makeClient()
        let (group, members) = try await makeGroup(client, memberCount: 2)
        let submission = try await submit(client, groupID: group.id, as: members[1])

        await client.actAs(members[0])
        let rejected = try await client.vote(submissionID: submission.id, approve: false)
        XCTAssertEqual(rejected.submission.status, .rejected)
        XCTAssertEqual(rejected.submission.rejections, 1)
    }

    func testTwoEligibleVotersNeedTwoApprovalsButOnlyOneRejection() async throws {
        let client = makeClient()
        let (group, members) = try await makeGroup(client, memberCount: 3)
        let submission = try await submit(client, groupID: group.id, as: members[2])

        XCTAssertEqual(submission.eligibleVoters, 2)
        XCTAssertEqual(submission.approvalsNeeded, 2)
        XCTAssertEqual(submission.rejectionsNeeded, 1)

        await client.actAs(members[0])
        let first = try await client.vote(submissionID: submission.id, approve: true)
        XCTAssertEqual(first.submission.status, .pending, "One approval is not enough with two voters.")
        XCTAssertEqual(first.submission.approvals, 1)

        await client.castVoteAs(voterID: members[1], approve: true, submissionID: submission.id)
        let decided = try await client.submission(id: submission.id)
        XCTAssertEqual(decided.submission.status, .accepted)
        XCTAssertEqual(decided.submission.approvals, 2)
    }

    func testTwoEligibleVotersRejectWithASingleRejection() async throws {
        let client = makeClient()
        let (group, members) = try await makeGroup(client, memberCount: 3)
        let submission = try await submit(client, groupID: group.id, as: members[2])

        await client.actAs(members[0])
        let rejected = try await client.vote(submissionID: submission.id, approve: false)
        XCTAssertEqual(rejected.submission.status, .rejected)
    }

    func testFourEligibleVotersNeedTwoApprovalsAndTwoRejections() async throws {
        let client = makeClient()
        let (group, members) = try await makeGroup(client, memberCount: 5)
        let submission = try await submit(client, groupID: group.id, as: members[4])

        XCTAssertEqual(submission.eligibleVoters, 4)
        XCTAssertEqual(submission.approvalsNeeded, 2)
        XCTAssertEqual(submission.rejectionsNeeded, 2)

        await client.actAs(members[0])
        let approved = try await client.vote(submissionID: submission.id, approve: true)
        XCTAssertEqual(approved.submission.status, .pending)

        await client.castVoteAs(voterID: members[1], approve: false, submissionID: submission.id)
        let mixed = try await client.submission(id: submission.id)
        XCTAssertEqual(mixed.submission.status, .pending, "One approval and one rejection decide nothing.")

        await client.castVoteAs(voterID: members[2], approve: true, submissionID: submission.id)
        let accepted = try await client.submission(id: submission.id)
        XCTAssertEqual(accepted.submission.status, .accepted)
        XCTAssertEqual(accepted.submission.approvals, 2)
        XCTAssertEqual(accepted.submission.rejections, 1)
    }

    func testFourEligibleVotersRejectWithTwoRejections() async throws {
        let client = makeClient()
        let (group, members) = try await makeGroup(client, memberCount: 5)
        let submission = try await submit(client, groupID: group.id, as: members[4])

        await client.actAs(members[0])
        _ = try await client.vote(submissionID: submission.id, approve: false)
        await client.castVoteAs(voterID: members[1], approve: false, submissionID: submission.id)
        let rejected = try await client.submission(id: submission.id)
        XCTAssertEqual(rejected.submission.status, .rejected)
        XCTAssertEqual(rejected.submission.rejections, 2)
    }

    func testTheFirstThresholdReachedWins() async throws {
        let client = makeClient()
        let (group, members) = try await makeGroup(client, memberCount: 5)
        let submission = try await submit(client, groupID: group.id, as: members[4])

        // Two rejections come first: the proof is rejected even though an approval follows.
        await client.castVoteAs(voterID: members[0], approve: false, submissionID: submission.id)
        await client.castVoteAs(voterID: members[1], approve: false, submissionID: submission.id)
        await client.castVoteAs(voterID: members[2], approve: true, submissionID: submission.id)
        let rejected = try await client.submission(id: submission.id)
        XCTAssertEqual(rejected.submission.status, .rejected)
    }

    func testAVoteOnMyOwnProofIsRefused() async throws {
        let client = makeClient()
        let (group, members) = try await makeGroup(client, memberCount: 3)
        let submission = try await submit(client, groupID: group.id, as: members[0])

        await client.actAs(members[0])
        do {
            _ = try await client.vote(submissionID: submission.id, approve: true)
            XCTFail("Voting on your own proof must fail.")
        } catch {
            XCTAssertNotNil(error as? APIError)
        }
    }

    // MARK: - Point ledger

    func testAcceptedProofAddsChallengePointsAndTheFirstFinisherBonus() async throws {
        let client = makeClient()
        let (group, members) = try await makeGroup(client, memberCount: 5)
        let week = try await client.currentWeek(groupID: group.id)
        let challenge = try XCTUnwrap(week.challenges.first)
        let submitter = members[1]

        let submission = try await submit(client, groupID: group.id, as: submitter)
        XCTAssertEqual(submission.challengeId, challenge.id)

        await client.actAs(members[0])
        _ = try await client.vote(submissionID: submission.id, approve: true)
        await client.castVoteAs(voterID: members[2], approve: true, submissionID: submission.id)

        let events = await client.pointEvents(groupID: group.id)
        let challengeEvents = events.filter { $0.kind == .challenge }
        XCTAssertEqual(challengeEvents.count, 1)
        XCTAssertEqual(challengeEvents.first?.points, challenge.points)
        XCTAssertEqual(challengeEvents.first?.userID, submitter)

        let bonusEvents = events.filter { $0.kind == .firstBonus }
        XCTAssertEqual(bonusEvents.count, 1)
        XCTAssertEqual(bonusEvents.first?.points, 10)
        XCTAssertEqual(bonusEvents.first?.userID, submitter)

        // The leaderboard is the sum of the ledger.
        let board = try await client.leaderboard(groupID: group.id, scope: .week)
        let entry = board.entries.first { $0.user.id == submitter }
        XCTAssertEqual(entry?.points, challenge.points + 10)
        XCTAssertEqual(entry?.rank, 1)
    }

    func testTheFirstFinisherBonusIsOnlyPaidOncePerChallenge() async throws {
        let client = makeClient()
        let (group, members) = try await makeGroup(client, memberCount: 5)
        let week = try await client.currentWeek(groupID: group.id)
        let challenge = try XCTUnwrap(week.challenges.first)

        // The first member finishes the challenge.
        let first = try await submit(client, groupID: group.id, as: members[1])
        await client.actAs(members[0])
        _ = try await client.vote(submissionID: first.id, approve: true)
        await client.castVoteAs(voterID: members[2], approve: true, submissionID: first.id)

        // The second member finishes the same challenge later.
        let second = try await submit(client, groupID: group.id, as: members[3])
        XCTAssertEqual(second.challengeId, challenge.id)
        await client.actAs(members[0])
        _ = try await client.vote(submissionID: second.id, approve: true)
        await client.castVoteAs(voterID: members[2], approve: true, submissionID: second.id)

        let events = await client.pointEvents(groupID: group.id)
        XCTAssertEqual(events.filter { $0.kind == .firstBonus }.count, 1)
        XCTAssertEqual(events.filter { $0.kind == .challenge }.count, 2)

        let board = try await client.leaderboard(groupID: group.id, scope: .week)
        let firstEntry = board.entries.first { $0.user.id == members[1] }
        let secondEntry = board.entries.first { $0.user.id == members[3] }
        XCTAssertEqual(firstEntry?.points, challenge.points + 10)
        XCTAssertEqual(secondEntry?.points, challenge.points)
    }

    func testTheLedgerHoldsWeeklyWinnerAndStreakPoints() async throws {
        let client = makeClient()
        let events = await client.pointEvents(groupID: DemoSeed.warriorsID)

        XCTAssertTrue(events.contains { $0.kind == .challenge })
        XCTAssertTrue(events.contains { $0.kind == .firstBonus })
        XCTAssertTrue(events.contains { $0.kind == .weeklyWinner })
        XCTAssertTrue(events.contains { $0.kind == .streak })
        XCTAssertTrue(events.allSatisfy { $0.points > 0 })
    }

    func testTheAllTimeLeaderboardIsTheSumOfEveryWeek() async throws {
        let client = makeClient()
        let currentWeek = try await client.currentWeek(groupID: DemoSeed.warriorsID)
        let week = try await client.leaderboard(groupID: DemoSeed.warriorsID, scope: .week)
        let all = try await client.leaderboard(groupID: DemoSeed.warriorsID, scope: .all)
        let events = await client.pointEvents(groupID: DemoSeed.warriorsID)

        let weekTotal = events
            .filter { $0.weekID == currentWeek.week.id }
            .reduce(0) { $0 + $1.points }
        XCTAssertEqual(week.entries.reduce(0) { $0 + $1.points }, weekTotal)

        let allTotal = events.reduce(0) { $0 + $1.points }
        XCTAssertEqual(all.entries.reduce(0) { $0 + $1.points }, allTotal)
        XCTAssertGreaterThan(allTotal, 0)
        XCTAssertTrue(all.entries.contains { $0.streak > 0 })
    }

    // MARK: - Pending votes

    func testPendingVotesExcludeMyOwnProofsAndTheOnesIAlreadyVotedOn() async throws {
        let client = makeClient()
        let pending = try await client.pendingVotes(groupID: DemoSeed.warriorsID)

        XCTAssertEqual(pending.items.count, 6, "The demo seeds six proofs that wait for a vote.")
        XCTAssertTrue(pending.items.allSatisfy { $0.user.id != DemoSeed.currentUserID })
        XCTAssertTrue(pending.items.allSatisfy { $0.myVote == nil })
        XCTAssertTrue(pending.items.allSatisfy { $0.status == .pending })

        // Oldest first.
        let dates = pending.items.map(\.createdAt)
        XCTAssertEqual(dates, dates.sorted())

        let target = try XCTUnwrap(pending.items.first)
        let voted = try await client.vote(submissionID: target.id, approve: true)
        XCTAssertNotNil(voted.submission.myVote)

        let after = try await client.pendingVotes(groupID: DemoSeed.warriorsID)
        XCTAssertEqual(after.items.count, 5)
        XCTAssertFalse(after.items.contains { $0.id == target.id })
    }

    func testMyPendingProofIsNotInThePendingVotes() async throws {
        let client = makeClient()
        let pending = try await client.pendingVotes(groupID: DemoSeed.warriorsID)
        let feed = try await client.feed(groupID: DemoSeed.warriorsID, cursor: nil)

        let mineInFeed = feed.items.filter { $0.user.id == DemoSeed.currentUserID && $0.status == .pending }
        XCTAssertFalse(mineInFeed.isEmpty, "The demo seeds a proof of mine that waits for votes.")
        for submission in mineInFeed {
            XCTAssertFalse(pending.items.contains { $0.id == submission.id })
        }
    }

    // MARK: - Simulated votes

    func testTheDemoPlaysTheOtherMembersOnMyOwnProof() async throws {
        let client = makeClient()
        let week = try await client.currentWeek(groupID: DemoSeed.warriorsID)
        let challenge = try XCTUnwrap(week.challenges.first { $0.myStatus == .todo })

        let mine = try await client.createSubmission(
            challengeID: challenge.id,
            media: sampleUpload,
            onProgress: { _ in }
        ).submission
        XCTAssertEqual(mine.status, .pending)

        // The members of the demo vote a moment later.
        await client.applyScheduledSimulations()

        let decided = try await client.submission(id: mine.id)
        XCTAssertEqual(decided.submission.status, .accepted)

        let events = await client.pointEvents(groupID: DemoSeed.warriorsID)
        let mineEvents = events.filter { $0.userID == DemoSeed.currentUserID }
        XCTAssertTrue(mineEvents.contains { $0.kind == .challenge })
    }

    // MARK: - Groups, profile and account

    func testTheDemoSeedsTwoGroupsFiveMembersAndFiveChallenges() async throws {
        let client = makeClient()
        let groups = try await client.groups()
        XCTAssertEqual(groups.groups.count, 2)

        let detail = try await client.groupDetail(id: DemoSeed.warriorsID)
        XCTAssertEqual(detail.members.count, 5)
        XCTAssertTrue(detail.members.allSatisfy { $0.user.avatarEmoji?.isEmpty == false })

        let week = try await client.currentWeek(groupID: DemoSeed.warriorsID)
        XCTAssertEqual(week.challenges.count, 5)
        XCTAssertEqual(week.week.status, .open)
        XCTAssertEqual(Set(week.challenges.map(\.myStatus)), [.todo, .pending, .accepted, .rejected])
    }

    func testCreateJoinAndLeaveAGroup() async throws {
        let client = makeClient()

        let created = try await client.createGroup(
            CreateGroupRequest(name: "Fresh group", challengesPerWeek: 4, theme: "Outdoors")
        ).group
        XCTAssertEqual(created.challengesPerWeek, 4)
        XCTAssertEqual(created.memberCount, 1)
        XCTAssertEqual(created.inviteCode.count, 6)

        let week = try await client.currentWeek(groupID: created.id)
        XCTAssertEqual(week.challenges.count, 4)

        // Join the group of somebody else with its invite code.
        let joined = try await client.joinGroup(
            JoinGroupRequest(inviteCode: "PL4XZ9")
        ).group
        XCTAssertEqual(joined.id, DemoSeed.sundayID)
        XCTAssertEqual(joined.memberCount, 4)

        // Leave it again.
        _ = try await client.leaveGroup(id: joined.id)
        let myGroups = try await client.groups()
        XCTAssertFalse(myGroups.groups.contains { $0.id == joined.id })
    }

    func testJoiningWithAWrongCodeFails() async throws {
        let client = makeClient()
        do {
            _ = try await client.joinGroup(JoinGroupRequest(inviteCode: "ZZZZZZ"))
            XCTFail("An unknown invite code must fail.")
        } catch {
            XCTAssertNotNil(error as? APIError)
        }
    }

    func testTheProfileCanBeEdited() async throws {
        let client = makeClient()
        let updated = try await client.updateProfile(
            UpdateMeRequest(displayName: "Alex the Demo", avatarEmoji: "🐯")
        )
        XCTAssertEqual(updated.user.displayName, "Alex the Demo")
        XCTAssertEqual(updated.user.avatarEmoji, "🐯")

        let user = try await client.currentUser()
        XCTAssertEqual(user.user.displayName, "Alex the Demo")
    }

    func testDeletingTheAccountRemovesTheUser() async throws {
        let client = makeClient()
        _ = try await client.deleteAccount()
        do {
            _ = try await client.currentUser()
            XCTFail("The account is gone.")
        } catch {
            XCTAssertNotNil(error as? APIError)
        }
    }

    func testOnlyOneActiveProofPerChallenge() async throws {
        let client = makeClient()
        let (group, _) = try await makeGroup(client, memberCount: 3)
        let week = try await client.currentWeek(groupID: group.id)
        let challenge = try XCTUnwrap(week.challenges.first)

        _ = try await client.createSubmission(
            challengeID: challenge.id,
            media: sampleUpload,
            onProgress: { _ in }
        )
        do {
            _ = try await client.createSubmission(
                challengeID: challenge.id,
                media: sampleUpload,
                onProgress: { _ in }
            )
            XCTFail("A second proof for the same challenge must fail while one is pending.")
        } catch {
            XCTAssertNotNil(error as? APIError)
        }
    }

    // MARK: - Media

    func testTheBundledDemoProofsAreAvailable() async throws {
        let key = DemoMedia.photoKey(1)
        let data = try XCTUnwrap(DemoMedia.data(for: key))
        XCTAssertGreaterThan(data.count, 0)

        let client = makeClient()
        let pending = try await client.pendingVotes(groupID: DemoSeed.warriorsID)
        let withMedia = try XCTUnwrap(pending.items.first)
        let media = try await client.mediaData(for: withMedia.mediaUrl)
        XCTAssertGreaterThan(media.count, 0)
    }

    func testTheVideoProofIsBundled() async throws {
        let client = makeClient()
        let pending = try await client.pendingVotes(groupID: DemoSeed.warriorsID)
        let video = try XCTUnwrap(pending.items.first { $0.mediaType == .video })
        let data = try await client.mediaData(for: video.mediaUrl)
        XCTAssertGreaterThan(data.count, 0)
    }
}
