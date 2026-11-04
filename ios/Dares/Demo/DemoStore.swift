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

/// A stored submission of a challenge.
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

/// A stored challenge. The view dependent fields (`myStatus`, `acceptedCount`) are computed
/// per viewer, so they are not part of the stored record.
struct DemoChallenge: Sendable {
    let id: String
    let title: String
    let description: String
    let difficulty: Difficulty
    let points: Int
    let position: Int
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

/// The in-memory world of the demo: users, groups, weeks, challenges, submissions,
/// votes and the point ledger. It is a plain value type so it can be seeded without
/// touching the actor that owns it.
struct DemoStore: Sendable {
    var users: [String: User] = [:]
    var groups: [String: Group] = [:]
    var memberIDs: [String: [String]] = [:]
    var joinDates: [String: Date] = [:]
    /// Weeks per group, oldest first. The last one is the current week.
    var weeks: [String: [Week]] = [:]
    /// Challenges per week, keyed by `"\(groupID)|\(weekID)"`.
    var challenges: [String: [DemoChallenge]] = [:]
    var submissions: [String: DemoSubmission] = [:]
    var submissionOrder: [String] = []
    /// Votes per submission, in the order they were cast.
    var votes: [String: [DemoVote]] = [:]
    /// The point ledger per group.
    var events: [String: [DemoPointEvent]] = [:]
    /// `"groupID|userID"` → week IDs in which the member had an accepted submission.
    var acceptanceWeeks: [String: Set<String>] = [:]
    /// Proofs uploaded during the demo, keyed by their media key.
    var uploads: [String: Data] = [:]
    /// Votes the demo plays by itself.
    var pendingSimulations: [DemoSimulation] = []

    var currentUserID: String = DemoSeed.currentUserID

    private var eventCounter = 0
    private var submissionCounter = 0
    private var inviteCounter = 0

    // MARK: - Calendar helpers

    /// Monday 00:00 of the week that contains `date` (SPEC.md, section 1, "Week").
    static func mondayStart(_ date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        calendar.firstWeekday = 2 // Monday
        return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }

