import XCTest
@testable import Dares

/// Tests for the v2 endpoints of the demo client: the title race, the full-time receipt,
/// the awards night and the trophy cabinet (SPEC.md, section 5).
final class DemoV2Tests: XCTestCase {
    private func makeClient() -> DemoAPIClient {
        DemoAPIClient(autoSimulate: false)
    }

    // MARK: - Title race

    func testTheRaceShowsTheLastEightMatchweeksOfTheSeason() async throws {
        let client = makeClient()
        let race = try await client.race(groupID: DemoSeed.sundayLeagueID)

        XCTAssertEqual(race.weeks.count, DemoSeed.matchweekCount)
        XCTAssertEqual(race.weeks.first?.number, 1)
        XCTAssertEqual(race.weeks.last?.number, DemoSeed.matchweekCount)
        XCTAssertEqual(race.series.count, 5)

        for series in race.series {
            XCTAssertEqual(series.cumulative.count, race.weeks.count)
            XCTAssertEqual(series.perWeek.count, race.weeks.count)
        }
    }

    func testTheRaceTellsTheStoryOfTheSeason() async throws {
        let client = makeClient()
        let race = try await client.race(groupID: DemoSeed.sundayLeagueID)

        let alex = try XCTUnwrap(race.series.first { $0.user.id == DemoSeed.currentUserID })
        let lee = try XCTUnwrap(race.series.first { $0.user.id == "demo-user-lee" })

        // Alex takes the title in the last matchweek with 115 points.
        XCTAssertEqual(alex.cumulative.last, 365)
        XCTAssertEqual(alex.perWeek.last, 115)
        XCTAssertEqual(lee.cumulative.last, 340)

        // Lee led the table until the last matchweek.
        let beforeLast = alex.cumulative.count - 2
        XCTAssertLessThan(alex.cumulative[beforeLast], lee.cumulative[beforeLast])
        XCTAssertGreaterThan(alex.cumulative.last ?? 0, lee.cumulative.last ?? 0)
    }

    func testTheRaceKnowsMyBestWeekAndMyForm() async throws {
        let client = makeClient()
        let race = try await client.race(groupID: DemoSeed.sundayLeagueID)

        XCTAssertEqual(race.me.bestWeek.number, DemoSeed.matchweekCount)
        XCTAssertEqual(race.me.bestWeek.points, 115)
        XCTAssertEqual(race.me.avgPerWeek, 46)
        XCTAssertEqual(race.me.streak, 4)
    }

    // MARK: - Full-time receipt

    func testTheReceiptOfTheCurrentMatchweek() async throws {
        let client = makeClient()
        let week = try await client.currentWeek(groupID: DemoSeed.sundayLeagueID)
        let receipt = try await client.receipt(groupID: DemoSeed.sundayLeagueID, weekID: week.week.id)

        XCTAssertEqual(receipt.week.number, DemoSeed.matchweekCount)
        XCTAssertEqual(receipt.club.name, DemoSeed.clubName)
        XCTAssertEqual(receipt.club.forfeit, "Buys the round 🍺")
        XCTAssertEqual(receipt.player.user.id, DemoSeed.currentUserID)
        XCTAssertEqual(receipt.player.rank, 1)
        XCTAssertEqual(receipt.player.total, 115)

        let labels = receipt.lines.map(\.label)
        XCTAssertTrue(labels.contains { $0.hasPrefix("01 SUNRISE ON A HILL") })
        XCTAssertTrue(labels.contains { $0.hasPrefix("04 SUNSET SWIM") })
        XCTAssertTrue(labels.contains("FIRST TO SCORE BONUS"))

        // The red card is struck through and worth nothing.
        let red = try XCTUnwrap(receipt.lines.first { $0.struck })
        XCTAssertEqual(red.points, 0)
        XCTAssertTrue(red.label.contains("VAR: NO GOAL"))

        XCTAssertEqual(receipt.manOfTheMatch?.displayName, "Alex")
        XCTAssertEqual(receipt.woodenSpoon?.displayName, "Mika")
    }

