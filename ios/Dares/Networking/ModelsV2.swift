import Foundation

// MARK: - v2 models (SPEC.md, section 5 — "Sunday League")

/// The monthly awards. The raw values are the keys of the `monthly_awards` table.
enum AwardKey: String, Codable, CaseIterable, Identifiable, Sendable {
    case woodenSpoon = "wooden_spoon"
    case comebackKid = "comeback_kid"
    case toughestRef = "toughest_ref"
    case firstToScore = "first_to_score"
    case goldenBoot = "golden_boot"
    case playerOfTheMonth = "player_of_the_month"

    var id: String { rawValue }

    /// The order of the ceremony (SPEC.md, section 5).
    static let ceremonyOrder: [AwardKey] = [
        .woodenSpoon, .comebackKid, .toughestRef, .firstToScore, .goldenBoot, .playerOfTheMonth,
    ]

    /// The name of the award as it is written on the envelope.
    var title: String {
        switch self {
        case .woodenSpoon: "Wooden Spoon"
        case .comebackKid: "Comeback Kid"
        case .toughestRef: "Toughest Ref"
        case .firstToScore: "First to Score"
        case .goldenBoot: "Golden Boot"
        case .playerOfTheMonth: "Player of the Month"
        }
    }

    /// The emoji of the award (DESIGN.md, section 5).
    var icon: String {
        switch self {
        case .woodenSpoon: "🥄"
        case .comebackKid: "📈"
        case .toughestRef: "🟨"
        case .firstToScore: "⚡"
        case .goldenBoot: "🥾"
        case .playerOfTheMonth: "🏆"
        }
    }

    /// What the award measures — shown under the winner on the Player of the Month card.
    var metric: String {
        switch self {
        case .woodenSpoon: "BUYS THE ROUND 🍺"
        case .comebackKid: "BIGGEST CLIMB"
        case .toughestRef: "MOST NO-GOAL CALLS"
        case .firstToScore: "FIRST TO SCORE"
        case .goldenBoot: "MOST GOALS"
        case .playerOfTheMonth: "MOST POINTS"
        }
    }
}

// MARK: - Title race

/// `GET /groups/:id/stats/race`
struct RaceResponse: Codable, Sendable {
    let weeks: [RaceWeek]
    let series: [RaceSeries]
    let me: RaceMe

    private enum CodingKeys: String, CodingKey {
        case weeks, series, me
    }

    init(weeks: [RaceWeek], series: [RaceSeries], me: RaceMe) {
        self.weeks = weeks
        self.series = series
        self.me = me
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        weeks = try container.decodeIfPresent([RaceWeek].self, forKey: .weeks) ?? []
        series = try container.decodeIfPresent([RaceSeries].self, forKey: .series) ?? []
        me = try container.decodeIfPresent(RaceMe.self, forKey: .me) ?? RaceMe(
            bestWeek: RaceBestWeek(number: 0, points: 0),
            avgPerWeek: 0,
            streak: 0
        )
    }
}

struct RaceWeek: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let number: Int
    let startsAt: Date
}

struct RaceSeries: Codable, Identifiable, Sendable {
    let user: User
    /// Cumulative points at the end of each matchweek, aligned with `RaceResponse.weeks`.
    let cumulative: [Int]
    /// The points scored in each matchweek, aligned with `RaceResponse.weeks`.
    let perWeek: [Int]

    var id: String { user.id }
}

struct RaceMe: Codable, Sendable {
    let bestWeek: RaceBestWeek
    let avgPerWeek: Int
    let streak: Int
}

struct RaceBestWeek: Codable, Sendable {
    let number: Int
    let points: Int
}

// MARK: - Full-time receipt

/// `GET /groups/:id/weeks/:weekId/receipt`
struct ReceiptResponse: Codable, Sendable {
    let week: ReceiptWeek
    let club: ReceiptClub
    let player: ReceiptPlayer
    let lines: [ReceiptLine]
    let manOfTheMatch: User?
    let woodenSpoon: User?

    private enum CodingKeys: String, CodingKey {
        case week, club, player, lines, manOfTheMatch, woodenSpoon
    }

    init(
        week: ReceiptWeek,
        club: ReceiptClub,
        player: ReceiptPlayer,
        lines: [ReceiptLine],
        manOfTheMatch: User?,
        woodenSpoon: User?
    ) {
        self.week = week
        self.club = club
        self.player = player
        self.lines = lines
        self.manOfTheMatch = manOfTheMatch
        self.woodenSpoon = woodenSpoon
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        week = try container.decodeIfPresent(ReceiptWeek.self, forKey: .week) ?? ReceiptWeek(
            id: "",
            number: 0,
            startsAt: Date(),
            endsAt: Date()
        )
        club = try container.decodeIfPresent(ReceiptClub.self, forKey: .club) ?? ReceiptClub(
            name: "",
            forfeit: ""
        )
        player = try container.decodeIfPresent(ReceiptPlayer.self, forKey: .player) ?? ReceiptPlayer(
            user: User(id: "", displayName: ""),
            rank: 0,
            rankDelta: 0,
            total: 0
        )
        lines = try container.decodeIfPresent([ReceiptLine].self, forKey: .lines) ?? []
        manOfTheMatch = try container.decodeIfPresent(User.self, forKey: .manOfTheMatch)
        woodenSpoon = try container.decodeIfPresent(User.self, forKey: .woodenSpoon)
    }
}

