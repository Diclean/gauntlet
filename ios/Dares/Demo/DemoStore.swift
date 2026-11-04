import Foundation

// MARK: - Stored records

/// A row of the `point_events` ledger (SPEC.md, section 1, "Points").
/// Points are never a mutable counter — the leaderboards are sums of these rows.
struct DemoPointEvent: Sendable, Equatable {
    enum Kind: String, Sendable {
        case challenge
        case firstBonus
        case weeklyWinner
        case streak
        /// The captain bonus of a fixture (v3, SPEC.md section 6.6).
        case captain
    }

    let id: String
    let groupID: String
    let weekID: String
    let userID: String
    let kind: Kind
    let points: Int
    let challengeID: String?
    let submissionID: String?
    let createdAt: Date
}

/// A vote. Votes keep the order they were cast in so that "whichever threshold is hit
/// first wins" can be replayed exactly.
struct DemoVote: Sendable {
    let voterID: String
    var approve: Bool
    let createdAt: Date
}

/// A stored comment of the banter (v3, SPEC.md section 6.5).
struct DemoComment: Sendable, Equatable {
    let id: String
    let submissionID: String
    let userID: String
    let text: String
    let createdAt: Date
}

/// A stored report (v3, SPEC.md section 6.2).
struct DemoReport: Sendable, Equatable {
    enum TargetType: String, Sendable {
        case submission
        case comment
    }

    let reporterID: String
    let targetType: TargetType
    let targetID: String
    let groupID: String
    let reason: ReportReason
    let note: String?
    let createdAt: Date
}

/// A stored submission of a fixture.
struct DemoSubmission: Sendable {
    let id: String
    let groupID: String
    let weekID: String
    let challengeID: String
    let challengeTitle: String
    let userID: String
    var mediaKey: String
    var mediaType: MediaType
    var caption: String?
    var status: SubmissionStatus
    var eligibleVoters: Int
    let createdAt: Date
    var decidedAt: Date?
}

/// A stored fixture. The view dependent fields (`myStatus`, `acceptedCount`) are computed
/// per viewer, so they are not part of the stored record.
struct DemoChallenge: Sendable {
    let id: String
    let title: String
    let description: String
    let difficulty: Difficulty
    let points: Int
    let position: Int
    /// True when a member of the club wrote this fixture (v3, SPEC.md section 6.7).
    let isHouse: Bool
    /// The member that wrote the fixture — `nil` for the fixtures of the AI.
    let createdBy: String?
    /// When the fixture was written. A fixture that is younger than a day is "new".
    var createdAt: Date
    /// True when the fixture was vetoed out of the matchweek.
    var vetoed: Bool
}

/// One line of a receipt.
struct DemoReceiptLine: Sendable, Equatable {
    let label: String
    let points: Int
    let struck: Bool
}

/// The seeded result of a member in a matchweek.
struct DemoWeekResult: Sendable {
    let points: Int
    let acceptedCount: Int
    let lines: [DemoReceiptLine]
}

/// A vote that the demo plays by itself, so the accept flow can be seen.
struct DemoSimulatedVote: Sendable {
    let voterID: String
    let approve: Bool
}

struct DemoSimulation: Sendable {
    let id: String
    let submissionID: String
    let votes: [DemoSimulatedVote]
    let delay: TimeInterval
}

// MARK: - Store

/// The in-memory world of the demo: users, clubs, matchweeks, fixtures, submissions,
/// votes and the point ledger. It is a plain value type so it can be seeded without
/// touching the actor that owns it.
struct DemoStore: Sendable {
    var users: [String: User] = [:]
    var groups: [String: Group] = [:]
    var memberIDs: [String: [String]] = [:]
    var joinDates: [String: Date] = [:]
    /// Matchweeks per club, oldest first. The last one is the current matchweek.
    var weeks: [String: [Week]] = [:]
    /// Fixtures per matchweek, keyed by `"\(groupID)|\(weekID)"`.
    var challenges: [String: [DemoChallenge]] = [:]
    var submissions: [String: DemoSubmission] = [:]
    var submissionOrder: [String] = []
    /// Votes per submission, in the order they were cast.
    var votes: [String: [DemoVote]] = [:]
    /// The point ledger per club.
    var events: [String: [DemoPointEvent]] = [:]
    /// `"groupID|userID"` → matchweek IDs in which the member had an accepted proof.
    var acceptanceWeeks: [String: Set<String>] = [:]
    /// The seeded result of a member in a matchweek, keyed by `"groupID|weekID"`.
    var weekResults: [String: [String: DemoWeekResult]] = [:]
    /// Proofs uploaded during the demo, keyed by their media key.
    var uploads: [String: Data] = [:]
    /// Votes the demo plays by itself.
    var pendingSimulations: [DemoSimulation] = []

    // MARK: v3 — safety, banter, captain, house fixture

    /// The reactions of every proof: `submissionID` → emoji → the members that used it.
    var reactions: [String: [ReactionEmoji: Set<String>]] = [:]
    /// The comments of every proof, oldest first.
    var comments: [String: [DemoComment]] = [:]
    /// The reports of the club.
    var reports: [DemoReport] = []
    /// The blocks: the blocker → the members it blocked.
    var blocks: [String: Set<String>] = [:]
    /// The members the owner removed: club → member → the day of the ban.
    var bans: [String: [String: Date]] = [:]
    /// The vetoes of every fixture: `challengeID` → the members that vetoed it.
    var vetoes: [String: Set<String>] = [:]
    /// The fixtures that were replaced in a matchweek: club + week → the count.
    var replacements: [String: Int] = [:]
    /// The captain fixture of every member: `weekID|userID` → the fixture.
    var captains: [String: String] = [:]
    /// The push switches of every member.
    var notificationPrefs: [String: NotificationPrefs] = [:]

    var currentUserID: String = DemoSeed.currentUserID
    /// The month of the awards ceremony that is live.
    var awardMonth: String = ""

    private var eventCounter = 0
    private var submissionCounter = 0
    private var inviteCounter = 0
    private var commentCounter = 0

    // MARK: - Calendar helpers

    /// Monday 00:00 of the week that contains `date` (SPEC.md, section 1, "Week").
    static func mondayStart(_ date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        calendar.firstWeekday = 2 // Monday
        return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }

    static func makeWeek(groupID: String, number: Int, start: Date, status: WeekStatus) -> Week {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        return Week(
            id: "demo-week-\(groupID)-\(number)-\(Int(start.timeIntervalSince1970))",
            number: number,
            startsAt: start,
            endsAt: weekEnd.addingTimeInterval(-1),
            voteDeadline: weekEnd.addingTimeInterval(12 * 3_600),
            status: status
        )
    }

    static func points(for difficulty: Difficulty) -> Int {
        switch difficulty {
        case .easy: 10
        case .medium: 25
        case .hard: 50
        }
    }

    // MARK: - Seeding

    mutating func seed(now: Date, simulationDelay: TimeInterval = 45) {
        for user in DemoSeed.users {
            users[user.id] = user
        }
        for group in DemoSeed.groups {
            groups[group.id] = group
        }
        for (groupID, members) in DemoSeed.membership {
            memberIDs[groupID] = members
            for (index, userID) in members.enumerated() {
                joinDates["\(groupID)|\(userID)"] = now.addingTimeInterval(-Double(24 - index * 5) * 3_600 * 12)
            }
        }

        awardMonth = DemoSeed.awardMonths(now: now).first ?? ""

        let weekStart = Self.mondayStart(now)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current

        for group in DemoSeed.groups {
            let isMainClub = group.id == DemoSeed.sundayLeagueID
            let total = isMainClub ? DemoSeed.matchweekCount : 4
            var list: [Week] = []
            for index in stride(from: total - 1, through: 1, by: -1) {
                let start = calendar.date(byAdding: .day, value: -7 * index, to: weekStart) ?? weekStart
                let week = Self.makeWeek(groupID: group.id, number: total - index, start: start, status: .closed)
                list.append(week)
                challenges["\(group.id)|\(week.id)"] = makeChallenges(
                    weekID: week.id,
                    groupID: group.id,
                    count: group.challengesPerWeek,
                    offset: total - index,
                    isCurrentWeek: false,
                    createdAt: week.startsAt
                )
            }
            let current = Self.makeWeek(groupID: group.id, number: total, start: weekStart, status: .open)
            list.append(current)
            challenges["\(group.id)|\(current.id)"] = makeChallenges(
                weekID: current.id,
                groupID: group.id,
                count: group.challengesPerWeek,
                offset: 0,
                isCurrentWeek: isMainClub,
                createdAt: current.startsAt
            )
            weeks[group.id] = list
        }

        seedHistory()
        seedCurrentWeek(now: now, simulationDelay: simulationDelay)
        seedV3Features(now: now)
    }

    // MARK: - Seeded v3 features

    /// The v3 features of the demo: a fixture that was replaced, a fixture that waits
    /// for the vetoes, a captain pick, the house fixture of another club, some banter,
    /// a member the owner removed and a member the player blocked.
    private mutating func seedV3Features(now: Date) {
        let groupID = DemoSeed.sundayLeagueID
        guard let week = weeks[groupID]?.last else { return }
        let list = challengeList(groupID: groupID, weekID: week.id)

        // 04 was replaced three hours ago — it wears the NEW pill.
        if list.indices.contains(3) {
            challenges["\(groupID)|\(week.id)"]?[3].createdAt = now.addingTimeInterval(-3 * 3_600)
        }
        // One replacement of the two of this matchweek is used.
        replacements["\(groupID)|\(week.id)"] = 1

        // 05 waits for the vetoes: one of three.
        if list.indices.contains(4) {
            vetoes[list[4].id] = ["demo-user-jo"]
        }

        // Alex wears the armband on 03 — and the armband is locked, because he played it.
        if list.indices.contains(2) {
            captains["\(week.id)|\(DemoSeed.currentUserID)"] = list[2].id
        }

        // The house fixture of another club, written by its owner.
        seedHouseFixture(now: now)

        // The banter of the matchweek.
        seedBanter(now: now)

        // The owner removed Tom from the club, Alex blocked Nina.
        bans[groupID] = ["demo-user-tom": now.addingTimeInterval(-3 * 86_400)]
        blocks[DemoSeed.currentUserID] = ["demo-user-nina"]

        // The push switches of Alex: the Sunday reminder is off.
        notificationPrefs[DemoSeed.currentUserID] = NotificationPrefs(deadline: false)
    }