    static func makeWeek(groupID: String, start: Date, status: WeekStatus) -> Week {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        return Week(
            id: "demo-week-\(groupID)-\(Int(start.timeIntervalSince1970))",
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

    mutating func seed(now: Date) {
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

        let weekStart = Self.mondayStart(now)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current

        // Closed weeks first, the open week last.
        for group in DemoSeed.groups {
            var list: [Week] = []
            let plan = DemoSeed.history(for: group.id)
            for index in plan.indices {
                let start = calendar.date(byAdding: .day, value: -7 * (index + 1), to: weekStart) ?? weekStart
                let week = Self.makeWeek(groupID: group.id, start: start, status: .closed)
                list.append(week)
                challenges["\(group.id)|\(week.id)"] = makeChallenges(
                    weekID: week.id,
                    groupID: group.id,
                    count: group.challengesPerWeek,
                    offset: index * 5,
                    titles: DemoSeed.challengePool
                )
            }
            let current = Self.makeWeek(groupID: group.id, start: weekStart, status: .open)
            list.append(current)
            challenges["\(group.id)|\(current.id)"] = makeChallenges(
                weekID: current.id,
                groupID: group.id,
                count: group.challengesPerWeek,
                offset: 0,
                titles: DemoSeed.currentTitles(for: group.id)
            )
            weeks[group.id] = list
        }

        seedCurrentWeek(now: now)
        seedHistory(now: now)
    }

    private mutating func makeChallenges(
        weekID: String,
        groupID: String,
        count: Int,
        offset: Int,
        titles: [String]
    ) -> [DemoChallenge] {
        let difficulties: [Difficulty] = [.easy, .medium, .hard, .medium, .easy]
        return (0 ..< count).map { index in
            let titleIndex = (offset + index) % max(titles.count, 1)
            let title = titles[titleIndex]
            let difficulty = difficulties[(offset + index) % difficulties.count]
            return DemoChallenge(
                id: "demo-challenge-\(weekID)-\(index)",
                title: title,
                description: DemoSeed.description(for: title, difficulty: difficulty),
                difficulty: difficulty,
                points: Self.points(for: difficulty),
                position: index + 1
            )
        }
    }

    // MARK: - Seeded current week

    private mutating func seedCurrentWeek(now: Date) {
        let groupID = DemoSeed.warriorsID
        guard let week = weeks[groupID]?.last else { return }
        guard let list = challenges["\(groupID)|\(week.id)"] else { return }

        func challenge(_ index: Int) -> DemoChallenge? {
            list.indices.contains(index) ? list[index] : nil
        }

        // My proofs: one accepted, one waiting for votes, one rejected.
        if let first = challenge(0) {
            seedSubmission(
                groupID: groupID,
                week: week,
                challenge: first,
                userID: DemoSeed.currentUserID,
                mediaKey: DemoMedia.photoKey(1),
                caption: "5am alarm. Worth it.",
                age: 6 * 3_600,
                approvals: ["demo-user-sam", "demo-user-jo"],
                rejections: [],
                now: now
            )
        }
        if let second = challenge(1) {
            let mine = seedSubmission(
                groupID: groupID,
                week: week,
                challenge: second,
                userID: DemoSeed.currentUserID,
                mediaKey: DemoMedia.photoKey(2),
                caption: "A Korean dish I have never made before.",
                age: 4 * 3_600,
                approvals: ["demo-user-sam"],
                rejections: [],
                now: now
            )
            // The demo plays one more approval for my pending proof, so the accept flow shows.
            pendingSimulations.append(
                DemoSimulation(
                    id: "demo-simulation-1",
                    submissionID: mine.id,
                    votes: [DemoSimulatedVote(voterID: "demo-user-jo", approve: true)],
                    delay: 4
                )
            )
        }
        if let fourth = challenge(3) {
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
        }

        // Six proofs from the others, waiting for my vote.
        if let third = challenge(2) {
            seedSubmission(
                groupID: groupID,
                week: week,
                challenge: third,
                userID: "demo-user-sam",
                mediaKey: DemoMedia.videoKey,
                mediaType: .video,
                caption: "Three hours. Zero notifications.",
                age: 5 * 3_600,
                approvals: [],
                rejections: [],
                now: now
            )
            seedSubmission(
                groupID: groupID,
                week: week,
                challenge: third,
                userID: "demo-user-jo",
                mediaKey: DemoMedia.photoKey(3),
                caption: "Phone stayed in the drawer.",
                age: 30 * 60,
                approvals: ["demo-user-lee"],
                rejections: [],
                now: now
            )
        }
        if let fifth = challenge(4) {
            seedSubmission(
                groupID: groupID,
                week: week,
                challenge: fifth,
                userID: "demo-user-jo",
                mediaKey: DemoMedia.photoKey(5),
                caption: "Wrote it by hand and posted it.",
                age: 3 * 3_600,
                approvals: ["demo-user-mika"],
                rejections: [],
                now: now
            )
            seedSubmission(
                groupID: groupID,
                week: week,
                challenge: fifth,
                userID: "demo-user-lee",
                mediaKey: DemoMedia.photoKey(5),
                caption: "Dear stranger, hi.",
                age: 8 * 3_600,
                approvals: ["demo-user-sam", "demo-user-mika"],
                rejections: [],
                now: now
            )
        }
        if let first = challenge(0) {
            seedSubmission(
                groupID: groupID,
                week: week,
                challenge: first,
                userID: "demo-user-mika",
                mediaKey: DemoMedia.photoKey(1),
                caption: "Same hill, better light.",
                age: 2 * 3_600,
                approvals: [],
                rejections: ["demo-user-lee"],
                now: now
            )
        }
        if let second = challenge(1) {
            seedSubmission(
                groupID: groupID,
                week: week,
                challenge: second,
                userID: "demo-user-lee",
                mediaKey: DemoMedia.photoKey(2),
                caption: "My grandmother's recipe. Send help.",
                age: 90 * 60,
                approvals: ["demo-user-jo"],
                rejections: ["demo-user-mika"],
                now: now
            )
        }
        if let fourth = challenge(3) {
            seedSubmission(
                groupID: groupID,
                week: week,
                challenge: fourth,
                userID: "demo-user-sam",
                mediaKey: DemoMedia.photoKey(4),
                caption: "Sunset swim, cold sea.",
                age: 60 * 60,
                approvals: [],
                rejections: [],
                now: now
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

    // MARK: - Seeded history

    private mutating func seedHistory(now: Date) {
        for group in DemoSeed.groups {
            guard let list = weeks[group.id] else { continue }
            let plan = DemoSeed.history(for: group.id)
            for (index, entry) in plan.enumerated() {
                let week = list[index]
                guard let challengeList = challenges["\(group.id)|\(week.id)"] else { continue }
                var challengeIndex = 0
                for userID in entry.accept {
                    guard challengeList.indices.contains(challengeIndex) else { break }
                    let submission = makeSubmission(
                        groupID: group.id,
                        weekID: week.id,
                        challenge: challengeList[challengeIndex],
                        userID: userID,
                        mediaKey: DemoMedia.photoKey((challengeIndex % 6) + 1),
                        mediaType: .photo,
                        caption: "Last week's proof.",
                        at: week.startsAt.addingTimeInterval(Double(challengeIndex) * 3_600)
                    )
                    for voterID in voters(groupID: group.id, excluding: userID).prefix(2) {
                        castVote(
                            submissionID: submission.id,
                            voterID: voterID,
                            approve: true,
                            at: week.startsAt.addingTimeInterval(Double(challengeIndex) * 3_600 + 1_800)
                        )
                    }
                    challengeIndex += 1
                }
                for userID in entry.reject {
                    guard challengeList.indices.contains(challengeIndex) else { break }
                    let submission = makeSubmission(
                        groupID: group.id,
                        weekID: week.id,
                        challenge: challengeList[challengeIndex],
                        userID: userID,
                        mediaKey: DemoMedia.photoKey((challengeIndex % 6) + 1),
                        mediaType: .photo,
                        caption: "Not my best week.",
                        at: week.startsAt.addingTimeInterval(Double(challengeIndex) * 3_600)
                    )
                    for voterID in voters(groupID: group.id, excluding: userID).prefix(2) {
                        castVote(
                            submissionID: submission.id,
                            voterID: voterID,
                            approve: false,
                            at: week.startsAt.addingTimeInterval(Double(challengeIndex) * 3_600 + 1_800)
                        )
                    }
                    challengeIndex += 1
                }
                closeWeek(groupID: group.id, week: week)
            }
        }
    }

    // MARK: - Groups

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
            memberCount: memberIDs[id]?.count ?? 0
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
            throw APIError.server(code: "invalid_name", message: "The group needs a name.", status: 400)
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
            memberCount: 1
        )
        groups[id] = group
        memberIDs[id] = [ownerID]
        joinDates["\(id)|\(ownerID)"] = Date()

        let week = Self.makeWeek(groupID: id, start: Self.mondayStart(Date()), status: .open)
        weeks[id] = [week]
        challenges["\(id)|\(week.id)"] = makeChallenges(
            weekID: week.id,
            groupID: id,
            count: count,
            offset: inviteCounter * 3,
            titles: DemoSeed.challengePool
        )
        return group
    }

    mutating func joinGroup(inviteCode: String, userID: String) throws -> Group {
        let code = inviteCode.uppercased()
        guard let id = groups.values.first(where: { $0.inviteCode.uppercased() == code })?.id else {
            throw APIError.server(
                code: "invalid_code",
                message: "That invite code does not match any group.",
                status: 404
            )
        }
        guard memberIDs[id]?.contains(userID) != true else {
            throw APIError.server(
                code: "already_member",
                message: "You are already in this group.",
                status: 409
            )
        }
        memberIDs[id, default: []].append(userID)
        joinDates["\(id)|\(userID)"] = Date()
        if weeks[id]?.last?.status != .open {
            let week = Self.makeWeek(groupID: id, start: Self.mondayStart(Date()), status: .open)
            weeks[id, default: []].append(week)
            challenges["\(id)|\(week.id)"] = makeChallenges(
                weekID: week.id,
                groupID: id,
                count: groups[id]?.challengesPerWeek ?? 5,
                offset: 1,
                titles: DemoSeed.challengePool
            )
        }
        guard let joined = group(id: id) else {
            throw APIError.server(code: "not_found", message: "That group does not exist.", status: 404)
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
            throw APIError.server(code: "not_found", message: "That group does not exist.", status: 404)
        }
        guard stored.ownerId == userID else {
            throw APIError.server(
                code: "forbidden",
                message: "Only the group owner can change these settings.",
                status: 403
            )
        }
        let updated = Group(
            id: stored.id,
            name: request.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? stored.name,
            inviteCode: stored.inviteCode,
            challengesPerWeek: request.challengesPerWeek.map { min(max($0, 3), 10) } ?? stored.challengesPerWeek,
            theme: request.theme ?? stored.theme,
            language: request.language ?? stored.language,
            timezone: request.timezone ?? stored.timezone,
            ownerId: stored.ownerId,
            memberCount: memberIDs[id]?.count ?? 0
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

    // MARK: - Weeks & challenges

    func week(of groupID: String) -> Week? {
        weeks[groupID]?.last
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

    /// The challenges of the current week with the view dependent fields filled in.
    func challenges(groupID: String, viewerID: String) -> [Challenge] {
        guard let week = week(of: groupID) else { return [] }
        return challengeList(groupID: groupID, weekID: week.id).map { challenge in
            Challenge(
                id: challenge.id,
                title: challenge.title,
                description: challenge.description,
                difficulty: challenge.difficulty,
                points: challenge.points,
                position: challenge.position,
                myStatus: myStatus(groupID: groupID, challengeID: challenge.id, viewerID: viewerID),
                acceptedCount: acceptedCount(groupID: groupID, challengeID: challenge.id)
            )
        }
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
                message: "That challenge does not exist.",
                status: 404
            )
        }
        guard let week = week(of: info.groupID), week.status == .open else {
            throw APIError.server(
                code: "week_closed",
                message: "This week is closed, no more proofs.",
                status: 409
            )
        }
        let mine = submissions.values.filter {
            $0.groupID == info.groupID && $0.challengeID == challengeID && $0.userID == currentUserID
        }
        if mine.contains(where: { $0.status == .accepted }) {
            throw APIError.server(
                code: "already_accepted",
                message: "That challenge is already done.",
                status: 409
            )
        }
        if mine.contains(where: { $0.status == .pending }) {
            throw APIError.server(
                code: "already_pending",
                message: "You already sent a proof for this challenge.",
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
            decidedAt: submission.decidedAt
        )
    }

    /// Pending submissions of others that the viewer has not voted on, oldest first.
    func pendingVotes(groupID: String, viewerID: String) -> [Submission] {
        submissionList(groupID: groupID)
            .filter { submission in
                submission.status == .pending
                    && submission.userID != viewerID
                    && !(votes[submission.id] ?? []).contains { $0.voterID == viewerID }
            }
            .sorted { $0.createdAt < $1.createdAt }
            .map { makeSubmission($0, viewerID: viewerID) }
    }

    /// The group feed, newest first, 20 items per page.
    func feed(groupID: String, cursor: String?, viewerID: String) -> (items: [Submission], nextCursor: String?) {
        let all = submissionList(groupID: groupID)
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
        }
    }

    /// The points of an accepted submission: the points of the challenge plus the
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

    /// The number of consecutive weeks (ending with `week`) in which the member had at
    /// least one accepted submission.
    func streak(userID: String, groupID: String, upTo week: Week?) -> Int {
        guard let list = weeks[groupID], let week else { return 0 }
        guard let index = list.firstIndex(where: { $0.id == week.id }) else { return 0 }
        var count = 0
        var cursor = index
        while cursor >= 0 {
            let candidate = list[cursor]
            let accepted = acceptanceWeeks["\(groupID)|\(userID)"]?.contains(candidate.id) == true
            if accepted {
                count += 1
            } else if candidate.status == .open {
                // The current week is still open: it only counts once a proof was accepted.
                cursor -= 1
                continue
            } else {
                break
            }
            cursor -= 1
        }
        return count
    }

    /// Closes a week: pending proofs expire, the weekly winner and the streaks are paid.
    mutating func closeWeek(groupID: String, week: Week) {
        for id in submissionOrder {
            guard var submission = submissions[id],
                  submission.groupID == groupID,
                  submission.weekID == week.id,
                  submission.status == .pending
            else { continue }
            submission.status = .expired
            submissions[id] = submission
        }

        var totals: [String: Int] = [:]
        for event in events[groupID] ?? [] where event.weekID == week.id {
            totals[event.userID, default: 0] += event.points
        }
        if let best = totals.values.max(), best > 0 {
            for (userID, points) in totals where points == best {
                addEvent(
                    groupID: groupID,
                    weekID: week.id,
                    userID: userID,
                    kind: .weeklyWinner,
                    points: 50,
                    at: week.endsAt
                )
            }
        }

        for userID in memberIDs[groupID] ?? [] {
            let streak = streak(userID: userID, groupID: groupID, upTo: week)
            guard streak >= 2 else { continue }
            addEvent(
                groupID: groupID,
                weekID: week.id,
                userID: userID,
                kind: .streak,
                points: 5 * min(streak, 10),
                at: week.endsAt
            )
        }
    }

    /// The leaderboard of a group: the sum of the point ledger.
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

    // MARK: - Helpers

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
