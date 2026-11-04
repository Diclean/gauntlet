import Foundation

// MARK: - Enumerations

enum Difficulty: String, Codable, CaseIterable, Identifiable, Sendable {
    case easy
    case medium
    case hard

    var id: String { rawValue }
}

enum MyChallengeStatus: String, Codable, CaseIterable, Sendable {
    case todo
    case pending
    case accepted
    case rejected
}

enum SubmissionStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case accepted
    case rejected
    case expired
    /// The proof was removed after reports (v3, SPEC.md section 6.2).
    case removed
}

enum MediaType: String, Codable, CaseIterable, Sendable {
    case photo
    case video
}

enum WeekStatus: String, Codable, Sendable {
    case open
    case closed
}

enum LeaderboardScope: String, Codable, CaseIterable, Identifiable, Sendable {
    case week
    case all

    var id: String { rawValue }
}

// MARK: - Models

struct User: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let avatarEmoji: String?
    /// True when the player accepted the house rules (v3, SPEC.md section 6.1).
    /// The API only sends it for `/me`, so it is `false` everywhere else.
    let termsAccepted: Bool

    init(id: String, displayName: String, avatarEmoji: String? = nil, termsAccepted: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.avatarEmoji = avatarEmoji
        self.termsAccepted = termsAccepted
    }

    private enum CodingKeys: String, CodingKey {
        case id, displayName, avatarEmoji, termsAccepted
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        avatarEmoji = try container.decodeIfPresent(String.self, forKey: .avatarEmoji)
        termsAccepted = try container.decodeIfPresent(Bool.self, forKey: .termsAccepted) ?? false
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encodeIfPresent(avatarEmoji, forKey: .avatarEmoji)
        try container.encode(termsAccepted, forKey: .termsAccepted)
    }
}

struct Group: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let inviteCode: String
    let challengesPerWeek: Int
    let theme: String?
    let language: String
    let timezone: String
    let ownerId: String
    let memberCount: Int
    /// What the club of the relegation zone buys (v2, SPEC.md section 5). Display only.
    let forfeit: String
    /// The link that opens the join confirmation screen (v3, SPEC.md section 6.8).
    let inviteUrl: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, inviteCode, challengesPerWeek, theme, language, timezone, ownerId, memberCount
        case forfeit, inviteUrl
    }

    init(
        id: String,
        name: String,
        inviteCode: String,
        challengesPerWeek: Int,
        theme: String? = nil,
        language: String = "en",
        timezone: String,
        ownerId: String,
        memberCount: Int,
        forfeit: String = Group.defaultForfeit,
        inviteUrl: String? = nil
    ) {
        self.id = id
        self.name = name
        self.inviteCode = inviteCode
        self.challengesPerWeek = challengesPerWeek
        self.theme = theme
        self.language = language
        self.timezone = timezone
        self.ownerId = ownerId
        self.memberCount = memberCount
        self.forfeit = forfeit
        self.inviteUrl = inviteUrl
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        inviteCode = try container.decode(String.self, forKey: .inviteCode)
        challengesPerWeek = try container.decodeIfPresent(Int.self, forKey: .challengesPerWeek) ?? 5
        theme = try container.decodeIfPresent(String.self, forKey: .theme)
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? "en"
        timezone = try container.decodeIfPresent(String.self, forKey: .timezone) ?? TimeZone.current.identifier
        ownerId = try container.decodeIfPresent(String.self, forKey: .ownerId) ?? ""
        memberCount = try container.decodeIfPresent(Int.self, forKey: .memberCount) ?? 0
        forfeit = try container.decodeIfPresent(String.self, forKey: .forfeit) ?? Group.defaultForfeit
        inviteUrl = try container.decodeIfPresent(String.self, forKey: .inviteUrl)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(inviteCode, forKey: .inviteCode)
        try container.encode(challengesPerWeek, forKey: .challengesPerWeek)
        try container.encodeIfPresent(theme, forKey: .theme)
        try container.encode(language, forKey: .language)
        try container.encode(timezone, forKey: .timezone)
        try container.encode(ownerId, forKey: .ownerId)
        try container.encode(memberCount, forKey: .memberCount)
        try container.encode(forfeit, forKey: .forfeit)
        try container.encodeIfPresent(inviteUrl, forKey: .inviteUrl)
    }

    /// The forfeit of a club that never set one (SPEC.md, section 5).
    static let defaultForfeit = "Buys the round 🍺"
}

struct Member: Codable, Identifiable, Hashable, Sendable {
    let user: User
    let joinedAt: Date