    func testThePastMatchweeksHaveReceiptsToo() async throws {
        let client = makeClient()
        let weeks = try await client.weeks(groupID: DemoSeed.sundayLeagueID, limit: 10)

        XCTAssertGreaterThan(weeks.count, 1)
        let past = try XCTUnwrap(weeks.first { $0.status == .closed })
        let receipt = try await client.receipt(groupID: DemoSeed.sundayLeagueID, weekID: past.id)
        XCTAssertEqual(receipt.week.number, past.number)
        XCTAssertFalse(receipt.lines.isEmpty)
    }

    // MARK: - Awards

    func testTheAwardsNightHasTheSixAwardsInTheCeremonyOrder() async throws {
        let client = makeClient()
        let awards = try await client.awards(groupID: DemoSeed.sundayLeagueID, month: nil)

        XCTAssertEqual(awards.awards.count, 6)
        XCTAssertEqual(awards.awards.map(\.award), AwardKey.ceremonyOrder)
        XCTAssertFalse(awards.month.isEmpty)

        let playerOfTheMonth = try XCTUnwrap(awards.awards.first { $0.award == .playerOfTheMonth })
        XCTAssertEqual(playerOfTheMonth.winners.first?.id, DemoSeed.currentUserID)
        XCTAssertEqual(playerOfTheMonth.value, 365)
        XCTAssertEqual(playerOfTheMonth.nominees.count, 3)

        let woodenSpoon = try XCTUnwrap(awards.awards.first { $0.award == .woodenSpoon })
        XCTAssertEqual(woodenSpoon.winners.first?.id, "demo-user-mika")
    }

    /// Every award measures its own metric and the best player of that metric is the
    /// winner — the Wooden Spoon is the exception: it goes to the player with the
    /// fewest points, so its nominees are the three worst of the club, worst first.
    func testTheNomineesOfEveryAwardFollowItsOwnMetric() async throws {
        let client = makeClient()
        let awards = try await client.awards(groupID: DemoSeed.sundayLeagueID, month: nil)

        for award in awards.awards {
            let nominees = award.nominees
            XCTAssertEqual(nominees.count, 3, "\(award.award.title) needs three nominees")

            // The winner of the award is the first nominee.
            XCTAssertEqual(
                nominees.first?.user.id,
                award.winners.first?.id,
                "\(award.award.title) must nominate its winner first"
            )

            let values = nominees.map(\.value)
            if award.award == .woodenSpoon {
                XCTAssertEqual(
                    values,
                    values.sorted(),
                    "The Wooden Spoon nominates the fewest points first"
                )
            } else {
                XCTAssertEqual(
                    values,
                    values.sorted(by: >),
                    "\(award.award.title) nominates the best value first"
                )
            }
        }
    }

    func testTheWoodenSpoonNominatesTheBottomOfTheTable() async throws {
        let client = makeClient()
        let awards = try await client.awards(groupID: DemoSeed.sundayLeagueID, month: nil)
        let woodenSpoon = try XCTUnwrap(awards.awards.first { $0.award == .woodenSpoon })

        // Mika (60), Sam (195) and Jo (230) — the three worst of the season.
        XCTAssertEqual(
            woodenSpoon.nominees.map(\.user.id),
            ["demo-user-mika", "demo-user-sam", "demo-user-jo"]
        )
        XCTAssertEqual(woodenSpoon.nominees.map(\.value), [60, 195, 230])
        XCTAssertEqual(woodenSpoon.winners.first?.id, "demo-user-mika")
    }