struct ReceiptWeek: Codable, Sendable {
    let id: String
    let number: Int
    let startsAt: Date
    let endsAt: Date
}

struct ReceiptClub: Codable, Sendable {
    let name: String
    let forfeit: String
}

struct ReceiptPlayer: Codable, Sendable {
    let user: User
    let rank: Int
    let rankDelta: Int
    let total: Int
}

/// One line of the receipt: a fixture, a bonus or a penalty.
struct ReceiptLine: Codable, Identifiable, Sendable {
    let label: String
    let points: Int
    /// A rejected proof is struck through and carries the note "· VAR: NO GOAL".
    let struck: Bool

    var id: String { "\(label)-\(points)-\(struck)" }
}

// MARK: - Awards

/// `GET /groups/:id/awards?month=YYYY-MM`
struct AwardsResponse: Codable, Sendable {
    let month: String
    let awards: [Award]

    private enum CodingKeys: String, CodingKey {
        case month, awards
    }

    init(month: String, awards: [Award]) {
        self.month = month
        self.awards = awards
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        month = try container.decodeIfPresent(String.self, forKey: .month) ?? ""
        awards = try container.decodeIfPresent([Award].self, forKey: .awards) ?? []
    }
}

struct Award: Codable, Identifiable, Sendable {
    let award: AwardKey
    let winners: [User]
    let value: Int
    let nominees: [AwardNominee]
    /// The personal stats of the winner: `goals`, `redCards`, `firstToScore`, `bestWeek`.
    /// The API may leave them out.
    let stats: [String: Int]?

    var id: String { award.rawValue }

    private enum CodingKeys: String, CodingKey {
        case award, winners, value, nominees, stats
    }

    init(
        award: AwardKey,
        winners: [User],
        value: Int,
        nominees: [AwardNominee],
        stats: [String: Int]? = nil
    ) {
        self.award = award
        self.winners = winners
        self.value = value
        self.nominees = nominees
        self.stats = stats
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        award = try container.decode(AwardKey.self, forKey: .award)
        winners = try container.decodeIfPresent([User].self, forKey: .winners) ?? []
        value = try container.decodeIfPresent(Int.self, forKey: .value) ?? 0
        nominees = try container.decodeIfPresent([AwardNominee].self, forKey: .nominees) ?? []
        stats = try container.decodeIfPresent([String: Int].self, forKey: .stats)
    }
}

struct AwardNominee: Codable, Identifiable, Sendable {
    let user: User
    let value: Int

    var id: String { user.id }
}

/// `GET /groups/:id/awards/months`
struct AwardMonthsResponse: Codable, Sendable {
    let months: [String]

    init(months: [String]) {
        self.months = months
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        months = try container.decodeIfPresent([String].self, forKey: .months) ?? []
    }
}

// MARK: - Trophy cabinet

/// `GET /me/trophies`
struct TrophiesResponse: Codable, Sendable {
    let trophies: [Trophy]

    init(trophies: [Trophy]) {
        self.trophies = trophies
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        trophies = try container.decodeIfPresent([Trophy].self, forKey: .trophies) ?? []
    }
}

struct Trophy: Codable, Identifiable, Sendable {
    let groupId: String
    let groupName: String
    /// `YYYY-MM`.
    let month: String
    let award: AwardKey
    let value: Int

    var id: String { "\(groupId)-\(month)-\(award.rawValue)" }
}

// MARK: - Helpers

extension AwardKey {
    /// The date of the first day of a `YYYY-MM` month.
    static func date(for month: String) -> Date? {
        let parts = month.split(separator: "-")
        guard
            parts.count == 2,
            let year = Int(parts[0]),
            let monthNumber = Int(parts[1]),
            (1 ... 12).contains(monthNumber)
        else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = monthNumber
        components.day = 1
        return Calendar(identifier: .gregorian).date(from: components)
    }

    /// "2026-11" → "NOVEMBER".
    static func monthName(for month: String) -> String {
        guard let date = date(for: month) else { return month.uppercased() }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "LLLL"
        return formatter.string(from: date).uppercased()
    }

    /// "2026-11" → "NOV 2026".
    static func shortMonth(for month: String) -> String {
        guard let date = date(for: month) else { return month.uppercased() }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "LLL"
        let parts = month.split(separator: "-")
        return "\(formatter.string(from: date).uppercased()) \(parts.first.map(String.init) ?? "")"
    }
}

/// `GET /groups/:id/weeks` → `{weeks:[Week]}` (closed weeks, newest first).
struct WeeksResponse: Decodable, Sendable {
    let weeks: [Week]
}
