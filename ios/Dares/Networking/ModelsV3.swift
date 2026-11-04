import Foundation

// MARK: - v3 models (SPEC.md, section 6 — "safety, banter, captain, house fixture")
//
// Every new field is optional or has a default, so the payloads of an older server
// still decode. The client never breaks when the backend is one version behind.

// MARK: - Reactions

/// The six reactions of the banter (SPEC.md, section 6.5). The API sends the emoji as
/// a string, so the raw value of the enum is the emoji itself.
enum ReactionEmoji: String, Codable, CaseIterable, Identifiable, Sendable {
    case fire = "🔥"
    case joy = "😂"
    case clown = "🤡"
    case goat = "🐐"
    case wow = "😮"
    case clap = "👏"

    var id: String { rawValue }

    /// The fixed order of the spec: `🔥 😂 🤡 🐐 😮 👏`.
    static let displayOrder: [ReactionEmoji] = [.fire, .joy, .clown, .goat, .wow, .clap]
}

/// One reaction of a proof: how many members used it and whether I did.
struct Reaction: Codable, Identifiable, Hashable, Sendable {
    let emoji: String
    let count: Int
    /// True when the signed in player used this reaction.
    let mine: Bool

    var id: String { emoji }

    /// The emoji as a reaction of the house — `nil` when the server sends something else.
    var reaction: ReactionEmoji? { ReactionEmoji(rawValue: emoji) }
}

// MARK: - Comments

/// One comment of the banter (SPEC.md, section 6.5).
struct Comment: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let user: User
    let text: String
    let createdAt: Date
    /// The author of the comment or the owner of the club may delete it.
    let canDelete: Bool
}

// MARK: - Reports

/// The six reasons of a report (SPEC.md, section 6.2).
enum ReportReason: String, Codable, CaseIterable, Identifiable, Sendable {
    case nudity
    case violence
    case harassment
    case dangerous
    case spam
    case other

    var id: String { rawValue }

    /// The label of the reason on the square row of the reason sheet.
    var title: String {
        switch self {
        case .nudity: "Nudity"
        case .violence: "Violence"
        case .harassment: "Harassment"
        case .dangerous: "Dangerous stunt"
        case .spam: "Spam"
        case .other: "Something else"
        }
    }
}

/// `POST /submissions/:id/report` and `POST /comments/:id/report`.
struct ReportRequest: Codable, Sendable {
    let reason: ReportReason
    let note: String?

    init(reason: ReportReason, note: String? = nil) {
        self.reason = reason
        self.note = note
    }
}

// MARK: - Notification preferences

/// `GET /me/notification-prefs` (SPEC.md, section 6.4). Every switch is on by default.
struct NotificationPrefs: Codable, Hashable, Sendable {
    var newWeek: Bool
    var voteNeeded: Bool
    var result: Bool
    var deadline: Bool
    var awards: Bool
    var banter: Bool

    init(
        newWeek: Bool = true,
        voteNeeded: Bool = true,
        result: Bool = true,
        deadline: Bool = true,
        awards: Bool = true,
        banter: Bool = true
    ) {
        self.newWeek = newWeek
        self.voteNeeded = voteNeeded
        self.result = result
        self.deadline = deadline
        self.awards = awards
        self.banter = banter
    }

    private enum CodingKeys: String, CodingKey {
        case newWeek, voteNeeded, result, deadline, awards, banter
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        newWeek = try container.decodeIfPresent(Bool.self, forKey: .newWeek) ?? true
        voteNeeded = try container.decodeIfPresent(Bool.self, forKey: .voteNeeded) ?? true
        result = try container.decodeIfPresent(Bool.self, forKey: .result) ?? true
        deadline = try container.decodeIfPresent(Bool.self, forKey: .deadline) ?? true
        awards = try container.decodeIfPresent(Bool.self, forKey: .awards) ?? true
        banter = try container.decodeIfPresent(Bool.self, forKey: .banter) ?? true
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(newWeek, forKey: .newWeek)
        try container.encode(voteNeeded, forKey: .voteNeeded)
        try container.encode(result, forKey: .result)
        try container.encode(deadline, forKey: .deadline)
        try container.encode(awards, forKey: .awards)
        try container.encode(banter, forKey: .banter)
    }
}

// MARK: - House fixture

/// `GET /groups/:id/week` → `houseFixture` (SPEC.md, section 6.7).
struct HouseFixtureInfo: Codable, Hashable, Sendable {
    /// True when the signed in player may add the house fixture of this matchweek.
    let allowed: Bool
    /// Wednesday 23:59 of the matchweek, in the time zone of the club.
    let deadline: Date
    /// The member that wrote the house fixture — `nil` when there is none yet.
    let author: User?

    init(allowed: Bool, deadline: Date, author: User? = nil) {
        self.allowed = allowed
        self.deadline = deadline
        self.author = author
    }
}

// MARK: - Veto

/// `POST /challenges/:id/veto` (SPEC.md, section 6.3).
struct VetoResponse: Codable, Sendable {
    /// The fixture after the call — the replacement when it was replaced.
    let challenge: Challenge
    /// True when the veto replaced the fixture.
    let replaced: Bool
}

// MARK: - Captain