    var id: String { user.id }
}

struct Week: Codable, Identifiable, Hashable, Sendable {
    let id: String
    /// The 1-based index of the matchweek since the club was created (v2).
    let number: Int
    let startsAt: Date
    let endsAt: Date
    let voteDeadline: Date
    let status: WeekStatus
    /// The fixture I chose as my captain fixture (v3, SPEC.md section 6.6).
    let myCaptainChallengeId: String?
    /// How many of the two replacements of the matchweek are used (v3).
    let vetoesUsed: Int

    init(
        id: String,
        number: Int,
        startsAt: Date,
        endsAt: Date,
        voteDeadline: Date,
        status: WeekStatus,
        myCaptainChallengeId: String? = nil,
        vetoesUsed: Int = 0
    ) {
        self.id = id
        self.number = number
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.voteDeadline = voteDeadline
        self.status = status
        self.myCaptainChallengeId = myCaptainChallengeId
        self.vetoesUsed = vetoesUsed
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        number = try container.decodeIfPresent(Int.self, forKey: .number) ?? 1
        startsAt = try container.decode(Date.self, forKey: .startsAt)
        endsAt = try container.decode(Date.self, forKey: .endsAt)
        voteDeadline = try container.decodeIfPresent(Date.self, forKey: .voteDeadline) ?? endsAt
        status = try container.decodeIfPresent(WeekStatus.self, forKey: .status) ?? .open
        myCaptainChallengeId = try container.decodeIfPresent(String.self, forKey: .myCaptainChallengeId)
        vetoesUsed = try container.decodeIfPresent(Int.self, forKey: .vetoesUsed) ?? 0
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(number, forKey: .number)
        try container.encode(startsAt, forKey: .startsAt)
        try container.encode(endsAt, forKey: .endsAt)
        try container.encode(voteDeadline, forKey: .voteDeadline)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(myCaptainChallengeId, forKey: .myCaptainChallengeId)
        try container.encode(vetoesUsed, forKey: .vetoesUsed)
    }

    private enum CodingKeys: String, CodingKey {
        case id, number, startsAt, endsAt, voteDeadline, status, myCaptainChallengeId, vetoesUsed
    }
}

struct Challenge: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let description: String
    let difficulty: Difficulty
    let points: Int
    let position: Int
    let myStatus: MyChallengeStatus
    let acceptedCount: Int
    /// How many members vetoed this fixture (v3, SPEC.md section 6.3).
    let vetoCount: Int
    /// How many vetoes replace the fixture (half of the club, rounded up).
    let vetoThreshold: Int
    /// True when the signed in player vetoed this fixture.
    let myVeto: Bool
    /// True for the first 24 hours of a fixture that replaced another one.
    let isNew: Bool
    /// True when a member of the club wrote this fixture.
    let isHouse: Bool
    /// The member that wrote the fixture — `nil` for the fixtures of the AI.
    let createdBy: User?
    /// True when this fixture is my captain fixture.
    let isCaptain: Bool

    private enum CodingKeys: String, CodingKey {
        case id, title, description, difficulty, points, position, myStatus, acceptedCount
        case vetoCount, vetoThreshold, myVeto, isNew, isHouse, createdBy, isCaptain
    }

    init(
        id: String,
        title: String,
        description: String,
        difficulty: Difficulty,
        points: Int,
        position: Int,
        myStatus: MyChallengeStatus,
        acceptedCount: Int,
        vetoCount: Int = 0,
        vetoThreshold: Int = 0,
        myVeto: Bool = false,
        isNew: Bool = false,
        isHouse: Bool = false,
        createdBy: User? = nil,
        isCaptain: Bool = false
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.difficulty = difficulty
        self.points = points
        self.position = position
        self.myStatus = myStatus
        self.acceptedCount = acceptedCount
        self.vetoCount = vetoCount
        self.vetoThreshold = vetoThreshold
        self.myVeto = myVeto
        self.isNew = isNew
        self.isHouse = isHouse
        self.createdBy = createdBy
        self.isCaptain = isCaptain
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        difficulty = try container.decodeIfPresent(Difficulty.self, forKey: .difficulty) ?? .easy
        points = try container.decodeIfPresent(Int.self, forKey: .points) ?? 10
        position = try container.decodeIfPresent(Int.self, forKey: .position) ?? 0
        myStatus = try container.decodeIfPresent(MyChallengeStatus.self, forKey: .myStatus) ?? .todo
        acceptedCount = try container.decodeIfPresent(Int.self, forKey: .acceptedCount) ?? 0
        vetoCount = try container.decodeIfPresent(Int.self, forKey: .vetoCount) ?? 0
        vetoThreshold = try container.decodeIfPresent(Int.self, forKey: .vetoThreshold) ?? 0
        myVeto = try container.decodeIfPresent(Bool.self, forKey: .myVeto) ?? false
        isNew = try container.decodeIfPresent(Bool.self, forKey: .isNew) ?? false
        isHouse = try container.decodeIfPresent(Bool.self, forKey: .isHouse) ?? false
        createdBy = try container.decodeIfPresent(User.self, forKey: .createdBy)
        isCaptain = try container.decodeIfPresent(Bool.self, forKey: .isCaptain) ?? false
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(description, forKey: .description)
        try container.encode(difficulty, forKey: .difficulty)
        try container.encode(points, forKey: .points)
        try container.encode(position, forKey: .position)
        try container.encode(myStatus, forKey: .myStatus)
        try container.encode(acceptedCount, forKey: .acceptedCount)
        try container.encode(vetoCount, forKey: .vetoCount)
        try container.encode(vetoThreshold, forKey: .vetoThreshold)
        try container.encode(myVeto, forKey: .myVeto)
        try container.encode(isNew, forKey: .isNew)
        try container.encode(isHouse, forKey: .isHouse)
        try container.encodeIfPresent(createdBy, forKey: .createdBy)
        try container.encode(isCaptain, forKey: .isCaptain)
    }
}

