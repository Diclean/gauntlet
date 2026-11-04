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

    init(id: String, displayName: String, avatarEmoji: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.avatarEmoji = avatarEmoji
    }

    private enum CodingKeys: String, CodingKey {
        case id, displayName, avatarEmoji
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        avatarEmoji = try container.decodeIfPresent(String.self, forKey: .avatarEmoji)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encodeIfPresent(avatarEmoji, forKey: .avatarEmoji)
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

    private enum CodingKeys: String, CodingKey {
        case id, name, inviteCode, challengesPerWeek, theme, language, timezone, ownerId, memberCount
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
        memberCount: Int
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
    }
}

struct Member: Codable, Identifiable, Hashable, Sendable {
    let user: User
    let joinedAt: Date

    var id: String { user.id }
}

struct Week: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let startsAt: Date
    let endsAt: Date
    let voteDeadline: Date
    let status: WeekStatus
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

    private enum CodingKeys: String, CodingKey {
        case id, title, description, difficulty, points, position, myStatus, acceptedCount
    }

    init(
        id: String,
        title: String,
        description: String,
        difficulty: Difficulty,
        points: Int,
        position: Int,
        myStatus: MyChallengeStatus,
        acceptedCount: Int
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.difficulty = difficulty
        self.points = points
        self.position = position
        self.myStatus = myStatus
        self.acceptedCount = acceptedCount
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

    /// Number of approvals needed for the submission to be accepted (`min(2, N)`).
    var approvalsNeeded: Int { min(2, eligibleVoters) }

    /// Number of rejections needed for the submission to be rejected (`ceil(N / 2)`).
    var rejectionsNeeded: Int { Int(ceil(Double(eligibleVoters) / 2.0)) }

    var isSoloGroup: Bool { eligibleVoters == 0 }
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

    init(
        name: String? = nil,
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
