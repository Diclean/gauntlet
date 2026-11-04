import XCTest
@testable import Dares

/// Decoding tests for the v2 models of the REST contract (SPEC.md, section 5 —
/// "v2 additions — Sunday League").
final class ModelsV2DecodingTests: XCTestCase {
    // MARK: - Fixtures

    private let userJSON = """
    {
      "id": "u_1",
      "displayName": "Alex",
      "avatarEmoji": "🦊"
    }
    """

    private let raceJSON = """
    {
      "weeks": [
        { "id": "w_11", "number": 11, "startsAt": 1762128000 },
        { "id": "w_12", "number": 12, "startsAt": 1762732800 }
      ],
      "series": [
        {
          "user": { "id": "u_1", "displayName": "Alex", "avatarEmoji": "🦊" },
          "cumulative": [250, 365],
          "perWeek": [30, 115]
        },
        {
          "user": { "id": "u_2", "displayName": "Lee", "avatarEmoji": "🐧" },
          "cumulative": [280, 340],
          "perWeek": [25, 60]
        }
      ],
      "me": {
        "bestWeek": { "number": 12, "points": 115 },
        "avgPerWeek": 46,
        "streak": 4
      }
    }
    """

    private let receiptJSON = """
    {
      "week": {
        "id": "w_12",
        "number": 12,
        "startsAt": 1762732800,
        "endsAt": 1763337599
      },
      "club": {
        "name": "Sunday League FC",
        "forfeit": "Buys the round 🍺"
      },
      "player": {
        "user": { "id": "u_1", "displayName": "Alex", "avatarEmoji": "🦊" },
        "rank": 1,
        "rankDelta": 2,
        "total": 115
      },
      "lines": [
        { "label": "01 SUNRISE ON A HILL", "points": 10, "struck": false },
        { "label": "04 SUNSET SWIM · VAR: NO GOAL", "points": 0, "struck": true },
        { "label": "FIRST TO SCORE BONUS", "points": 10, "struck": false }
      ],
      "manOfTheMatch": { "id": "u_1", "displayName": "Alex", "avatarEmoji": "🦊" },
      "woodenSpoon": { "id": "u_5", "displayName": "Mika", "avatarEmoji": "🐙" }
    }
    """

    private let awardsJSON = """
    {
      "month": "2026-11",
      "awards": [
        {
          "award": "wooden_spoon",
          "winners": [{ "id": "u_5", "displayName": "Mika", "avatarEmoji": "🐙" }],
          "value": 60,
          "nominees": [
            { "user": { "id": "u_5", "displayName": "Mika", "avatarEmoji": "🐙" }, "value": 60 }
          ]
        },
        {
          "award": "player_of_the_month",
          "winners": [{ "id": "u_1", "displayName": "Alex", "avatarEmoji": "🦊" }],
          "value": 365,
          "nominees": [
            { "user": { "id": "u_1", "displayName": "Alex", "avatarEmoji": "🦊" }, "value": 365 },
            { "user": { "id": "u_2", "displayName": "Lee", "avatarEmoji": "🐧" }, "value": 340 }
          ]
        }
      ]
    }
    """

    private let monthsJSON = """
    { "months": ["2026-11", "2026-10"] }
    """

    private let trophiesJSON = """
    {
      "trophies": [
        {
          "groupId": "g_1",
          "groupName": "Sunday League FC",
          "month": "2026-11",
          "award": "player_of_the_month",
          "value": 365
        },
        {
          "groupId": "g_1",
          "groupName": "Sunday League FC",
          "month": "2026-10",
          "award": "golden_boot",
          "value": 16
        }
      ]
    }
    """

    // MARK: - Tests

    func testTheRaceDecodes() throws {
        let race = try APIJSON.decoder().decode(RaceResponse.self, from: Data(raceJSON.utf8))

        XCTAssertEqual(race.weeks.count, 2)
        XCTAssertEqual(race.weeks.first?.number, 11)
        XCTAssertEqual(race.weeks.last?.number, 12)
        XCTAssertEqual(race.weeks.last?.startsAt, Date(timeIntervalSince1970: 1_762_732_800))

        XCTAssertEqual(race.series.count, 2)
        XCTAssertEqual(race.series.first?.user.displayName, "Alex")
        XCTAssertEqual(race.series.first?.cumulative, [250, 365])
        XCTAssertEqual(race.series.first?.perWeek, [30, 115])

        XCTAssertEqual(race.me.bestWeek.number, 12)
        XCTAssertEqual(race.me.bestWeek.points, 115)
        XCTAssertEqual(race.me.avgPerWeek, 46)
        XCTAssertEqual(race.me.streak, 4)
    }