/// `PUT /groups/:id/week/captain` (SPEC.md, section 6.6).
struct CaptainResponse: Codable, Sendable {
    /// The matchweek with the captain fixture of the player.
    let week: Week?
    /// The captain fixture itself.
    let challenge: Challenge?

    init(week: Week? = nil, challenge: Challenge? = nil) {
        self.week = week
        self.challenge = challenge
    }
}

// MARK: - Blocks

/// `GET /me/blocks` (SPEC.md, section 6.2).
struct BlocksResponse: Codable, Sendable {
    let users: [User]

    init(users: [User]) {
        self.users = users
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        users = try container.decodeIfPresent([User].self, forKey: .users) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case users
    }
}

// MARK: - Bans

/// A member that the owner of the club removed (SPEC.md, section 6.2).
///
/// The API sends the user of the ban with the moment of the ban:
/// `{users:[User & {bannedAt:number}]}` (SPEC.md, section 6.9).
struct BannedMember: Codable, Identifiable, Hashable, Sendable {
    let user: User
    /// When the owner removed the member from the club.
    let bannedAt: Date

    var id: String { user.id }

    init(user: User, bannedAt: Date) {
        self.user = user
        self.bannedAt = bannedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, displayName, avatarEmoji, bannedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        user = User(
            id: try container.decode(String.self, forKey: .id),
            displayName: try container.decodeIfPresent(String.self, forKey: .displayName) ?? "",
            avatarEmoji: try container.decodeIfPresent(String.self, forKey: .avatarEmoji)
        )
        bannedAt = try container.decodeIfPresent(Date.self, forKey: .bannedAt)
            ?? Date(timeIntervalSince1970: 0)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(user.id, forKey: .id)
        try container.encode(user.displayName, forKey: .displayName)
        try container.encodeIfPresent(user.avatarEmoji, forKey: .avatarEmoji)
        try container.encode(bannedAt, forKey: .bannedAt)
    }
}

/// `GET /groups/:id/bans` — `{users:[User & {bannedAt}]}` (SPEC.md, section 6.9).
struct BannedMembersResponse: Decodable, Sendable {
    let users: [BannedMember]

    init(users: [BannedMember]) {
        self.users = users
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let users = try container.decodeIfPresent([BannedMember].self, forKey: .users) {
            self.users = users
        } else {
            // An older server sent `{bans:[{user, createdAt}]}` — the app still reads it.
            let legacy = try container.decodeIfPresent([LegacyBan].self, forKey: .bans) ?? []
            self.users = legacy.map { BannedMember(user: $0.user, bannedAt: $0.createdAt) }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case users, bans
    }
}

/// The shape of the bans of an older server.
private struct LegacyBan: Decodable {
    let user: User
    let createdAt: Date
}

// MARK: - Invite link

/// `GET /join/:code` — the preview of the club behind an invite code. The app never
/// joins on its own: it shows the confirmation screen (SPEC.md, section 6.8).
struct JoinPreviewResponse: Codable, Sendable {
    let group: Group

    init(group: Group) {
        self.group = group
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        group = try container.decode(Group.self, forKey: .group)
    }

    private enum CodingKeys: String, CodingKey {
        case group
    }
}

// MARK: - Response envelopes

/// `GET /submissions/:id/comments` → `{comments:[Comment]}`.
struct CommentsResponse: Codable, Sendable {
    let comments: [Comment]

    init(comments: [Comment]) {
        self.comments = comments
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        comments = try container.decodeIfPresent([Comment].self, forKey: .comments) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case comments
    }
}

/// `POST /submissions/:id/comments` → `{comment:Comment}`.
struct CommentResponse: Codable, Sendable {
    let comment: Comment

    init(comment: Comment) {
        self.comment = comment
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        comment = try container.decode(Comment.self, forKey: .comment)
    }

    private enum CodingKeys: String, CodingKey {
        case comment
    }
}

/// `POST /groups/:id/week/house-fixture` → `{challenge:Challenge}`.
struct ChallengeResponse: Codable, Sendable {
    let challenge: Challenge

    init(challenge: Challenge) {
        self.challenge = challenge
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        challenge = try container.decode(Challenge.self, forKey: .challenge)
    }

    private enum CodingKeys: String, CodingKey {
        case challenge
    }
}

// MARK: - Request bodies

/// `POST /submissions/:id/reactions` — the emoji toggles my reaction.
struct ReactionRequest: Codable, Sendable {
    let emoji: String

    init(emoji: String) {
        self.emoji = emoji
    }
}

/// `POST /submissions/:id/comments`.
struct CommentRequest: Codable, Sendable {
    let text: String

    init(text: String) {
        self.text = text
    }
}

/// `POST /groups/:id/week/house-fixture`.
struct HouseFixtureRequest: Codable, Sendable {
    let title: String
    let description: String
    let difficulty: Difficulty

    init(title: String, description: String, difficulty: Difficulty) {
        self.title = title
        self.description = description
        self.difficulty = difficulty
    }
}

/// `PUT /groups/:id/week/captain`.
struct CaptainRequest: Codable, Sendable {
    let challengeId: String

    init(challengeId: String) {
        self.challengeId = challengeId
    }
}