/// The spec names this shape `ChallengeWithMyStatus`.
typealias ChallengeWithMyStatus = Challenge

struct Submission: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let challengeId: String
    let challengeTitle: String
    let user: User
    let mediaUrl: String
    let mediaType: MediaType
    let caption: String?
    let status: SubmissionStatus
    let approvals: Int
    let rejections: Int
    let eligibleVoters: Int
    let myVote: Bool?
    let createdAt: Date
    let decidedAt: Date?
    /// The members that called this proof. The API may leave them out.
    let voters: [User]?
    /// The reactions of the banter (v3, SPEC.md section 6.5).
    let reactions: [Reaction]
    /// How many comments the proof has.
    let commentCount: Int

    /// Number of approvals needed for the submission to be accepted (`min(2, N)`).
    var approvalsNeeded: Int { min(2, eligibleVoters) }

    /// Number of rejections needed for the submission to be rejected (`ceil(N / 2)`).
    var rejectionsNeeded: Int { Int(ceil(Double(eligibleVoters) / 2.0)) }

    var isSoloGroup: Bool { eligibleVoters == 0 }

    private enum CodingKeys: String, CodingKey {
        case id, challengeId, challengeTitle, user, mediaUrl, mediaType, caption, status
        case approvals, rejections, eligibleVoters, myVote, createdAt, decidedAt, voters
        case reactions, commentCount
    }

    init(
        id: String,
        challengeId: String,
        challengeTitle: String,
        user: User,
        mediaUrl: String,
        mediaType: MediaType,
        caption: String?,
        status: SubmissionStatus,
        approvals: Int,
        rejections: Int,
        eligibleVoters: Int,
        myVote: Bool?,
        createdAt: Date,
        decidedAt: Date?,
        voters: [User]? = nil,
        reactions: [Reaction] = [],
        commentCount: Int = 0
    ) {
        self.id = id
        self.challengeId = challengeId
        self.challengeTitle = challengeTitle
        self.user = user
        self.mediaUrl = mediaUrl
        self.mediaType = mediaType
        self.caption = caption
        self.status = status
        self.approvals = approvals
        self.rejections = rejections
        self.eligibleVoters = eligibleVoters
        self.myVote = myVote
        self.createdAt = createdAt
        self.decidedAt = decidedAt
        self.voters = voters
        self.reactions = reactions
        self.commentCount = commentCount
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        challengeId = try container.decode(String.self, forKey: .challengeId)
        challengeTitle = try container.decode(String.self, forKey: .challengeTitle)
        user = try container.decode(User.self, forKey: .user)
        mediaUrl = try container.decode(String.self, forKey: .mediaUrl)
        mediaType = try container.decodeIfPresent(MediaType.self, forKey: .mediaType) ?? .photo
        caption = try container.decodeIfPresent(String.self, forKey: .caption)
        status = try container.decodeIfPresent(SubmissionStatus.self, forKey: .status) ?? .pending
        approvals = try container.decodeIfPresent(Int.self, forKey: .approvals) ?? 0
        rejections = try container.decodeIfPresent(Int.self, forKey: .rejections) ?? 0
        eligibleVoters = try container.decodeIfPresent(Int.self, forKey: .eligibleVoters) ?? 0
        myVote = try container.decodeIfPresent(Bool.self, forKey: .myVote)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        decidedAt = try container.decodeIfPresent(Date.self, forKey: .decidedAt)
        voters = try container.decodeIfPresent([User].self, forKey: .voters)
        reactions = try container.decodeIfPresent([Reaction].self, forKey: .reactions) ?? []
        commentCount = try container.decodeIfPresent(Int.self, forKey: .commentCount) ?? 0
    }
}

