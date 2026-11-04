import XCTest
@testable import Dares

/// Tests for the v3 features of the offline demo client: the banter, the veto, the
/// captain armband, the house fixture, the reports, the blocks and the bans
/// (SPEC.md, section 6).
final class DemoV3Tests: XCTestCase {
    private func makeClient() -> DemoAPIClient {
        DemoAPIClient(autoSimulate: false)
    }

    // MARK: - Helpers

    /// The first proof of another member that waits for a call.
    private func proofOfAnotherMember(_ client: DemoAPIClient) async throws -> Submission {
        let pending = try await client.pendingVotes(groupID: DemoSeed.sundayLeagueID)
        return try XCTUnwrap(pending.items.first { $0.user.id != DemoSeed.currentUserID })
    }

    /// A club of the demo with `memberCount` members — the player is always the first.
    private func makeGroup(
        _ client: DemoAPIClient,
        memberCount: Int
    ) async throws -> Group {
        let group = try await client.createGroup(
            CreateGroupRequest(name: "Test club")
        ).group
        for index in 1 ..< memberCount {
            let user = User(
                id: "test-member-\(index)",
                displayName: "Member \(index)",
                avatarEmoji: "🙂"
            )
            await client.addMember(groupID: group.id, user: user)
        }
        return group
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

    // MARK: - The house rules

    func testTheDemoStartsWithoutTheHouseRules() async throws {
        let client = makeClient()
        let me = try await client.currentUser()
        XCTAssertFalse(me.user.termsAccepted)

        let accepted = try await client.acceptTerms()
        XCTAssertTrue(accepted.user.termsAccepted)

        let after = try await client.currentUser()
        XCTAssertTrue(after.user.termsAccepted)
    }

    // MARK: - The reactions

    func testTheReactionToggles() async throws {
        let client = makeClient()
        let feed = try await client.feed(groupID: DemoSeed.sundayLeagueID, cursor: nil)
        let proof = try XCTUnwrap(feed.items.first { $0.reactions.contains { $0.emoji == "🔥" } })

        let fire = try XCTUnwrap(proof.reactions.first { $0.emoji == "🔥" })
        XCTAssertEqual(fire.count, 3)
        XCTAssertFalse(fire.mine)

        // My reaction is added.
        let added = try await client.toggleReaction(submissionID: proof.id, emoji: .fire)
        let mine = try XCTUnwrap(added.reactions.first { $0.emoji == "🔥" })
        XCTAssertTrue(mine.mine)
        XCTAssertEqual(mine.count, 4)

        // And taken away again.
        let removed = try await client.toggleReaction(submissionID: proof.id, emoji: .fire)
        let gone = try XCTUnwrap(removed.reactions.first { $0.emoji == "🔥" })
        XCTAssertFalse(gone.mine)
        XCTAssertEqual(gone.count, 3)
    }

    func testTheReactionsKeepTheOrderOfTheSpec() async throws {
        let client = makeClient()
        let feed = try await client.feed(groupID: DemoSeed.sundayLeagueID, cursor: nil)
        let proof = try XCTUnwrap(feed.items.first { !$0.reactions.isEmpty })

        let order = proof.reactions.compactMap(\.reaction)
        XCTAssertEqual(order, order.sorted { lhs, rhs in
            let left = ReactionEmoji.displayOrder.firstIndex(of: lhs) ?? 0
            let right = ReactionEmoji.displayOrder.firstIndex(of: rhs) ?? 0
            return left < right
        })
    }

    // MARK: - The comments

    func testACommentIsAddedAndDeleted() async throws {
        let client = makeClient()
        let proof = try await proofOfAnotherMember(client)

        let comment = try await client.addComment(submissionID: proof.id, text: "  The light though.  ")
        XCTAssertEqual(comment.text, "The light though.")
        XCTAssertTrue(comment.canDelete)

        let comments = try await client.comments(submissionID: proof.id)
        XCTAssertTrue(comments.contains { $0.id == comment.id })

        _ = try await client.deleteComment(id: comment.id)

        let after = try await client.comments(submissionID: proof.id)
        XCTAssertFalse(after.contains { $0.id == comment.id })
    }

    func testAnEmptyCommentIsRefused() async throws {
        let client = makeClient()
        let proof = try await proofOfAnotherMember(client)
        do {
            _ = try await client.addComment(submissionID: proof.id, text: "   ")
            XCTFail("An empty comment must fail.")
        } catch {
            XCTAssertNotNil(error as? APIError)
        }
    }

    func testOnlyTheAuthorOrTheOwnerMayDeleteAComment() async throws {
        let client = makeClient()
        let proof = try await proofOfAnotherMember(client)

        // The comment of another member.
        let comment = try await client.addComment(submissionID: proof.id, text: "Nice one")
        await client.actAs("demo-user-sam")
        do {
            _ = try await client.deleteComment(id: comment.id)
            XCTFail("A member cannot delete the comment of somebody else.")
        } catch {
            XCTAssertNotNil(error as? APIError)
        }

        // The owner of the club may.
        await client.actAs(DemoSeed.currentUserID)
        _ = try await client.deleteComment(id: comment.id)
        let after = try await client.comments(submissionID: proof.id)
        XCTAssertFalse(after.contains { $0.id == comment.id })
    }

    // MARK: - The report

    func testAReportedProofIsHiddenForTheReporter() async throws {
        let client = makeClient()
        let proof = try await proofOfAnotherMember(client)

        let before = try await client.feed(groupID: DemoSeed.sundayLeagueID, cursor: nil)
        XCTAssertTrue(before.items.contains { $0.id == proof.id })

        _ = try await client.reportSubmission(
            id: proof.id,
            request: ReportRequest(reason: .spam, note: "Not the fixture.")
        )

        let after = try await client.feed(groupID: DemoSeed.sundayLeagueID, cursor: nil)
        XCTAssertFalse(after.items.contains { $0.id == proof.id }, "A reported proof is hidden for me.")

        let pending = try await client.pendingVotes(groupID: DemoSeed.sundayLeagueID)
        XCTAssertFalse(pending.items.contains { $0.id == proof.id })
    }

    func testYouCannotReportYourOwnProof() async throws {
        let client = makeClient()
        let feed = try await client.feed(groupID: DemoSeed.sundayLeagueID, cursor: nil)
        let mine = try XCTUnwrap(feed.items.first { $0.user.id == DemoSeed.currentUserID })

        do {
            _ = try await client.reportSubmission(id: mine.id, request: ReportRequest(reason: .spam))
            XCTFail("You cannot report your own proof.")
        } catch {
            XCTAssertNotNil(error as? APIError)
        }
    }

    func testTheSameProofIsNotReportedTwice() async throws {
        let client = makeClient()
        let proof = try await proofOfAnotherMember(client)
        _ = try await client.reportSubmission(id: proof.id, request: ReportRequest(reason: .spam))

        do {
            _ = try await client.reportSubmission(id: proof.id, request: ReportRequest(reason: .spam))
            XCTFail("One report per proof and reporter.")
        } catch {
            XCTAssertNotNil(error as? APIError)
        }
    }

    func testTwoReportsRemoveTheProofForEverybody() async throws {
        let client = makeClient()
        let proof = try await proofOfAnotherMember(client)

        _ = try await client.reportSubmission(id: proof.id, request: ReportRequest(reason: .spam))
        await client.actAs("demo-user-sam")
        _ = try await client.reportSubmission(id: proof.id, request: ReportRequest(reason: .spam))

        await client.actAs(DemoSeed.currentUserID)
        let feed = try await client.feed(groupID: DemoSeed.sundayLeagueID, cursor: nil)
        XCTAssertFalse(feed.items.contains { $0.id == proof.id })

        let submission = try await client.submission(id: proof.id)
        XCTAssertEqual(submission.submission.status, .removed)
    }

    // MARK: - The block

    func testABlockedMemberDisappearsFromTheFeedAndTheCalls() async throws {
        let client = makeClient()
        let pending = try await client.pendingVotes(groupID: DemoSeed.sundayLeagueID)
        let mika = try XCTUnwrap(pending.items.first { $0.user.id == "demo-user-mika" })

        _ = try await client.blockUser("demo-user-mika")

        let after = try await client.pendingVotes(groupID: DemoSeed.sundayLeagueID)
        XCTAssertFalse(after.items.contains { $0.id == mika.id })

        let feed = try await client.feed(groupID: DemoSeed.sundayLeagueID, cursor: nil)
        XCTAssertFalse(feed.items.contains { $0.user.id == "demo-user-mika" })

        // The threshold of the proof does not change — the block only hides it.
        let submission = try await client.submission(id: mika.id)
        XCTAssertEqual(submission.submission.eligibleVoters, mika.eligibleVoters)

        let blocked = try await client.blockedUsers()
        XCTAssertTrue(blocked.contains { $0.id == "demo-user-mika" })

        // And unblocking brings the proof back.
        _ = try await client.unblockUser("demo-user-mika")
        let back = try await client.pendingVotes(groupID: DemoSeed.sundayLeagueID)
        XCTAssertTrue(back.items.contains { $0.id == mika.id })
    }

    func testTheDemoSeedsABlockedMember() async throws {
        let client = makeClient()
        let blocked = try await client.blockedUsers()
        XCTAssertTrue(blocked.contains { $0.displayName == "Nina" })
    }

    // MARK: - The veto

    func testTheFixtureIsReplacedWhenTheClubHasTheMajority() async throws {
        let client = makeClient()
        let week = try await client.currentWeek(groupID: DemoSeed.sundayLeagueID)
        let fixture = try XCTUnwrap(week.challenges.first { $0.position == 5 })

        // The demo seeds one veto of three.
        XCTAssertEqual(fixture.vetoCount, 1)
        XCTAssertEqual(fixture.vetoThreshold, 3)

        // My veto is the second one — the fixture stays.
        let second = try await client.vetoChallenge(id: fixture.id)
        XCTAssertFalse(second.replaced)
        XCTAssertEqual(second.challenge.vetoCount, 2)

        // The third veto replaces the fixture in place.
        await client.actAs("demo-user-lee")
        let third = try await client.vetoChallenge(id: fixture.id)
        XCTAssertTrue(third.replaced)
        XCTAssertEqual(third.challenge.position, 5, "The replacement keeps the place of the fixture.")
        XCTAssertTrue(third.challenge.isNew)
    }

    func testAVetoCanBeTakenBack() async throws {
        let client = makeClient()
        let week = try await client.currentWeek(groupID: DemoSeed.sundayLeagueID)
        let fixture = try XCTUnwrap(week.challenges.first { $0.position == 5 })

        let vetoed = try await client.vetoChallenge(id: fixture.id)
        XCTAssertTrue(vetoed.challenge.myVeto)
        XCTAssertEqual(vetoed.challenge.vetoCount, 2)

        let back = try await client.vetoChallenge(id: fixture.id)
        XCTAssertFalse(back.challenge.myVeto)
        XCTAssertEqual(back.challenge.vetoCount, 1)
    }

    func testTheClubHasTwoReplacementsPerMatchweek() async throws {
        let client = makeClient()
        let week = try await client.currentWeek(groupID: DemoSeed.sundayLeagueID)

        // The demo seeds one replacement of the two.
        XCTAssertEqual(week.week.vetoesUsed, 1)

        // The fixture at the place of five is replaced — the second replacement.
        let fixture = try XCTUnwrap(week.challenges.first { $0.position == 5 })
        _ = try await client.vetoChallenge(id: fixture.id)
        await client.actAs("demo-user-lee")
        _ = try await client.vetoChallenge(id: fixture.id)

        let after = try await client.currentWeek(groupID: DemoSeed.sundayLeagueID)
        XCTAssertEqual(after.week.vetoesUsed, 2)

        // The next veto of another fixture is refused — the third replacement is too much.
        let other = try XCTUnwrap(after.challenges.first { $0.position == 4 })
        await client.actAs("demo-user-jo")
        _ = try await client.vetoChallenge(id: other.id)
        await client.actAs("demo-user-mika")
        _ = try await client.vetoChallenge(id: other.id)
        await client.actAs("demo-user-sam")
        do {
            _ = try await client.vetoChallenge(id: other.id)
            XCTFail("The third replacement of the matchweek must fail.")
        } catch {
            XCTAssertNotNil(error as? APIError)
        }
    }

    // MARK: - The captain armband

    func testTheDemoSeedsACaptainPick() async throws {
        let client = makeClient()
        let week = try await client.currentWeek(groupID: DemoSeed.sundayLeagueID)

        let captain = try XCTUnwrap(week.challenges.first { $0.isCaptain })
        XCTAssertEqual(captain.position, 3)
        XCTAssertEqual(week.week.myCaptainChallengeId, captain.id)
    }

    func testTheArmbandLocksWhenYouPlayedTheFixture() async throws {
        let client = makeClient()
        let week = try await client.currentWeek(groupID: DemoSeed.sundayLeagueID)
        let other = try XCTUnwrap(week.challenges.first { !$0.isCaptain })

        do {
            _ = try await client.setCaptain(
                groupID: DemoSeed.sundayLeagueID,
                challengeID: other.id
            )
            XCTFail("The armband is locked once you played your captain fixture.")
        } catch {
            XCTAssertNotNil(error as? APIError)
        }
    }

    func testTheArmbandCanBeWornWhenTheFixtureIsNotPlayed() async throws {
        let client = makeClient()
        let group = try await makeGroup(client, memberCount: 4)
        let week = try await client.currentWeek(groupID: group.id)
        let fixture = try XCTUnwrap(week.challenges.first)

        let response = try await client.setCaptain(
            groupID: group.id,
            challengeID: fixture.id
        )
        XCTAssertEqual(response.week?.myCaptainChallengeId, fixture.id)
        XCTAssertEqual(response.challenge?.isCaptain, true)
    }

    func testTheArmbandLocksWhenYouPlayTheFixture() async throws {
        let client = makeClient()
        let group = try await makeGroup(client, memberCount: 4)
        let week = try await client.currentWeek(groupID: group.id)
        let fixture = try XCTUnwrap(week.challenges.first)
        let other = try XCTUnwrap(week.challenges.last)

        _ = try await client.setCaptain(groupID: group.id, challengeID: fixture.id)

        // Now I play my captain fixture — the armband is locked.
        _ = try await client.createSubmission(
            challengeID: fixture.id,
            media: sampleUpload,
            onProgress: { _ in }
        )

        do {
            _ = try await client.setCaptain(groupID: group.id, challengeID: other.id)
            XCTFail("The armband is locked once you played your captain fixture.")
        } catch {
            XCTAssertNotNil(error as? APIError)
        }
    }

    func testTheCaptainBonusDoublesTheFixture() async throws {
        let client = makeClient()
        let group = try await makeGroup(client, memberCount: 5)
        let week = try await client.currentWeek(groupID: group.id)
        let fixture = try XCTUnwrap(week.challenges.first)

        _ = try await client.setCaptain(groupID: group.id, challengeID: fixture.id)

        // A new proof of mine on the captain fixture, accepted by the club.
        let mine = try await client.createSubmission(
            challengeID: fixture.id,
            media: sampleUpload,
            onProgress: { _ in }
        ).submission
        XCTAssertEqual(mine.status, .pending)

        await client.actAs("demo-user-jo")
        _ = try await client.vote(submissionID: mine.id, approve: true)
        await client.castVoteAs(voterID: "demo-user-sam", approve: true, submissionID: mine.id)

        let events = await client.pointEvents(groupID: group.id)
        let captainEvents = events.filter { $0.kind == .captain }
        XCTAssertEqual(captainEvents.count, 1)
        XCTAssertEqual(captainEvents.first?.points, fixture.points)

        // The receipt shows the line of the armband.
        await client.actAs(DemoSeed.currentUserID)
        let receipt = try await client.receipt(
            groupID: group.id,
            weekID: week.week.id
        )
        XCTAssertTrue(receipt.lines.contains { $0.label == "CAPTAIN ×2" })
    }

    // MARK: - The house fixture

    func testTheHouseFixtureOfAnotherClubIsWrittenByItsOwner() async throws {
        let client = makeClient()
        let week = try await client.currentWeek(groupID: DemoSeed.bankHolidayID)

        XCTAssertEqual(week.houseFixture?.allowed, false, "The house fixture of the week is already written.")
        XCTAssertEqual(week.houseFixture?.author?.displayName, "Sam")
        XCTAssertTrue(week.challenges.contains { $0.isHouse })
    }

    func testTheManOfTheMatchMayWriteTheHouseFixture() async throws {
        let client = makeClient()
        let week = try await client.currentWeek(groupID: DemoSeed.sundayLeagueID)

        XCTAssertEqual(week.houseFixture?.allowed, true, "Alex was the man of the match of the last matchweek.")

        let challenge = try await client.addHouseFixture(
            groupID: DemoSeed.sundayLeagueID,
            request: HouseFixtureRequest(
                title: "Film your best goalie save",
                description: "Any goalie, any ball.",
                difficulty: .easy
            )
        )
        XCTAssertTrue(challenge.isHouse)
        XCTAssertEqual(challenge.createdBy?.displayName, "Alex")

        // Only one house fixture per matchweek.
        do {
            _ = try await client.addHouseFixture(
                groupID: DemoSeed.sundayLeagueID,
                request: HouseFixtureRequest(
                    title: "Another one",
                    description: "",
                    difficulty: .easy
                )
            )
            XCTFail("The house fixture of the matchweek is already written.")
        } catch {
            XCTAssertNotNil(error as? APIError)
        }
    }

    func testAMemberWhoIsNotTheManOfTheMatchMayNotWriteTheHouseFixture() async throws {
        let client = makeClient()
        await client.actAs("demo-user-mika")
        do {
            _ = try await client.addHouseFixture(
                groupID: DemoSeed.sundayLeagueID,
                request: HouseFixtureRequest(
                    title: "My own fixture",
                    description: "",
                    difficulty: .easy
                )
            )
            XCTFail("Only the man of the match writes the house fixture.")
        } catch {
            XCTAssertNotNil(error as? APIError)
        }
    }

    // MARK: - The owner

    func testTheOwnerRemovesAMemberAndSeesTheBannedList() async throws {
        let client = makeClient()

        // The demo seeds Tom as a member the owner removed.
        let bans = try await client.bannedMembers(groupID: DemoSeed.sundayLeagueID)
        XCTAssertTrue(bans.contains { $0.user.displayName == "Tom" })

        // The owner removes Lee.
        _ = try await client.removeMember(groupID: DemoSeed.sundayLeagueID, userID: "demo-user-lee")

        let detail = try await client.groupDetail(id: DemoSeed.sundayLeagueID)
        XCTAssertFalse(detail.members.contains { $0.user.id == "demo-user-lee" })

        let after = try await client.bannedMembers(groupID: DemoSeed.sundayLeagueID)
        XCTAssertTrue(after.contains { $0.user.displayName == "Lee" })

        // A banned member cannot come back with the invite code.
        await client.actAs("demo-user-lee")
        do {
            _ = try await client.joinGroup(
                JoinGroupRequest(inviteCode: DemoSeed.groups.first { $0.id == DemoSeed.sundayLeagueID }?.inviteCode ?? "")
            )
            XCTFail("A banned member cannot join the club.")
        } catch {
            XCTAssertNotNil(error as? APIError)
        }

        // The owner lifts the ban.
        await client.actAs(DemoSeed.currentUserID)
        _ = try await client.unbanMember(groupID: DemoSeed.sundayLeagueID, userID: "demo-user-lee")
        let lifted = try await client.bannedMembers(groupID: DemoSeed.sundayLeagueID)
        XCTAssertFalse(lifted.contains { $0.user.displayName == "Lee" })
    }

    func testAMemberThatIsNotTheOwnerCannotRemoveSomebody() async throws {
        let client = makeClient()
        await client.actAs("demo-user-jo")
        do {
            _ = try await client.removeMember(groupID: DemoSeed.sundayLeagueID, userID: "demo-user-lee")
            XCTFail("Only the owner of the club removes a member.")
        } catch {
            XCTAssertNotNil(error as? APIError)
        }
    }

    // MARK: - The notification switches

    func testTheNotificationSwitchesCanBeChanged() async throws {
        let client = makeClient()
        let seeded = try await client.notificationPrefs()
        XCTAssertTrue(seeded.newWeek)
        XCTAssertFalse(seeded.deadline, "The demo switches the Sunday reminder off.")

        var changed = seeded
        changed.deadline = true
        changed.banter = false
        let saved = try await client.updateNotificationPrefs(changed)
        XCTAssertTrue(saved.deadline)
        XCTAssertFalse(saved.banter)

        let after = try await client.notificationPrefs()
        XCTAssertTrue(after.deadline)
        XCTAssertFalse(after.banter)
    }

    // MARK: - The invite link

    func testTheInviteLinkShowsTheClubWithoutJoiningIt() async throws {
        let client = makeClient()
        let group = try await client.joinPreview(code: "K7M2PQ")
        XCTAssertEqual(group.name, DemoSeed.clubName)
        XCTAssertEqual(group.memberCount, 5)

        // The preview never joins the club.
        let groups = try await client.groups()
        XCTAssertTrue(groups.groups.contains { $0.id == group.id })
        XCTAssertEqual(groups.groups.count, 3, "The preview does not change the clubs of the player.")
    }

    func testAnUnknownInviteCodeHasNoPreview() async throws {
        let client = makeClient()
        do {
            _ = try await client.joinPreview(code: "ZZZZZZ")
            XCTFail("An unknown invite code has no club.")
        } catch {
            XCTAssertNotNil(error as? APIError)
        }
    }
}