    /// The house fixture of the bank holiday club — written by its owner.
    private mutating func seedHouseFixture(now: Date) {
        let groupID = DemoSeed.bankHolidayID
        guard let week = weeks[groupID]?.last else { return }
        var list = challengeList(groupID: groupID, weekID: week.id)
        let house = DemoChallenge(
            id: "demo-challenge-house-\(week.id)",
            title: DemoSeed.houseFixture.title,
            description: DemoSeed.houseFixture.description,
            difficulty: DemoSeed.houseFixture.difficulty,
            points: Self.points(for: DemoSeed.houseFixture.difficulty),
            position: (list.map(\.position).max() ?? 0) + 1,
            isHouse: true,
            createdBy: "demo-user-sam",
            createdAt: now.addingTimeInterval(-3 * 86_400),
            vetoed: false
        )
        list.append(house)
        challenges["\(groupID)|\(week.id)"] = list
    }

    /// Some reactions and some comments on the proofs of the matchweek.
    private mutating func seedBanter(now: Date) {
        let groupID = DemoSeed.sundayLeagueID
        guard let week = weeks[groupID]?.last else { return }
        let list = challengeList(groupID: groupID, weekID: week.id)
        let fixtureID: (Int) -> String? = { position in
            list.first { $0.position == position }?.id
        }
        let proofs = submissionList(groupID: groupID)

        if let sunrise = fixtureID(1),
           let proof = proofs.first(where: { $0.challengeID == sunrise && $0.userID == DemoSeed.currentUserID })
        {
            reactions[proof.id] = [
                .fire: ["demo-user-lee", "demo-user-jo", "demo-user-sam"],
                .joy: ["demo-user-mika"],
            ]
            comments[proof.id] = [
                DemoComment(
                    id: "demo-comment-seed-1",
                    submissionID: proof.id,
                    userID: "demo-user-jo",
                    text: "5am and still smiling. Captain behaviour.",
                    createdAt: now.addingTimeInterval(-5 * 3_600)
                ),
                DemoComment(
                    id: "demo-comment-seed-2",
                    submissionID: proof.id,
                    userID: "demo-user-sam",
                    text: "The light though. Where is this?!",
                    createdAt: now.addingTimeInterval(-4 * 3_600)
                ),
            ]
        }

        if let panenka = fixtureID(3),
           let proof = proofs.first(where: { $0.challengeID == panenka && $0.userID == DemoSeed.currentUserID })
        {
            reactions[proof.id] = [
                .clap: ["demo-user-lee", "demo-user-jo"],
                .wow: ["demo-user-mika"],
            ]
            comments[proof.id] = [
                DemoComment(
                    id: "demo-comment-seed-3",
                    submissionID: proof.id,
                    userID: "demo-user-lee",
                    text: "Scored it on the second try. Absolute scenes.",
                    createdAt: now.addingTimeInterval(-3 * 3_600)
                ),
            ]
        }
    }

    private mutating func makeChallenges(
        weekID: String,
        groupID: String,
        count: Int,
        offset: Int,
        isCurrentWeek: Bool,
        createdAt: Date = Date()
    ) -> [DemoChallenge] {
        let pool = DemoSeed.fixturePool
        return (0 ..< count).map { index in
            let fixture: (title: String, difficulty: Difficulty)
            if isCurrentWeek, index < DemoSeed.currentFixtures.count {
                fixture = DemoSeed.currentFixtures[index]
            } else {
                let entry = pool[(offset + index) % pool.count]
                fixture = (entry.title, entry.difficulty)
            }
            return DemoChallenge(
                id: "demo-challenge-\(weekID)-\(index)",
                title: fixture.title,
                description: DemoSeed.description(for: fixture.title, difficulty: fixture.difficulty),
                difficulty: fixture.difficulty,
                points: Self.points(for: fixture.difficulty),
                position: index + 1,
                isHouse: false,
                createdBy: nil,
                createdAt: createdAt,
                vetoed: false
            )
        }
    }

    // MARK: - Seeded history

    /// The closed matchweeks of the demo club: the points of every member are seeded
    /// so that the table, the race and the receipts tell one coherent story.
    private mutating func seedHistory() {
        let groupID = DemoSeed.sundayLeagueID
        guard let list = weeks[groupID] else { return }
        let closed = list.filter { $0.status == .closed }

        for (index, week) in closed.enumerated() {
            let fixtures = challenges["\(groupID)|\(week.id)"] ?? []
            var results: [String: DemoWeekResult] = [:]
            for (userID, points) in DemoSeed.season {
                guard points[index] > 0 else { continue }
                let lines = Self.makeReceiptLines(
                    points: points[index],
                    fixtures: fixtures,
                    seed: index + userID.count
                )
                let accepted = lines.filter { !$0.struck && !Self.isBonus($0.label) }.count
                results[userID] = DemoWeekResult(
                    points: points[index],
                    acceptedCount: max(1, accepted),
                    lines: lines
                )
                acceptanceWeeks["\(groupID)|\(userID)", default: []].insert(week.id)
                addEvent(
                    groupID: groupID,
                    weekID: week.id,
                    userID: userID,
                    kind: .challenge,
                    points: points[index],
                    at: week.endsAt
                )
            }
            weekResults["\(groupID)|\(week.id)"] = results
        }
    }

    /// Splits the points of a matchweek into the lines of a receipt.
    static func makeReceiptLines(
        points: Int,
        fixtures: [DemoChallenge],
        seed: Int
    ) -> [DemoReceiptLine] {
        guard points > 0 else { return [] }
        var remaining = points
        var lines: [DemoReceiptLine] = []
        var index = seed
        let values = [50, 25, 10]
        while remaining > 0 {
            var placed = false
            for value in values where remaining >= value {
                remaining -= value
                let fixture = fixtures.isEmpty ? nil : fixtures[index % fixtures.count]
                let title = (fixture?.title ?? "Fixture").uppercased()
                let position = fixture.map { String(format: "%02d", $0.position) } ?? "00"
                lines.append(DemoReceiptLine(label: "\(position) \(title)", points: value, struck: false))
                index += 1
                placed = true
                break
            }
            if !placed {
                // The rest is a streak bonus: five points per week on the run.
                let weeks = max(1, remaining / 5)
                lines.append(
                    DemoReceiptLine(
                        label: "STREAK 🔥 \(weeks) WKS",
                        points: weeks * 5,
                        struck: false
                    )
                )
                remaining = 0
            }
        }
        return lines
    }

    static func isBonus(_ label: String) -> Bool {
        label.hasPrefix("FIRST TO SCORE") || label.hasPrefix("STREAK") || label.hasPrefix("MAN OF THE MATCH")
            || label.hasPrefix("CAPTAIN")
    }

    // MARK: - Seeded current matchweek

    private mutating func seedCurrentWeek(now: Date, simulationDelay: TimeInterval) {
        let groupID = DemoSeed.sundayLeagueID
        guard let week = weeks[groupID]?.last else { return }
        guard let list = challenges["\(groupID)|\(week.id)"] else { return }

        func fixture(_ index: Int) -> DemoChallenge? {
            list.indices.contains(index) ? list[index] : nil
        }

        // 01 · Sunrise on a hill — accepted, and the first to score it.
        if let first = fixture(0) {
            seedSubmission(
                groupID: groupID,
                week: week,
                challenge: first,
                userID: DemoSeed.currentUserID,
                mediaKey: DemoMedia.photoKey(1),
                caption: "5am alarm. Worth it.",
                age: 6 * 3_600,
                approvals: ["demo-user-lee", "demo-user-jo"],
                rejections: [],
                now: now
            )
            seedSubmission(
                groupID: groupID,
                week: week,
                challenge: first,
                userID: "demo-user-sam",
                mediaKey: DemoMedia.photoKey(1),
                caption: "Same hill, better light.",
                age: 2 * 3_600,
                approvals: ["demo-user-jo", "demo-user-mika"],
                rejections: [],
                now: now
            )
        }

        // 02 · Cook a stranger's recipe — Jo was first, Alex followed, Lee waits in the VAR.
        if let second = fixture(1) {
            seedSubmission(
                groupID: groupID,
                week: week,
                challenge: second,
                userID: "demo-user-jo",
                mediaKey: DemoMedia.photoKey(3),
                caption: "Phone stayed in the drawer.",
                age: 5 * 3_600,
                approvals: ["demo-user-lee", "demo-user-sam"],
                rejections: [],
                now: now
            )
            seedSubmission(
                groupID: groupID,
                week: week,
                challenge: second,
                userID: DemoSeed.currentUserID,
                mediaKey: DemoMedia.photoKey(2),
                caption: "A Korean dish I have never made before.",
                age: 4 * 3_600,
                approvals: ["demo-user-lee", "demo-user-jo"],
                rejections: [],
                now: now
            )
            seedSubmission(
                groupID: groupID,
                week: week,
                challenge: second,
                userID: "demo-user-lee",
                mediaKey: DemoMedia.photoKey(2),
                caption: "My grandmother's recipe. Send help.",
                age: 9 * 3_600,
                approvals: ["demo-user-jo"],
                rejections: [],
                now: now
            )
        }

        // 03 · Score a Panenka — Lee was first, Alex followed.
        if let third = fixture(2) {
            seedSubmission(
                groupID: groupID,
                week: week,
                challenge: third,
                userID: "demo-user-lee",
                mediaKey: DemoMedia.videoKey,
                mediaType: .video,
                caption: "Three hours. Zero notifications.",
                age: 8 * 3_600,
                approvals: ["demo-user-jo", "demo-user-sam"],
                rejections: [],
                now: now
            )
            seedSubmission(
                groupID: groupID,
                week: week,
                challenge: third,
                userID: DemoSeed.currentUserID,
                mediaKey: DemoMedia.photoKey(4),
                caption: "Scored it on the second try.",
                age: 3 * 3_600,
                approvals: ["demo-user-lee", "demo-user-jo"],
                rejections: [],
                now: now
            )
            seedSubmission(
                groupID: groupID,
                week: week,
                challenge: third,
                userID: "demo-user-jo",
                mediaKey: DemoMedia.photoKey(5),
                caption: "Wrote it by hand and posted it.",
                age: 2 * 3_600,
                approvals: ["demo-user-mika"],
                rejections: [],
                now: now
            )
            seedSubmission(
                groupID: groupID,
                week: week,
                challenge: third,
                userID: "demo-user-sam",
                mediaKey: DemoMedia.videoKey,
                mediaType: .video,
                caption: "Three hours of training. Zero notifications.",
                age: 8 * 3_600,
                approvals: [],
                rejections: [],
                now: now
            )
        }

        // 04 · Sunset swim — the red card.
        if let fourth = fixture(3) {
            seedSubmission(
                groupID: groupID,
                week: week,
                challenge: fourth,
                userID: DemoSeed.currentUserID,
                mediaKey: DemoMedia.photoKey(4),
                caption: "Cold water, loud music, no regrets.",
                age: 9 * 3_600,
                approvals: [],
                rejections: ["demo-user-jo", "demo-user-mika"],
                now: now
            )
            seedSubmission(
                groupID: groupID,
                week: week,
                challenge: fourth,
                userID: "demo-user-sam",
                mediaKey: DemoMedia.photoKey(6),
                caption: "Sunset swim, cold sea.",
                age: 3 * 3_600,
                approvals: [],
                rejections: [],
                now: now
            )
        }

        // 05 · Ref a kids' match — my proof is in the VAR, the club votes in a moment.
        if let fifth = fixture(4) {
            let mine = seedSubmission(
                groupID: groupID,
                week: week,
                challenge: fifth,
                userID: DemoSeed.currentUserID,
                mediaKey: DemoMedia.photoKey(6),
                caption: "Full time, all out. They loved it.",
                age: 20 * 60,
                approvals: [],
                rejections: [],
                now: now
            )
            // The demo plays the other members: my proof is accepted a little later.
            pendingSimulations.append(
                DemoSimulation(
                    id: "demo-simulation-1",
                    submissionID: mine.id,
                    votes: [
                        DemoSimulatedVote(voterID: "demo-user-jo", approve: true),
                        DemoSimulatedVote(voterID: "demo-user-lee", approve: true),
                    ],
                    delay: simulationDelay
                )
            )
        }

        // Mika stayed at home.
        if let first = fixture(0) {
            seedSubmission(
                groupID: groupID,
                week: week,
                challenge: first,
                userID: "demo-user-mika",
                mediaKey: DemoMedia.photoKey(3),
                caption: "Rain. I stayed in.",
                age: 4 * 3_600,
                approvals: [],
                rejections: ["demo-user-lee"],
                now: now
            )
        }

        seedStreakBonus(groupID: groupID, week: week)
    }