struct LeaderboardEntry: Codable, Identifiable, Hashable, Sendable {
    let user: User
    let points: Int
    let rank: Int
    let streak: Int

    var id: String { user.id }
}

// MARK: - Request bodies

struct AppleAuthRequest: Codable, Sendable {
    let identityToken: String
    let nonce: String
    let displayName: String?
}

struct UpdateMeRequest: Codable, Sendable {
    let displayName: String?
    let avatarEmoji: String?

    init(displayName: String? = nil, avatarEmoji: String? = nil) {
        self.displayName = displayName
        self.avatarEmoji = avatarEmoji
    }
}

struct CreateGroupRequest: Codable, Sendable {
    let name: String
    let challengesPerWeek: Int?
    let theme: String?
    let language: String?
    let timezone: String?

    init(
        name: String,
        challengesPerWeek: Int? = nil,
        theme: String? = nil,
        language: String? = nil,
        timezone: String? = nil
    ) {
        self.name = name
        self.challengesPerWeek = challengesPerWeek
        self.theme = theme
        self.language = language
        self.timezone = timezone
    }
}

struct UpdateGroupRequest: Codable, Sendable {
    let name: String?
    let challengesPerWeek: Int?
    let theme: String?
    let language: String?
    let timezone: String?
    /// The forfeit of the club — what the relegation zone buys (v2).
    let forfeit: String?

    init(
        name: String? = nil,
        challengesPerWeek: Int? = nil,
        theme: String? = nil,
        language: String? = nil,
        timezone: String? = nil,
        forfeit: String? = nil
    ) {
        self.name = name
        self.challengesPerWeek = challengesPerWeek
        self.theme = theme
        self.language = language
        self.timezone = timezone
        self.forfeit = forfeit
    }
}

struct JoinGroupRequest: Codable, Sendable {
    let inviteCode: String
}

struct VoteRequest: Codable, Sendable {
    let approve: Bool
}

struct DeviceRequest: Codable, Sendable {
    let apnsToken: String
}

// MARK: - Response envelopes

struct HealthResponse: Codable, Sendable {
    let ok: Bool
}

struct AuthResponse: Codable, Sendable {
    let token: String
    let user: User
}

struct MeResponse: Codable, Sendable {
    let user: User
}

struct OKResponse: Codable, Sendable {
    let ok: Bool
}

struct GroupsResponse: Codable, Sendable {
    let groups: [Group]
}

struct GroupResponse: Codable, Sendable {
    let group: Group
}

struct GroupDetailResponse: Codable, Sendable {
    let group: Group
    let members: [Member]
}

struct WeekResponse: Codable, Sendable {
    let week: Week
    let challenges: [Challenge]
    /// The house fixture of the matchweek (v3, SPEC.md section 6.7).
    let houseFixture: HouseFixtureInfo?

    init(week: Week, challenges: [Challenge], houseFixture: HouseFixtureInfo? = nil) {
        self.week = week
        self.challenges = challenges
        self.houseFixture = houseFixture
    }

    private enum CodingKeys: String, CodingKey {
        case week, challenges, houseFixture
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        week = try container.decode(Week.self, forKey: .week)
        challenges = try container.decodeIfPresent([Challenge].self, forKey: .challenges) ?? []
        houseFixture = try container.decodeIfPresent(HouseFixtureInfo.self, forKey: .houseFixture)
    }
}

struct FeedResponse: Codable, Sendable {
    let items: [Submission]
    let nextCursor: String?
}

/// `GET /groups/:id/votes/pending` — pending submissions of others that I have not voted on.
struct PendingVotesResponse: Codable, Sendable {
    let items: [Submission]
}

struct LeaderboardResponse: Codable, Sendable {
    let entries: [LeaderboardEntry]
}

struct SubmissionResponse: Codable, Sendable {
    let submission: Submission
}

struct APIErrorPayload: Codable, Sendable {
    let code: String
    let message: String
}

struct APIErrorEnvelope: Codable, Sendable {
    let error: APIErrorPayload
}