    func testTheOtherAwardsNominateTheirOwnMetric() async throws {
        let client = makeClient()
        let awards = try await client.awards(groupID: DemoSeed.sundayLeagueID, month: nil)

        func nominees(_ key: AwardKey) throws -> [AwardNominee] {
            try XCTUnwrap(awards.awards.first { $0.award == key }).nominees
        }

        // The golden boot counts goals, not points.
        XCTAssertEqual(try nominees(.goldenBoot).map(\.value), [16, 14, 11])
        // The toughest ref counts no-goal calls.
        XCTAssertEqual(try nominees(.toughestRef).map(\.value), [9, 4, 3])
        // The comeback kid counts the climb.
        XCTAssertEqual(try nominees(.comebackKid).map(\.value), [3, 2, 1])
        // The first to score counts the first finishes.
        XCTAssertEqual(try nominees(.firstToScore).map(\.value), [5, 4, 3])
        // The player of the month counts the points of the season.
        XCTAssertEqual(try nominees(.playerOfTheMonth).map(\.value), [365, 340, 230])
    }

    func testTheAwardMonthsAreListedNewestFirst() async throws {
        let client = makeClient()
        let months = try await client.awardMonths(groupID: DemoSeed.sundayLeagueID)
        XCTAssertEqual(months.count, 2)
        XCTAssertEqual(months, months.sorted(by: >))
    }

    func testTheTrophyCabinetHoldsTheSilverwareOfThePlayer() async throws {
        let client = makeClient()
        let trophies = try await client.trophies()
        XCTAssertFalse(trophies.isEmpty)
        XCTAssertTrue(trophies.allSatisfy { $0.groupName == DemoSeed.clubName })
        XCTAssertTrue(trophies.contains { $0.award == .playerOfTheMonth })
    }

    // MARK: - The forfeit

    func testTheClubCarriesItsForfeit() async throws {
        let client = makeClient()
        let detail = try await client.groupDetail(id: DemoSeed.sundayLeagueID)
        XCTAssertEqual(detail.group.forfeit, "Buys the round 🍺")
    }

    func testTheOwnerCanChangeTheForfeit() async throws {
        let client = makeClient()
        let updated = try await client.updateGroup(
            id: DemoSeed.sundayLeagueID,
            request: UpdateGroupRequest(forfeit: "Pays for the chips 🍟")
        )
        XCTAssertEqual(updated.group.forfeit, "Pays for the chips 🍟")

        let detail = try await client.groupDetail(id: DemoSeed.sundayLeagueID)
        XCTAssertEqual(detail.group.forfeit, "Pays for the chips 🍟")
    }

    // MARK: - The table

    func testTheTableOfTheMatchweekMatchesTheMock() async throws {
        let client = makeClient()
        let board = try await client.leaderboard(groupID: DemoSeed.sundayLeagueID, scope: .week)
        let points = board.entries.map { ($0.user.displayName, $0.points) }

        XCTAssertEqual(points.first { $0.0 == "Alex" }?.1, 115)
        XCTAssertEqual(points.first { $0.0 == "Lee" }?.1, 60)
        XCTAssertEqual(points.first { $0.0 == "Jo" }?.1, 35)
        XCTAssertEqual(points.first { $0.0 == "Sam" }?.1, 10)
        XCTAssertEqual(points.first { $0.0 == "Mika" }?.1, 0)
    }

    func testTheSeasonTableMatchesTheMock() async throws {
        let client = makeClient()
        let board = try await client.leaderboard(groupID: DemoSeed.sundayLeagueID, scope: .all)
        let points = board.entries.map { ($0.user.displayName, $0.points) }

        XCTAssertEqual(points.first { $0.0 == "Alex" }?.1, 365)
        XCTAssertEqual(points.first { $0.0 == "Lee" }?.1, 340)
        XCTAssertEqual(points.first { $0.0 == "Jo" }?.1, 230)
        XCTAssertEqual(points.first { $0.0 == "Sam" }?.1, 195)
        XCTAssertEqual(points.first { $0.0 == "Mika" }?.1, 60)
    }
}