    func testTheReceiptDecodes() throws {
        let receipt = try APIJSON.decoder().decode(ReceiptResponse.self, from: Data(receiptJSON.utf8))

        XCTAssertEqual(receipt.week.number, 12)
        XCTAssertEqual(receipt.club.name, "Sunday League FC")
        XCTAssertEqual(receipt.club.forfeit, "Buys the round 🍺")

        XCTAssertEqual(receipt.player.user.displayName, "Alex")
        XCTAssertEqual(receipt.player.rank, 1)
        XCTAssertEqual(receipt.player.rankDelta, 2)
        XCTAssertEqual(receipt.player.total, 115)

        XCTAssertEqual(receipt.lines.count, 3)
        XCTAssertEqual(receipt.lines.first?.label, "01 SUNRISE ON A HILL")
        XCTAssertEqual(receipt.lines.first?.points, 10)
        XCTAssertFalse(receipt.lines.first?.struck ?? true)
        XCTAssertTrue(receipt.lines[1].struck, "A rejected proof is struck through.")
        XCTAssertEqual(receipt.lines[1].points, 0)

        XCTAssertEqual(receipt.manOfTheMatch?.displayName, "Alex")
        XCTAssertEqual(receipt.woodenSpoon?.displayName, "Mika")
    }

    func testTheAwardsDecode() throws {
        let awards = try APIJSON.decoder().decode(AwardsResponse.self, from: Data(awardsJSON.utf8))

        XCTAssertEqual(awards.month, "2026-11")
        XCTAssertEqual(awards.awards.count, 2)
        XCTAssertEqual(awards.awards.first?.award, .woodenSpoon)
        XCTAssertEqual(awards.awards.first?.winners.first?.displayName, "Mika")
        XCTAssertEqual(awards.awards.first?.value, 60)
        XCTAssertEqual(awards.awards.last?.award, .playerOfTheMonth)
        XCTAssertEqual(awards.awards.last?.nominees.count, 2)
        XCTAssertEqual(awards.awards.last?.nominees.last?.value, 340)
    }

    func testTheAwardMonthsDecode() throws {
        let months = try APIJSON.decoder().decode(AwardMonthsResponse.self, from: Data(monthsJSON.utf8))
        XCTAssertEqual(months.months, ["2026-11", "2026-10"])
    }

    func testTheTrophiesDecode() throws {
        let trophies = try APIJSON.decoder().decode(TrophiesResponse.self, from: Data(trophiesJSON.utf8))

        XCTAssertEqual(trophies.trophies.count, 2)
        XCTAssertEqual(trophies.trophies.first?.groupName, "Sunday League FC")
        XCTAssertEqual(trophies.trophies.first?.month, "2026-11")
        XCTAssertEqual(trophies.trophies.first?.award, .playerOfTheMonth)
        XCTAssertEqual(trophies.trophies.last?.award, .goldenBoot)
    }

    func testTheGroupCarriesTheForfeit() throws {
        let groupJSON = """
        {
          "id": "g_1",
          "name": "Sunday League FC",
          "inviteCode": "K7M2PQ",
          "challengesPerWeek": 5,
          "theme": "One kick, one dares",
          "language": "en",
          "timezone": "Europe/Paris",
          "ownerId": "u_1",
          "memberCount": 5,
          "forfeit": "Buys the round 🍺"
        }
        """
        let group = try APIJSON.decoder().decode(Group.self, from: Data(groupJSON.utf8))
        XCTAssertEqual(group.forfeit, "Buys the round 🍺")
    }

    func testTheGroupFallsBackToTheDefaultForfeit() throws {
        let groupJSON = """
        {
          "id": "g_1",
          "name": "Sunday League FC",
          "inviteCode": "K7M2PQ",
          "challengesPerWeek": 5,
          "theme": null,
          "language": "en",
          "timezone": "Europe/Paris",
          "ownerId": "u_1",
          "memberCount": 5
        }
        """
        let group = try APIJSON.decoder().decode(Group.self, from: Data(groupJSON.utf8))
        XCTAssertEqual(group.forfeit, Group.defaultForfeit)
    }

    func testTheWeekCarriesTheMatchweekNumber() throws {
        let weekJSON = """
        {
          "id": "w_12",
          "number": 12,
          "startsAt": 1762732800,
          "endsAt": 1763337599,
          "voteDeadline": 1763381999,
          "status": "open"
        }
        """
        let week = try APIJSON.decoder().decode(Week.self, from: Data(weekJSON.utf8))
        XCTAssertEqual(week.number, 12)
        XCTAssertEqual(week.status, .open)
    }

    func testTheAwardOrderIsTheCeremonyOrder() {
        XCTAssertEqual(
            AwardKey.ceremonyOrder,
            [.woodenSpoon, .comebackKid, .toughestRef, .firstToScore, .goldenBoot, .playerOfTheMonth]
        )
    }

    func testTheMonthNamesAreWrittenInCaps() {
        XCTAssertEqual(AwardKey.monthName(for: "2026-11"), "NOVEMBER")
        XCTAssertEqual(AwardKey.shortMonth(for: "2026-11"), "NOV 2026")
        XCTAssertEqual(AwardKey.monthName(for: "2026-10"), "OCTOBER")
        XCTAssertEqual(AwardKey.shortMonth(for: "2026-01"), "JAN 2026")
    }
}