    /// The streak bonus of the current matchweek is paid when it closes. The demo
    /// shows it right away so that the table and the receipt are complete.
    private mutating func seedStreakBonus(groupID: String, week: Week) {
        for userID in memberIDs[groupID] ?? [] {
            let streak = streak(userID: userID, groupID: groupID, upTo: week)
            guard streak >= 2 else { continue }
            addEvent(
                groupID: groupID,
                weekID: week.id,
                userID: userID,
                kind: .streak,
                points: 5 * min(streak, 10),
                at: week.startsAt
            )
        }
    }

    @discardableResult
    private mutating func seedSubmission(
        groupID: String,
        week: Week,
        challenge: DemoChallenge,
        userID: String,
        mediaKey: String,
        mediaType: MediaType = .photo,
        caption: String?,
        age: TimeInterval,
        approvals: [String],
        rejections: [String],
        now: Date
    ) -> DemoSubmission {
        let submission = makeSubmission(
            groupID: groupID,
            weekID: week.id,
            challenge: challenge,
            userID: userID,
            mediaKey: mediaKey,
            mediaType: mediaType,
            caption: caption,
            at: now.addingTimeInterval(-age)
        )
        for (index, voterID) in approvals.enumerated() {
            castVote(
                submissionID: submission.id,
                voterID: voterID,
                approve: true,
                at: now.addingTimeInterval(-age + Double(index + 1) * 600)
            )
        }
        for (index, voterID) in rejections.enumerated() {
            castVote(
                submissionID: submission.id,
                voterID: voterID,
                approve: false,
                at: now.addingTimeInterval(-age + Double(index + 1) * 900)
            )
        }
        return submission
    }

    // MARK: - Clubs

    func group(id: String) -> Group? {
        guard let stored = groups[id] else { return nil }
        return Group(
            id: stored.id,
            name: stored.name,
            inviteCode: stored.inviteCode,
            challengesPerWeek: stored.challengesPerWeek,
            theme: stored.theme,
            language: stored.language,
            timezone: stored.timezone,
            ownerId: stored.ownerId,
            memberCount: memberIDs[id]?.count ?? 0,
            forfeit: stored.forfeit,
            inviteUrl: stored.inviteUrl ?? "\(DemoSeed.inviteHost)/join/\(stored.inviteCode)"
        )
    }

    func groups(for userID: String) -> [Group] {
        groups.keys
            .filter { memberIDs[$0]?.contains(userID) == true }
            .compactMap { group(id: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func members(of groupID: String) -> [Member] {
        (memberIDs[groupID] ?? []).compactMap { userID in
            guard let user = users[userID] else { return nil }
            return Member(user: user, joinedAt: joinDates["\(groupID)|\(userID)"] ?? Date())
        }
    }

    mutating func createGroup(
        name: String,
        challengesPerWeek: Int,
        theme: String?,
        language: String,
        timezone: String,
        ownerID: String
    ) throws -> Group {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw APIError.server(code: "invalid_name", message: "The club needs a name.", status: 400)
        }
        let count = min(max(challengesPerWeek, 3), 10)
        inviteCounter += 1
        let id = "demo-group-\(inviteCounter)-\(UUID().uuidString.prefix(6).lowercased())"
        let group = Group(
            id: id,
            name: trimmed,
            inviteCode: Self.makeInviteCode(seed: inviteCounter),
            challengesPerWeek: count,
            theme: theme,
            language: language,
            timezone: timezone,
            ownerId: ownerID,
            memberCount: 1,
            inviteUrl: "\(DemoSeed.inviteHost)/join/\(Self.makeInviteCode(seed: inviteCounter))"
        )
        groups[id] = group
        memberIDs[id] = [ownerID]
        joinDates["\(id)|\(ownerID)"] = Date()

        let week = Self.makeWeek(groupID: id, number: 1, start: Self.mondayStart(Date()), status: .open)
        weeks[id] = [week]
        challenges["\(id)|\(week.id)"] = makeChallenges(
            weekID: week.id,
            groupID: id,
            count: count,
            offset: inviteCounter * 3,
            isCurrentWeek: false,
            createdAt: week.startsAt
        )
        return group
    }

    mutating func joinGroup(inviteCode: String, userID: String) throws -> Group {
        let code = inviteCode.uppercased()
        guard let id = groups.values.first(where: { $0.inviteCode.uppercased() == code })?.id else {
            throw APIError.server(
                code: "invalid_code",
                message: "That invite code does not match any club.",
                status: 404
            )
        }
        guard memberIDs[id]?.contains(userID) != true else {
            throw APIError.server(
                code: "already_member",
                message: "You are already in this club.",
                status: 409
            )
        }
        if bans[id]?[userID] != nil {
            throw APIError.server(
                code: "banned",
                message: "You were removed from this club.",
                status: 403
            )
        }
        memberIDs[id, default: []].append(userID)
        joinDates["\(id)|\(userID)"] = Date()
        if weeks[id]?.last?.status != .open {
            let week = Self.makeWeek(groupID: id, number: 1, start: Self.mondayStart(Date()), status: .open)
            weeks[id, default: []].append(week)
            challenges["\(id)|\(week.id)"] = makeChallenges(
                weekID: week.id,
                groupID: id,
                count: groups[id]?.challengesPerWeek ?? 5,
                offset: 1,
                isCurrentWeek: false,
                createdAt: week.startsAt
            )
        }
        guard let joined = group(id: id) else {
            throw APIError.server(code: "not_found", message: "That club does not exist.", status: 404)
        }
        return joined
    }

    mutating func leaveGroup(id: String, userID: String) {
        memberIDs[id]?.removeAll { $0 == userID }
    }

    mutating func updateGroup(
        id: String,
        request: UpdateGroupRequest,
        userID: String
    ) throws -> Group {
        guard let stored = groups[id] else {
            throw APIError.server(code: "not_found", message: "That club does not exist.", status: 404)
        }
        guard stored.ownerId == userID else {
            throw APIError.server(
                code: "forbidden",
                message: "Only the club owner can change these settings.",
                status: 403
            )
        }
        let forfeit = request.forfeit?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? stored.forfeit
        let updated = Group(
            id: stored.id,
            name: request.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? stored.name,
            inviteCode: stored.inviteCode,
            challengesPerWeek: request.challengesPerWeek.map { min(max($0, 3), 10) } ?? stored.challengesPerWeek,
            theme: request.theme ?? stored.theme,
            language: request.language ?? stored.language,
            timezone: request.timezone ?? stored.timezone,
            ownerId: stored.ownerId,
            memberCount: memberIDs[id]?.count ?? 0,
            forfeit: forfeit
        )
        groups[id] = updated
        return group(id: id) ?? updated
    }

    private static func makeInviteCode(seed: Int) -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var value = UInt64(seed &* 2_654_435_761 &+ 12_345)
        var code = ""
        for _ in 0 ..< 6 {
            value = value &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let index = Int((value >> 33) % UInt64(alphabet.count))
            code.append(alphabet[index])
        }
        return code
    }

    // MARK: - Matchweeks and fixtures

    func week(of groupID: String) -> Week? {
        weeks[groupID]?.last
    }

    func matchweek(groupID: String, number: Int) -> Week? {
        weeks[groupID]?.first { $0.number == number }
    }

    func challengeList(groupID: String, weekID: String) -> [DemoChallenge] {
        challenges["\(groupID)|\(weekID)"] ?? []
    }

    func challengeInfo(id: String) -> (groupID: String, weekID: String, challenge: DemoChallenge)? {
        for (key, list) in challenges {
            guard let challenge = list.first(where: { $0.id == id }) else { continue }
            let parts = key.split(separator: "|", maxSplits: 1)
            guard parts.count == 2 else { continue }
            return (String(parts[0]), String(parts[1]), challenge)
        }
        return nil
    }

    /// The fixtures of the current matchweek with the view dependent fields filled in.
    func challenges(groupID: String, viewerID: String) -> [Challenge] {
        guard let week = week(of: groupID) else { return [] }
        return challengeList(groupID: groupID, weekID: week.id)
            .filter { !$0.vetoed }
            .map { challenge in
                makeChallenge(challenge, groupID: groupID, weekID: week.id, viewerID: viewerID)
            }
    }

    /// One fixture with the view dependent fields filled in.
    func makeChallenge(
        _ challenge: DemoChallenge,
        groupID: String,
        weekID: String,
        viewerID: String
    ) -> Challenge {
        let log = vetoes[challenge.id] ?? []
        return Challenge(
            id: challenge.id,
            title: challenge.title,
            description: challenge.description,
            difficulty: challenge.difficulty,
            points: challenge.points,
            position: challenge.position,
            myStatus: myStatus(groupID: groupID, challengeID: challenge.id, viewerID: viewerID),
            acceptedCount: acceptedCount(groupID: groupID, challengeID: challenge.id),
            vetoCount: log.count,
            vetoThreshold: vetoThreshold(groupID: groupID),
            myVeto: log.contains(viewerID),
            isNew: challenge.createdAt > Date().addingTimeInterval(-24 * 3_600),
            isHouse: challenge.isHouse,
            createdBy: challenge.createdBy.flatMap { users[$0] },
            isCaptain: captains["\(weekID)|\(viewerID)"] == challenge.id
        )
    }

    /// The matchweek as the API shows it: with the captain fixture of the player.
    func apiWeek(groupID: String, viewerID: String) -> Week? {
        guard let week = week(of: groupID) else { return nil }
        return Week(
            id: week.id,
            number: week.number,
            startsAt: week.startsAt,
            endsAt: week.endsAt,
            voteDeadline: week.voteDeadline,
            status: week.status,
            myCaptainChallengeId: captains["\(week.id)|\(viewerID)"],
            vetoesUsed: replacements["\(groupID)|\(week.id)"] ?? 0
        )
    }

    func myStatus(groupID: String, challengeID: String, viewerID: String) -> MyChallengeStatus {
        let mine = submissions.values
            .filter { $0.groupID == groupID && $0.challengeID == challengeID && $0.userID == viewerID }
            .sorted { $0.createdAt > $1.createdAt }
        if mine.contains(where: { $0.status == .accepted }) { return .accepted }
        if mine.contains(where: { $0.status == .pending }) { return .pending }
        if mine.contains(where: { $0.status == .rejected }) { return .rejected }
        return .todo
    }

    func acceptedCount(groupID: String, challengeID: String) -> Int {
        submissions.values.filter {
            $0.groupID == groupID && $0.challengeID == challengeID && $0.status == .accepted
        }.count
    }

    // MARK: - Submissions

    func submissionList(groupID: String) -> [DemoSubmission] {
        submissionOrder.compactMap { submissions[$0] }.filter { $0.groupID == groupID }
    }

    mutating func makeSubmission(
        groupID: String,
        weekID: String,
        challenge: DemoChallenge,
        userID: String,
        mediaKey: String,
        mediaType: MediaType,
        caption: String?,
        at date: Date
    ) -> DemoSubmission {
        submissionCounter += 1
        let eligible = max(0, (memberIDs[groupID]?.count ?? 1) - 1)
        let submission = DemoSubmission(
            id: "demo-submission-\(submissionCounter)",
            groupID: groupID,
            weekID: weekID,
            challengeID: challenge.id,
            challengeTitle: challenge.title,
            userID: userID,
            mediaKey: mediaKey,
            mediaType: mediaType,
            caption: caption,
            status: .pending,
            eligibleVoters: eligible,
            createdAt: date,
            decidedAt: nil
        )
        submissions[submission.id] = submission
        submissionOrder.append(submission.id)
        return submission
    }

    /// Creates a submission for the current user, following the "one active submission per
    /// (user, challenge)" rule of the spec.
    mutating func createSubmission(
        challengeID: String,
        mediaType: MediaType,
        caption: String?,
        mediaKey: String
    ) throws -> DemoSubmission {
        guard let info = challengeInfo(id: challengeID) else {
            throw APIError.server(
                code: "challenge_not_found",
                message: "That fixture does not exist.",
                status: 404
            )
        }
        guard let week = week(of: info.groupID), week.status == .open else {
            throw APIError.server(
                code: "week_closed",
                message: "This matchweek is closed, no more proofs.",
                status: 409
            )
        }
        let mine = submissions.values.filter {
            $0.groupID == info.groupID && $0.challengeID == challengeID && $0.userID == currentUserID
        }
        if mine.contains(where: { $0.status == .accepted }) {
            throw APIError.server(
                code: "already_accepted",
                message: "That fixture is already done.",
                status: 409
            )
        }
        if mine.contains(where: { $0.status == .pending }) {
            throw APIError.server(
                code: "already_pending",
                message: "You already sent a proof for this fixture.",
                status: 409
            )
        }
        return makeSubmission(
            groupID: info.groupID,
            weekID: week.id,
            challenge: info.challenge,
            userID: currentUserID,
            mediaKey: mediaKey,
            mediaType: mediaType,
            caption: caption,
            at: Date()
        )
    }

    func submission(id: String) -> DemoSubmission? {
        submissions[id]
    }

    /// The API view of a submission for a given viewer.
    func makeSubmission(_ submission: DemoSubmission, viewerID: String) -> Submission {
        let log = votes[submission.id] ?? []
        let approvals = log.filter(\.approve).count
        let rejections = log.count - approvals
        let user = users[submission.userID] ?? User(id: submission.userID, displayName: "Unknown", avatarEmoji: nil)
        let voters = log.compactMap { record in users[record.voterID] }
        return Submission(
            id: submission.id,
            challengeId: submission.challengeID,
            challengeTitle: submission.challengeTitle,
            user: user,
            mediaUrl: submission.mediaKey,
            mediaType: submission.mediaType,
            caption: submission.caption,
            status: submission.status,
            approvals: approvals,
            rejections: rejections,
            eligibleVoters: submission.eligibleVoters,
            myVote: log.first(where: { $0.voterID == viewerID })?.approve,
            createdAt: submission.createdAt,
            decidedAt: submission.decidedAt,
            voters: voters,
            reactions: reactionList(submissionID: submission.id, viewerID: viewerID),
            commentCount: commentList(
                submissionID: submission.id,
                viewerID: viewerID,
                groupID: submission.groupID
            ).count
        )
    }

    /// Pending submissions of others that the viewer has not voted on, oldest first.
    func pendingVotes(groupID: String, viewerID: String) -> [Submission] {
        submissionList(groupID: groupID)
            .filter { submission in
                submission.status == .pending
                    && submission.userID != viewerID
                    && !isBlocked(by: viewerID, user: submission.userID)
                    && !isReported(targetType: .submission, targetID: submission.id, by: viewerID)
                    && !(votes[submission.id] ?? []).contains { $0.voterID == viewerID }
            }
            .sorted { $0.createdAt < $1.createdAt }
            .map { makeSubmission($0, viewerID: viewerID) }
    }

    /// The group feed, newest first, 20 items per page.
    func feed(groupID: String, cursor: String?, viewerID: String) -> (items: [Submission], nextCursor: String?) {
        let all = submissionList(groupID: groupID)
            .filter { submission in
                !isBlocked(by: viewerID, user: submission.userID)
                    && !isReported(targetType: .submission, targetID: submission.id, by: viewerID)
            }
            .sorted { $0.createdAt > $1.createdAt }
            .map { makeSubmission($0, viewerID: viewerID) }
        let offset = max(0, Int(cursor ?? "0") ?? 0)
        guard offset < all.count else { return ([], nil) }
        let end = min(offset + 20, all.count)
        let page = Array(all[offset ..< end])
        let next = end < all.count ? String(end) : nil
        return (page, next)
    }

    // MARK: - Voting

    mutating func castVote(submissionID: String, voterID: String, approve: Bool, at date: Date) {
        var log = votes[submissionID] ?? []
        if let index = log.firstIndex(where: { $0.voterID == voterID }) {
            log[index].approve = approve
        } else {
            log.append(DemoVote(voterID: voterID, approve: approve, createdAt: date))
        }
        votes[submissionID] = log
        evaluate(submissionID: submissionID)
    }

    /// Applies a vote of the current user and returns the decided submission.
    mutating func vote(submissionID: String, approve: Bool) throws -> DemoSubmission {
        guard let submission = submissions[submissionID] else {
            throw APIError.server(
                code: "not_found",
                message: "That proof does not exist.",
                status: 404
            )
        }
        guard submission.userID != currentUserID else {
            throw APIError.server(
                code: "own_submission",
                message: "You cannot vote on your own proof.",
                status: 403
            )
        }
        guard submission.status == .pending else {
            throw APIError.server(
                code: "already_decided",
                message: "That proof has already been decided.",
                status: 409
            )
        }
        guard submission.eligibleVoters > 0 else {
            throw APIError.server(
                code: "solo_group",
                message: "Invite friends to get votes on your proofs.",
                status: 409
            )
        }
        castVote(submissionID: submissionID, voterID: currentUserID, approve: approve, at: Date())
        guard let updated = submissions[submissionID] else {
            throw APIError.server(code: "not_found", message: "That proof does not exist.", status: 404)
        }
        return updated
    }

    /// Decides a submission as soon as one of the thresholds is reached. Whichever
    /// threshold is hit first wins (SPEC.md, section 1, "Voting").
    private mutating func evaluate(submissionID: String) {
        guard var submission = submissions[submissionID], submission.status == .pending else { return }
        let log = votes[submissionID] ?? []
        let approvalsNeeded = min(2, submission.eligibleVoters)
        let rejectionsNeeded = Int(ceil(Double(submission.eligibleVoters) / 2))
        guard approvalsNeeded > 0 else { return }

        var approvals = 0
        var rejections = 0
        for record in log {
            if record.approve {
                approvals += 1
            } else {
                rejections += 1
            }
            if approvals >= approvalsNeeded {
                submission.status = .accepted
                submission.decidedAt = record.createdAt
                break
            }
            if rejections >= rejectionsNeeded {
                submission.status = .rejected
                submission.decidedAt = record.createdAt
                break
            }
        }
        guard submission.status != .pending else { return }
        submissions[submissionID] = submission

        if submission.status == .accepted {
            acceptanceWeeks["\(submission.groupID)|\(submission.userID)", default: []].insert(submission.weekID)
            awardChallengePoints(submission)
            if let info = challengeInfo(id: submission.challengeID) {
                awardCaptainPoints(submission, points: info.challenge.points)
            }
        }
    }

    /// The points of an accepted submission: the points of the fixture plus the
    /// first-to-finish bonus of 10.
    private mutating func awardChallengePoints(_ submission: DemoSubmission) {
        guard let info = challengeInfo(id: submission.challengeID) else { return }
        let decidedAt = submission.decidedAt ?? Date()
        addEvent(
            groupID: submission.groupID,
            weekID: submission.weekID,
            userID: submission.userID,
            kind: .challenge,
            points: info.challenge.points,
            challengeID: submission.challengeID,
            submissionID: submission.id,
            at: decidedAt
        )
        let alreadyRewarded = (events[submission.groupID] ?? []).contains {
            $0.kind == .firstBonus && $0.challengeID == submission.challengeID
        }
        guard !alreadyRewarded else { return }
        addEvent(
            groupID: submission.groupID,
            weekID: submission.weekID,
            userID: submission.userID,
            kind: .firstBonus,
            points: 10,
            challengeID: submission.challengeID,
            submissionID: submission.id,
            at: decidedAt
        )
    }

    /// The captain bonus: the armband doubles the fixture — but the first to finish
    /// bonus is not doubled (SPEC.md, section 6.6).
    private mutating func awardCaptainPoints(_ submission: DemoSubmission, points: Int) {
        guard captains["\(submission.weekID)|\(submission.userID)"] == submission.challengeID else { return }
        let alreadyRewarded = (events[submission.groupID] ?? []).contains {
            $0.kind == .captain && $0.submissionID == submission.id
        }
        guard !alreadyRewarded else { return }
        addEvent(
            groupID: submission.groupID,
            weekID: submission.weekID,
            userID: submission.userID,
            kind: .captain,
            points: points,
            challengeID: submission.challengeID,
            submissionID: submission.id,
            at: submission.decidedAt ?? Date()
        )
    }

    // MARK: - Points

    private mutating func addEvent(
        groupID: String,
        weekID: String,
        userID: String,
        kind: DemoPointEvent.Kind,
        points: Int,
        challengeID: String? = nil,
        submissionID: String? = nil,
        at date: Date
    ) {
        eventCounter += 1
        let event = DemoPointEvent(
            id: "demo-event-\(eventCounter)",
            groupID: groupID,
            weekID: weekID,
            userID: userID,
            kind: kind,
            points: points,
            challengeID: challengeID,
            submissionID: submissionID,
            createdAt: date
        )
        events[groupID, default: []].append(event)
    }

    func pointEvents(groupID: String) -> [DemoPointEvent] {
        events[groupID] ?? []
    }

    /// The points of a member in a matchweek.
    func pointsInWeek(groupID: String, weekID: String, userID: String) -> Int {
        (events[groupID] ?? [])
            .filter { $0.weekID == weekID && $0.userID == userID }
            .reduce(0) { $0 + $1.points }
    }

    /// The points of every member in a matchweek.
    func weeklyPoints(groupID: String, weekID: String) -> [String: Int] {
        var totals: [String: Int] = [:]
        for userID in memberIDs[groupID] ?? [] {
            totals[userID] = 0
        }
        for event in events[groupID] ?? [] where event.weekID == weekID {
            totals[event.userID, default: 0] += event.points
        }
        return totals
    }

    /// The rank of a member in a matchweek (1 is the best).
    func rank(groupID: String, weekID: String, userID: String) -> Int {
        let totals = weeklyPoints(groupID: groupID, weekID: weekID)
        let own = totals[userID] ?? 0
        let better = totals.filter { $0.value > own }.count
        return better + 1
    }

    /// The number of members that count as the top half of the table.
    func topHalfSize(groupID: String) -> Int {
        max(1, (memberIDs[groupID]?.count ?? 1) / 2)
    }

    /// The number of consecutive matchweeks (closed ones only) in which the member had
    /// an accepted proof and finished in the top half of the table.
    func streak(userID: String, groupID: String, upTo week: Week?) -> Int {
        guard let list = weeks[groupID], let week else { return 0 }
        guard let index = list.firstIndex(where: { $0.id == week.id }) else { return 0 }
        var count = 0
        var cursor = index
        while cursor >= 0 {
            let candidate = list[cursor]
            if candidate.status == .open {
                // The current matchweek is still running: it only counts once it is closed.
                cursor -= 1
                continue
            }
            let accepted = acceptanceWeeks["\(groupID)|\(userID)"]?.contains(candidate.id) == true
            let topHalf = rank(groupID: groupID, weekID: candidate.id, userID: userID)
                <= topHalfSize(groupID: groupID)
            if accepted && topHalf {
                count += 1
            } else {
                break
            }
            cursor -= 1
        }
        return count
    }

    /// The leaderboard of a club: the sum of the point ledger.
    func leaderboard(groupID: String, scope: LeaderboardScope) -> [LeaderboardEntry] {
        let currentWeek = week(of: groupID)
        var totals: [String: Int] = [:]
        for event in events[groupID] ?? [] {
            if scope == .week, event.weekID != currentWeek?.id { continue }
            totals[event.userID, default: 0] += event.points
        }
        let ranked = (memberIDs[groupID] ?? []).map { userID in
            let user = users[userID] ?? User(id: userID, displayName: "Unknown", avatarEmoji: nil)
            return LeaderboardEntry(
                user: user,
                points: totals[userID] ?? 0,
                rank: 0,
                streak: streak(userID: userID, groupID: groupID, upTo: currentWeek)
            )
        }
        let sorted = ranked.sorted { lhs, rhs in
            if lhs.points != rhs.points { return lhs.points > rhs.points }
            return lhs.user.displayName.localizedCaseInsensitiveCompare(rhs.user.displayName) == .orderedAscending
        }
        var result: [LeaderboardEntry] = []
        var rank = 0
        var previousPoints: Int?
        for (index, entry) in sorted.enumerated() {
            if previousPoints != entry.points {
                rank = index + 1
                previousPoints = entry.points
            }
            result.append(
                LeaderboardEntry(user: entry.user, points: entry.points, rank: rank, streak: entry.streak)
            )
        }
        return result
    }

    /// The form of a member: the last five closed matchweeks.
    func form(groupID: String, userID: String) -> [FormSquares.Result] {
        guard let list = weeks[groupID] else { return [] }
        let closed = list.filter { $0.status == .closed }.suffix(5)
        return closed.map { week in
            let accepted = acceptanceWeeks["\(groupID)|\(userID)"]?.contains(week.id) == true
            guard accepted else { return .loss }
            let topHalf = rank(groupID: groupID, weekID: week.id, userID: userID)
                <= topHalfSize(groupID: groupID)
            return topHalf ? .win : .draw
        }
    }

    /// The number of matchweeks a member won.
    func wins(groupID: String, userID: String) -> Int {
        guard let list = weeks[groupID] else { return 0 }
        return list.filter { week in
            week.status == .closed
                && rank(groupID: groupID, weekID: week.id, userID: userID) == 1
                && (pointsInWeek(groupID: groupID, weekID: week.id, userID: userID) > 0)
        }.count
    }

    /// The club form: the number of consecutive closed matchweeks in which every member
    /// of the club scored at least once.
    func clubForm(groupID: String) -> Int {
        guard let list = weeks[groupID] else { return 0 }
        let closed = list.filter { $0.status == .closed }
        var count = 0
        for week in closed.reversed() {
            let totals = weeklyPoints(groupID: groupID, weekID: week.id)
            let everybody = (memberIDs[groupID] ?? []).allSatisfy { (totals[$0] ?? 0) > 0 }
            guard everybody else { break }
            count += 1
        }
        return count
    }

    // MARK: - Title race

    /// The title race: the points of every member, matchweek by matchweek.
    func race(groupID: String, viewerID: String) -> RaceResponse {
        let list = weeks[groupID] ?? []
        let raceWeeks = list.map {
            RaceWeek(id: $0.id, number: $0.number, startsAt: $0.startsAt)
        }
        var cumulativeByUser: [String: [Int]] = [:]
        var perWeekByUser: [String: [Int]] = [:]
        for userID in memberIDs[groupID] ?? [] {
            var cumulative: [Int] = []
            var perWeek: [Int] = []
            var running = 0
            for week in list {
                let points = pointsInWeek(groupID: groupID, weekID: week.id, userID: userID)
                running += points
                cumulative.append(running)
                perWeek.append(points)
            }
            cumulativeByUser[userID] = cumulative
            perWeekByUser[userID] = perWeek
        }
        let series = (memberIDs[groupID] ?? []).compactMap { userID -> RaceSeries? in
            guard let user = users[userID] else { return nil }
            return RaceSeries(
                user: user,
                cumulative: cumulativeByUser[userID] ?? [],
                perWeek: perWeekByUser[userID] ?? []
            )
        }
        // The average and the best week of the matchweeks that are on the chart.
        let window = max(raceWeeks.count - 8, 0)
        let myPerWeek = perWeekByUser[viewerID] ?? []
        let windowPerWeek = Array(myPerWeek.suffix(8))
        let bestPoints = windowPerWeek.max() ?? 0
        let bestIndex = windowPerWeek.firstIndex(of: bestPoints) ?? 0
        let bestNumber = raceWeeks.indices.contains(window + bestIndex)
            ? raceWeeks[window + bestIndex].number
            : 0
        let total = windowPerWeek.reduce(0, +)
        let average = windowPerWeek.isEmpty ? 0 : Int((Double(total) / Double(windowPerWeek.count)).rounded())
        return RaceResponse(
            weeks: raceWeeks,
            series: series,
            me: RaceMe(
                bestWeek: RaceBestWeek(number: bestNumber, points: bestPoints),
                avgPerWeek: average,
                streak: streak(userID: viewerID, groupID: groupID, upTo: week(of: groupID))
            )
        )
    }

    // MARK: - Full-time receipt

    /// The receipt of a matchweek.
    func receipt(groupID: String, weekID: String, viewerID: String) -> ReceiptResponse? {
        guard let week = weeks[groupID]?.first(where: { $0.id == weekID }) else { return nil }
        guard let club = group(id: groupID) else { return nil }
        let user = users[viewerID] ?? User(id: viewerID, displayName: "Unknown", avatarEmoji: nil)

        var lines: [ReceiptLine] = []
        if week.status == .open {
            lines = currentReceiptLines(groupID: groupID, week: week, viewerID: viewerID)
        } else {
            let results = weekResults["\(groupID)|\(week.id)"] ?? [:]
            let result = results[viewerID]
            lines = (result?.lines ?? []).map {
                ReceiptLine(label: $0.label, points: $0.points, struck: $0.struck)
            }
        }

        let totals = weeklyPoints(groupID: groupID, weekID: weekID)
        let ranked = totals.sorted { $0.value > $1.value }
        let manOfTheMatch = ranked.first.flatMap { users[$0.key] }
        let woodenSpoon = ranked.last.flatMap { users[$0.key] }
        let currentRank = rank(groupID: groupID, weekID: weekID, userID: viewerID)
        let previousWeek: Week? = {
            guard let list = weeks[groupID],
                  let index = list.firstIndex(where: { $0.id == weekID }),
                  list.indices.contains(index - 1)
            else { return nil }
            return list[index - 1]
        }()
        let previousRank = previousWeek.map {
            rank(groupID: groupID, weekID: $0.id, userID: viewerID)
        } ?? currentRank
        let delta = previousRank - currentRank

        return ReceiptResponse(
            week: ReceiptWeek(id: week.id, number: week.number, startsAt: week.startsAt, endsAt: week.endsAt),
            club: ReceiptClub(name: club.name, forfeit: club.forfeit),
            player: ReceiptPlayer(
                user: user,
                rank: currentRank,
                rankDelta: delta,
                total: totals[viewerID] ?? 0
            ),
            lines: lines,
            manOfTheMatch: manOfTheMatch,
            woodenSpoon: woodenSpoon
        )
    }

    /// The lines of the receipt of the matchweek that is still running.
    private func currentReceiptLines(groupID: String, week: Week, viewerID: String) -> [ReceiptLine] {
        var lines: [ReceiptLine] = []
        let mine = submissionList(groupID: groupID)
            .filter { $0.weekID == week.id && $0.userID == viewerID }
            .sorted { lhs, rhs in
                let left = challengeInfo(id: lhs.challengeID)?.challenge.position ?? 0
                let right = challengeInfo(id: rhs.challengeID)?.challenge.position ?? 0
                return left < right
            }
        for submission in mine {
            guard let info = challengeInfo(id: submission.challengeID) else { continue }
            let position = String(format: "%02d", info.challenge.position)
            let title = info.challenge.title.uppercased()
            switch submission.status {
            case .accepted:
                lines.append(
                    ReceiptLine(
                        label: "\(position) \(title)",
                        points: eventPoints(groupID: groupID, submissionID: submission.id, kind: .challenge),
                        struck: false
                    )
                )
            case .rejected:
                lines.append(
                    ReceiptLine(label: "\(position) \(title) · VAR: NO GOAL", points: 0, struck: true)
                )
            case .pending, .expired, .removed:
                continue
            }
        }
        for event in pointEvents(groupID: groupID) where event.weekID == week.id && event.userID == viewerID {
            switch event.kind {
            case .firstBonus:
                lines.append(ReceiptLine(label: "FIRST TO SCORE BONUS", points: event.points, struck: false))
            case .streak:
                let streak = streak(userID: viewerID, groupID: groupID, upTo: week)
                lines.append(
                    ReceiptLine(
                        label: "STREAK 🔥 \(streak) WKS",
                        points: event.points,
                        struck: false
                    )
                )
            case .weeklyWinner:
                lines.append(ReceiptLine(label: "MAN OF THE MATCH", points: event.points, struck: false))
            case .captain:
                lines.append(ReceiptLine(label: "CAPTAIN ×2", points: event.points, struck: false))
            case .challenge:
                break
            }
        }
        return lines
    }

    private func eventPoints(groupID: String, submissionID: String, kind: DemoPointEvent.Kind) -> Int {
        pointEvents(groupID: groupID)
            .filter { $0.submissionID == submissionID && $0.kind == kind }
            .reduce(0) { $0 + $1.points }
    }

    // MARK: - Awards

    /// The awards of a ceremony month.
    func awards(groupID: String, month: String?) -> AwardsResponse {
        let resolvedMonth = month ?? awardMonth
        let totals = seasonTotals(groupID: groupID)
        let winners = DemoSeed.awardWinners(month: resolvedMonth, points: totals)
        var list: [Award] = []
        for key in AwardKey.ceremonyOrder {
            guard let winnerIDs = winners[key], let first = winnerIDs.first else { continue }
            let value = DemoSeed.awardValue(key, userID: first, points: totals[first] ?? 0)
            let nominees = nominees(for: key, groupID: groupID, totals: totals, limit: 3)
            var stats: [String: Int]? = nil
            if key == .playerOfTheMonth {
                stats = playerStats(groupID: groupID, userID: first)
            }
            list.append(
                Award(
                    award: key,
                    winners: winnerIDs.compactMap { users[$0] },
                    value: value,
                    nominees: nominees,
                    stats: stats
                )
            )
        }
        return AwardsResponse(month: resolvedMonth, awards: list)
    }

    /// The personal stats of a player: the goals, the red cards, the first to score and
    /// the best matchweek of the season.
    func playerStats(groupID: String, userID: String) -> [String: Int] {
        let seed = DemoSeed.stats[userID]
        var bestWeek = 0
        for week in weeks[groupID] ?? [] {
            bestWeek = max(bestWeek, pointsInWeek(groupID: groupID, weekID: week.id, userID: userID))
        }
        return [
            "goals": seed?.goals ?? 0,
            "redCards": seed?.redCards ?? 0,
            "firstToScore": seed?.firstToScore ?? 0,
            "bestWeek": bestWeek,
        ]
    }

    /// The three nominees of an award.
    ///
    /// Every award is measured by its own metric and the best comes first. The Wooden
    /// Spoon is the exception: it goes to the player with the **fewest** points, so its
    /// nominees are the three worst of the club, worst first.
    private func nominees(
        for key: AwardKey,
        groupID: String,
        totals: [String: Int],
        limit: Int
    ) -> [AwardNominee] {
        let worstFirst = key == .woodenSpoon
        let ranked = totals.sorted { lhs, rhs in
            let left = DemoSeed.awardValue(key, userID: lhs.key, points: lhs.value)
            let right = DemoSeed.awardValue(key, userID: rhs.key, points: rhs.value)
            if left != right { return worstFirst ? left < right : left > right }
            return lhs.key < rhs.key
        }
        return ranked.prefix(limit).compactMap { entry in
            guard let user = users[entry.key] else { return nil }
            return AwardNominee(
                user: user,
                value: DemoSeed.awardValue(key, userID: entry.key, points: entry.value)
            )
        }
    }

    /// The points of every member of the club since the beginning of the season.
    func seasonTotals(groupID: String) -> [String: Int] {
        var totals: [String: Int] = [:]
        for userID in memberIDs[groupID] ?? [] {
            totals[userID] = (events[groupID] ?? [])
                .filter { $0.userID == userID }
                .reduce(0) { $0 + $1.points }
        }
        return totals
    }

    /// The months that have an awards ceremony.
    func awardMonthList() -> [String] {
        DemoSeed.awardMonths(now: Date())
    }

    /// The trophy cabinet of a player.
    func trophies(userID: String) -> [Trophy] {
        var result: [Trophy] = []
        for month in awardMonthList() {
            let awards = awards(groupID: DemoSeed.sundayLeagueID, month: month)
            for award in awards.awards {
                guard award.winners.contains(where: { $0.id == userID }) else { continue }
                result.append(
                    Trophy(
                        groupId: DemoSeed.sundayLeagueID,
                        groupName: DemoSeed.clubName,
                        month: month,
                        award: award.award,
                        value: award.value
                    )
                )
            }
        }
        return result
    }

    // MARK: - v3: reactions, comments, reports, blocks and bans

    /// The reactions of a proof, in the fixed order of the spec. The reactions without
    /// a single member are not sent.
    func reactionList(submissionID: String, viewerID: String) -> [Reaction] {
        let log = reactions[submissionID] ?? [:]
        return ReactionEmoji.displayOrder.compactMap { emoji in
            guard let users = log[emoji], !users.isEmpty else { return nil }
            return Reaction(emoji: emoji.rawValue, count: users.count, mine: users.contains(viewerID))
        }
    }

    /// The comments of a proof, oldest first.
    func commentList(submissionID: String, viewerID: String, groupID: String) -> [Comment] {
        let ownerID = groups[groupID]?.ownerId
        return (comments[submissionID] ?? []).compactMap { comment in
            guard let user = users[comment.userID] else { return nil }
            guard !isBlocked(by: viewerID, user: comment.userID) else { return nil }
            guard !isReported(targetType: .comment, targetID: comment.id, by: viewerID) else { return nil }
            return Comment(
                id: comment.id,
                user: user,
                text: comment.text,
                createdAt: comment.createdAt,
                canDelete: comment.userID == viewerID || viewerID == ownerID
            )
        }
    }

    /// True when the player blocked the other one. The block is silent and one way.
    func isBlocked(by blockerID: String, user userID: String) -> Bool {
        blocks[blockerID]?.contains(userID) == true
    }

    /// True when the player reported the content — it is hidden for them.
    func isReported(targetType: DemoReport.TargetType, targetID: String, by reporterID: String) -> Bool {
        reports.contains {
            $0.reporterID == reporterID && $0.targetType == targetType && $0.targetID == targetID
        }
    }

    /// Toggles my reaction of a proof.
    @discardableResult
    mutating func toggleReaction(
        submissionID: String,
        emoji: ReactionEmoji,
        userID: String
    ) throws -> DemoSubmission {
        guard let submission = submissions[submissionID] else {
            throw APIError.server(code: "not_found", message: "That proof does not exist.", status: 404)
        }
        var log = reactions[submissionID] ?? [:]
        var members = log[emoji] ?? []
        if members.contains(userID) {
            members.remove(userID)
        } else {
            members.insert(userID)
        }
        if members.isEmpty {
            log.removeValue(forKey: emoji)
        } else {
            log[emoji] = members
        }
        reactions[submissionID] = log
        return submission
    }

    /// Writes a comment on a proof.
    mutating func addComment(submissionID: String, text: String, userID: String) throws -> DemoComment {
        guard submissions[submissionID] != nil else {
            throw APIError.server(code: "not_found", message: "That proof does not exist.", status: 404)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 280 else {
            throw APIError.server(
                code: "invalid_comment",
                message: "A comment is 1 to 280 characters.",
                status: 400
            )
        }
        commentCounter += 1
        let comment = DemoComment(
            id: "demo-comment-\(commentCounter)",
            submissionID: submissionID,
            userID: userID,
            text: trimmed,
            createdAt: Date()
        )
        comments[submissionID, default: []].append(comment)
        return comment
    }

    /// Deletes a comment — the author of the comment or the owner of the club.
    mutating func deleteComment(id: String, by userID: String) throws {
        for (submissionID, list) in comments {
            guard let comment = list.first(where: { $0.id == id }) else { continue }
            let groupID = submissions[comment.submissionID]?.groupID
            let ownerID = groupID.flatMap { groups[$0]?.ownerId }
            guard comment.userID == userID || ownerID == userID else {
                throw APIError.server(
                    code: "forbidden",
                    message: "You cannot delete this comment.",
                    status: 403
                )
            }
            comments[submissionID]?.removeAll { $0.id == id }
            return
        }
        throw APIError.server(code: "not_found", message: "That comment does not exist.", status: 404)
    }

    /// Reports a proof or a comment. The content is hidden for the reporter at once —
    /// and removed for everybody when enough members reported it.
    mutating func report(
        targetType: DemoReport.TargetType,
        targetID: String,
        reporterID: String,
        reason: ReportReason,
        note: String?,
        groupID: String
    ) throws {
        let authorID: String
        switch targetType {
        case .submission:
            guard let submission = submissions[targetID] else {
                throw APIError.server(code: "not_found", message: "That proof does not exist.", status: 404)
            }
            authorID = submission.userID
        case .comment:
            var found: DemoComment?
            for list in comments.values {
                if let comment = list.first(where: { $0.id == targetID }) {
                    found = comment
                    break
                }
            }
            guard let comment = found else {
                throw APIError.server(code: "not_found", message: "That comment does not exist.", status: 404)
            }
            authorID = comment.userID
        }

        guard authorID != reporterID else {
            throw APIError.server(
                code: "own_content",
                message: "You cannot report your own content.",
                status: 400
            )
        }
        guard !isReported(targetType: targetType, targetID: targetID, by: reporterID) else {
            throw APIError.server(
                code: "already_reported",
                message: "You already reported this.",
                status: 409
            )
        }

        reports.append(
            DemoReport(
                reporterID: reporterID,
                targetType: targetType,
                targetID: targetID,
                groupID: groupID,
                reason: reason,
                note: note,
                createdAt: Date()
            )
        )

        let reporters = Set(
            reports
                .filter { $0.targetType == targetType && $0.targetID == targetID }
                .map(\.reporterID)
        )
        let threshold = max(2, Int(ceil(Double(memberIDs[groupID]?.count ?? 1) / 3.0)))
        guard reporters.count >= threshold else { return }

        switch targetType {
        case .submission:
            removeSubmission(targetID)
        case .comment:
            for (submissionID, list) in comments {
                comments[submissionID] = list.filter { $0.id != targetID }
            }
        }
    }

    /// Removes a proof and everything that belongs to it.
    private mutating func removeSubmission(_ id: String) {
        guard var submission = submissions[id] else { return }
        submission.status = .removed
        submission.decidedAt = Date()
        submissions[id] = submission
        votes[id] = nil
        reactions[id] = nil
        comments[id] = nil
        for (groupID, list) in events {
            events[groupID] = list.filter { $0.submissionID != id }
        }
    }

    /// Blocks a member: their proofs and comments disappear for me.
    mutating func block(userID: String, by blockerID: String) {
        guard userID != blockerID else { return }
        blocks[blockerID, default: []].insert(userID)
    }

    /// Unblocks a member.
    mutating func unblock(userID: String, by blockerID: String) {
        blocks[blockerID]?.remove(userID)
    }

    /// The members I blocked.
    func blockedUsers(for blockerID: String) -> [User] {
        (blocks[blockerID] ?? [])
            .compactMap { users[$0] }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// The owner removes a member of the club: their pending proofs expire and they
    /// cannot come back with the invite code.
    mutating func removeMember(groupID: String, userID: String, by ownerID: String) throws {
        guard groups[groupID]?.ownerId == ownerID else {
            throw APIError.server(
                code: "forbidden",
                message: "Only the owner of the club can remove a member.",
                status: 403
            )
        }
        guard userID != ownerID else {
            throw APIError.server(
                code: "cannot_remove_owner",
                message: "The owner cannot be removed from the club.",
                status: 400
            )
        }
        guard memberIDs[groupID]?.contains(userID) == true else {
            throw APIError.server(code: "not_found", message: "That member is not in the club.", status: 404)
        }
        memberIDs[groupID]?.removeAll { $0 == userID }
        for (id, submission) in submissions {
            guard submission.groupID == groupID, submission.userID == userID else { continue }
            guard submission.status == .pending else { continue }
            submissions[id]?.status = .expired
        }
        bans[groupID, default: [:]][userID] = Date()
    }

    /// The owner lifts the ban of a member.
    mutating func unbanMember(groupID: String, userID: String, by ownerID: String) throws {
        guard groups[groupID]?.ownerId == ownerID else {
            throw APIError.server(
                code: "forbidden",
                message: "Only the owner of the club can lift a ban.",
                status: 403
            )
        }
        bans[groupID]?.removeValue(forKey: userID)
    }

    /// The members the owner removed from the club.
    func bannedMembers(groupID: String) -> [BannedMember] {
        (bans[groupID] ?? [:])
            .compactMap { userID, date in
                guard let user = users[userID] else { return nil }
                return BannedMember(user: user, bannedAt: date)
            }
            .sorted { $0.user.displayName.localizedCaseInsensitiveCompare($1.user.displayName) == .orderedAscending }
    }

    // MARK: - v3: veto, captain and house fixture

    /// The number of vetoes that replaces a fixture: half of the club, rounded up.
    func vetoThreshold(groupID: String) -> Int {
        max(1, Int(ceil(Double(memberIDs[groupID]?.count ?? 1) / 2.0)))
    }

    /// Vetoes a fixture. When the club has the majority, the fixture is replaced in
    /// place — a house fixture is never replaced (SPEC.md, section 6.3).
    mutating func veto(challengeID: String, by userID: String) throws -> (challenge: Challenge, replaced: Bool) {
        guard let info = challengeInfo(id: challengeID) else {
            throw APIError.server(code: "not_found", message: "That fixture does not exist.", status: 404)
        }
        let groupID = info.groupID
        guard let week = week(of: groupID), week.status == .open else {
            throw APIError.server(
                code: "week_closed",
                message: "The matchweek is closed.",
                status: 409
            )
        }

        var log = vetoes[challengeID] ?? []
        let alreadyVetoed = log.contains(userID)
        let newCount = alreadyVetoed ? log.count - 1 : log.count + 1
        let threshold = vetoThreshold(groupID: groupID)

        if newCount >= threshold, !info.challenge.isHouse {
            // The fixture would be replaced — the club has two replacements per matchweek.
            let key = "\(groupID)|\(week.id)"
            guard (replacements[key] ?? 0) < 2 else {
                throw APIError.server(
                    code: "veto_limit",
                    message: "2 vetoes used this week.",
                    status: 409
                )
            }
        }

        if alreadyVetoed {
            log.remove(userID)
        } else {
            log.insert(userID)
        }
        vetoes[challengeID] = log

        guard newCount >= threshold else {
            let challenge = makeChallenge(
                info.challenge,
                groupID: groupID,
                weekID: info.weekID,
                viewerID: userID
            )
            return (challenge, false)
        }

        if info.challenge.isHouse {
            // A house fixture is vetoed out of the matchweek, but never replaced.
            vetoOutFixture(info.challenge, groupID: groupID)
            let challenge = makeChallenge(
                info.challenge,
                groupID: groupID,
                weekID: info.weekID,
                viewerID: userID
            )
            return (challenge, false)
        }

        let replacement = replaceFixture(info.challenge, groupID: groupID, weekID: info.weekID)
        replacements["\(groupID)|\(week.id)", default: 0] += 1
        let challenge = makeChallenge(
            replacement,
            groupID: groupID,
            weekID: info.weekID,
            viewerID: userID
        )
        return (challenge, true)
    }

    /// Takes a fixture out of the matchweek. Its proofs expire.
    private mutating func vetoOutFixture(_ challenge: DemoChallenge, groupID: String) {
        var list = challengeList(groupID: groupID, weekID: weekID(ofChallenge: challenge))
        if let index = list.firstIndex(where: { $0.id == challenge.id }) {
            list[index].vetoed = true
        }
        challenges["\(groupID)|\(weekID(ofChallenge: challenge))"] = list
        expireSubmissions(challengeID: challenge.id)
    }

    /// Replaces a fixture in place: the new fixture keeps the position and the
    /// difficulty of the old one.
    private mutating func replaceFixture(
        _ challenge: DemoChallenge,
        groupID: String,
        weekID: String
    ) -> DemoChallenge {
        var list = challengeList(groupID: groupID, weekID: weekID)
        if let index = list.firstIndex(where: { $0.id == challenge.id }) {
            list[index].vetoed = true
        }
        expireSubmissions(challengeID: challenge.id)

        let used = Set(list.map(\.title))
        let entry = DemoSeed.fixturePool.first { !used.contains($0.title) } ?? DemoSeed.fixturePool[0]
        let replacement = DemoChallenge(
            id: "demo-challenge-\(weekID)-new-\(challenge.id)",
            title: entry.title,
            description: DemoSeed.description(for: entry.title, difficulty: challenge.difficulty),
            difficulty: challenge.difficulty,
            points: Self.points(for: challenge.difficulty),
            position: challenge.position,
            isHouse: false,
            createdBy: nil,
            createdAt: Date(),
            vetoed: false
        )
        list.removeAll { $0.id == challenge.id }
        list.append(replacement)
        challenges["\(groupID)|\(weekID)"] = list.sorted { $0.position < $1.position }
        return replacement
    }

    /// The proofs of a fixture expire and their points are gone.
    private mutating func expireSubmissions(challengeID: String) {
        for (id, submission) in submissions where submission.challengeID == challengeID {
            guard submission.status != .removed else { continue }
            if submission.status == .pending || submission.status == .accepted {
                submissions[id]?.status = .expired
            }
            for (groupID, list) in events {
                events[groupID] = list.filter { $0.submissionID != id }
            }
        }
    }

    /// The matchweek of a fixture.
    private func weekID(ofChallenge challenge: DemoChallenge) -> String {
        challengeInfo(id: challenge.id)?.weekID ?? ""
    }

    /// Chooses the captain fixture of the matchweek. The armband locks as soon as I
    /// have a proof on it (SPEC.md, section 6.6).
    mutating func setCaptain(groupID: String, challengeID: String, by userID: String) throws -> Week {
        guard let week = week(of: groupID), week.status == .open else {
            throw APIError.server(
                code: "week_closed",
                message: "The matchweek is closed.",
                status: 409
            )
        }
        guard let info = challengeInfo(id: challengeID),
              info.groupID == groupID,
              info.weekID == week.id
        else {
            throw APIError.server(code: "not_found", message: "That fixture does not exist.", status: 404)
        }

        let key = "\(week.id)|\(userID)"
        if let current = captains[key] {
            let played = submissions.values.contains { submission in
                submission.challengeID == current
                    && submission.userID == userID
                    && submission.status != .rejected
                    && submission.status != .expired
            }
            if played {
                throw APIError.server(
                    code: "captain_locked",
                    message: "You already played your captain fixture.",
                    status: 409
                )
            }
        }
        captains[key] = challengeID
        return apiWeek(groupID: groupID, viewerID: userID) ?? week
    }

    /// The captain fixture of a member in the matchweek.
    func captainChallengeID(groupID: String, weekID: String, userID: String) -> String? {
        captains["\(weekID)|\(userID)"]
    }

    /// The member that may write the house fixture: the man of the match of the
    /// previous matchweek — in the first matchweek of a club the owner.
    func houseFixtureAuthor(groupID: String) -> String? {
        guard let list = weeks[groupID], let current = list.last else { return nil }
        let ownerID = groups[groupID]?.ownerId
        guard let index = list.firstIndex(where: { $0.id == current.id }), index > 0 else { return ownerID }
        let previous = list[index - 1]
        let totals = weeklyPoints(groupID: groupID, weekID: previous.id)
        guard let best = totals.max(by: { $0.value < $1.value }), best.value > 0 else { return ownerID }
        return best.key
    }

    /// Wednesday 23:59 of the matchweek, in the time zone of the club.
    func houseFixtureDeadline(groupID: String) -> Date {
        guard let week = week(of: groupID) else { return Date() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: groups[groupID]?.timezone ?? "") ?? .current
        let monday = calendar.dateInterval(of: .day, for: week.startsAt)?.start ?? week.startsAt
        let wednesday = calendar.date(byAdding: .day, value: 2, to: monday) ?? monday
        var deadline = calendar.date(byAdding: .minute, value: 23 * 60 + 59, to: wednesday) ?? wednesday
        if deadline < Date() {
            // The demo keeps the window open, so the feature is always reachable.
            let nextWednesday = calendar.date(byAdding: .day, value: 7, to: wednesday) ?? wednesday
            deadline = calendar.date(byAdding: .minute, value: 23 * 60 + 59, to: nextWednesday) ?? nextWednesday
        }
        return deadline
    }

    /// The house fixture of the matchweek — `nil` when there is none yet.
    func currentHouseFixture(groupID: String) -> DemoChallenge? {
        guard let week = week(of: groupID) else { return nil }
        return challengeList(groupID: groupID, weekID: week.id).first { $0.isHouse && !$0.vetoed }
    }

    /// The state of the house fixture for the player.
    func houseFixtureInfo(groupID: String, viewerID: String) -> HouseFixtureInfo {
        let deadline = houseFixtureDeadline(groupID: groupID)
        if let existing = currentHouseFixture(groupID: groupID) {
            return HouseFixtureInfo(
                allowed: false,
                deadline: deadline,
                author: existing.createdBy.flatMap { users[$0] }
            )
        }
        let allowed = houseFixtureAuthor(groupID: groupID) == viewerID && Date() <= deadline
        return HouseFixtureInfo(allowed: allowed, deadline: deadline, author: nil)
    }

    /// Writes the house fixture of the matchweek.
    mutating func addHouseFixture(
        groupID: String,
        request: HouseFixtureRequest,
        by userID: String
    ) throws -> Challenge {
        guard let week = week(of: groupID), week.status == .open else {
            throw APIError.server(
                code: "week_closed",
                message: "The matchweek is closed.",
                status: 409
            )
        }
        guard currentHouseFixture(groupID: groupID) == nil else {
            throw APIError.server(
                code: "house_fixture_taken",
                message: "The house fixture of this matchweek is already written.",
                status: 409
            )
        }
        guard houseFixtureAuthor(groupID: groupID) == userID else {
            throw APIError.server(
                code: "not_allowed",
                message: "Only the man of the match writes the house fixture.",
                status: 403
            )
        }
        guard Date() <= houseFixtureDeadline(groupID: groupID) else {
            throw APIError.server(
                code: "house_fixture_closed",
                message: "The house fixture closes on Wednesday night.",
                status: 409
            )
        }
        let title = request.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.count >= 3, title.count <= 80 else {
            throw APIError.server(
                code: "invalid_title",
                message: "A fixture needs a title of 3 to 80 characters.",
                status: 400
            )
        }
        var list = challengeList(groupID: groupID, weekID: week.id)
        let house = DemoChallenge(
            id: "demo-challenge-house-\(week.id)",
            title: title,
            description: request.description,
            difficulty: request.difficulty,
            points: Self.points(for: request.difficulty),
            position: (list.map(\.position).max() ?? 0) + 1,
            isHouse: true,
            createdBy: userID,
            createdAt: Date(),
            vetoed: false
        )
        list.append(house)
        challenges["\(groupID)|\(week.id)"] = list.sorted { $0.position < $1.position }
        return makeChallenge(house, groupID: groupID, weekID: week.id, viewerID: userID)
    }

    // MARK: - Helpers

    /// The user of the demo world.
    func user(id: String) -> User? {
        users[id]
    }

    /// The owner of a club.
    func ownerID(of groupID: String) -> String? {
        groups[groupID]?.ownerId
    }

    /// The club a comment belongs to.
    func groupID(ofComment id: String) -> String? {
        for list in comments.values {
            if let comment = list.first(where: { $0.id == id }) {
                return submissions[comment.submissionID]?.groupID
            }
        }
        return nil
    }

    /// The player accepts the house rules.
    mutating func acceptTerms() -> User {
        guard let stored = users[currentUserID] else {
            return User(id: currentUserID, displayName: "")
        }
        let updated = User(
            id: stored.id,
            displayName: stored.displayName,
            avatarEmoji: stored.avatarEmoji,
            termsAccepted: true
        )
        users[currentUserID] = updated
        return updated
    }

    /// The push switches of a member.
    func notificationPrefs(for userID: String) -> NotificationPrefs {
        notificationPrefs[userID] ?? NotificationPrefs()
    }

    /// Deletes my own proof — with its votes, its banter and its points.
    mutating func deleteSubmission(id: String, by userID: String) throws {
        guard let submission = submissions[id] else {
            throw APIError.server(code: "not_found", message: "That proof does not exist.", status: 404)
        }
        guard submission.userID == userID else {
            throw APIError.server(
                code: "forbidden",
                message: "You can only delete your own proof.",
                status: 403
            )
        }
        removeSubmission(id)
    }

    func voters(groupID: String, excluding userID: String) -> [String] {
        (memberIDs[groupID] ?? []).filter { $0 != userID }
    }

    /// Adds a member (used by the demo and by the tests).
    mutating func addMember(groupID: String, user: User) {
        if users[user.id] == nil {
            users[user.id] = user
        }
        if memberIDs[groupID] == nil {
            memberIDs[groupID] = []
        }
        if memberIDs[groupID]?.contains(user.id) != true {
            memberIDs[groupID]?.append(user.id)
            joinDates["\(groupID)|\(user.id)"] = Date()
        }
    }

    mutating func setCurrentUser(_ userID: String) {
        currentUserID = userID
    }

    mutating func updateUser(displayName: String?, avatarEmoji: String?) -> User {
        let stored = users[currentUserID] ?? User(id: currentUserID, displayName: "", avatarEmoji: nil)
        let updated = User(
            id: stored.id,
            displayName: displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? stored.displayName,
            avatarEmoji: avatarEmoji ?? stored.avatarEmoji
        )
        users[currentUserID] = updated
        return updated
    }

    mutating func removeCurrentUser() {
        for groupID in memberIDs.keys {
            memberIDs[groupID]?.removeAll { $0 == currentUserID }
        }
        users.removeValue(forKey: currentUserID)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
