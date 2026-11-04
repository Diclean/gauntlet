import Foundation

enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case patch = "PATCH"
    case put = "PUT"
    case delete = "DELETE"
}

/// Percent-encodes the ids that go into a path.
///
/// Every id of the API is untrusted input: it may come from a push payload, an
/// invite link or a server response. Encoding it keeps it inside its own path
/// segment — a `../` or a `?` in an id can never rewrite the request.
enum PathComponent {
    /// The characters that may stay as they are: letters, digits, `-`, `.`, `_` and `~`.
    static let allowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    /// Percent-encodes every segment of a path and keeps the slashes.
    static func encodePath(_ path: String) -> String {
        path
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { encode(String($0)) }
            .joined(separator: "/")
    }
}

struct Endpoint: Sendable {
    let method: HTTPMethod
    let path: String
    let query: [URLQueryItem]
    let requiresAuth: Bool

    init(method: HTTPMethod, path: String, query: [URLQueryItem] = [], requiresAuth: Bool = true) {
        self.method = method
        self.path = path
        self.query = query
        self.requiresAuth = requiresAuth
    }

    // MARK: Auth & account

    static let health = Endpoint(method: .get, path: "/health", requiresAuth: false)
    static let appleAuth = Endpoint(method: .post, path: "/auth/apple", requiresAuth: false)
    /// `POST /auth/logout` — deletes the session of the bearer token (SPEC.md, section 3).
    static let logout = Endpoint(method: .post, path: "/auth/logout")
    static let me = Endpoint(method: .get, path: "/me")
    static let updateMe = Endpoint(method: .patch, path: "/me")
    static let deleteMe = Endpoint(method: .delete, path: "/me")
    static let registerDevice = Endpoint(method: .post, path: "/devices")

    // MARK: Groups

    static let groups = Endpoint(method: .get, path: "/groups")
    static let createGroup = Endpoint(method: .post, path: "/groups")
    static let joinGroup = Endpoint(method: .post, path: "/groups/join")

    static func group(_ id: String) -> Endpoint {
        Endpoint(method: .get, path: "/groups/\(PathComponent.encode(id))")
    }

    static func updateGroup(_ id: String) -> Endpoint {
        Endpoint(method: .patch, path: "/groups/\(PathComponent.encode(id))")
    }

    static func leaveGroup(_ id: String) -> Endpoint {
        Endpoint(method: .post, path: "/groups/\(PathComponent.encode(id))/leave")
    }

    static func groupWeek(_ id: String) -> Endpoint {
        Endpoint(method: .get, path: "/groups/\(PathComponent.encode(id))/week")
    }

    static func groupFeed(_ id: String, cursor: String? = nil) -> Endpoint {
        var query: [URLQueryItem] = []
        if let cursor, !cursor.isEmpty {
            query.append(URLQueryItem(name: "cursor", value: cursor))
        }
        return Endpoint(method: .get, path: "/groups/\(PathComponent.encode(id))/feed", query: query)
    }

    /// Pending submissions of the group that still need my vote.
    static func groupPendingVotes(_ id: String) -> Endpoint {
        Endpoint(method: .get, path: "/groups/\(PathComponent.encode(id))/votes/pending")
    }

    static func groupLeaderboard(_ id: String, scope: LeaderboardScope) -> Endpoint {
        Endpoint(
            method: .get,
            path: "/groups/\(PathComponent.encode(id))/leaderboard",
            query: [URLQueryItem(name: "scope", value: scope.rawValue)]
        )
    }

    // MARK: v2 — Sunday League

    /// The title race: the cumulative points of every member, matchweek by matchweek.
    static func groupRace(_ id: String) -> Endpoint {
        Endpoint(method: .get, path: "/groups/\(PathComponent.encode(id))/stats/race")
    }

    /// The past matchweeks, newest first.
    static func groupWeeks(_ id: String, limit: Int = 10) -> Endpoint {
        Endpoint(
            method: .get,
            path: "/groups/\(PathComponent.encode(id))/weeks",
            query: [URLQueryItem(name: "limit", value: String(limit))]
        )
    }

    /// The full-time receipt of a matchweek.
    static func groupReceipt(_ id: String, weekID: String) -> Endpoint {
        Endpoint(
            method: .get,
            path: "/groups/\(PathComponent.encode(id))/weeks/\(PathComponent.encode(weekID))/receipt"
        )
    }

    /// The awards of a month (`YYYY-MM`).
    static func groupAwards(_ id: String, month: String?) -> Endpoint {
        var query: [URLQueryItem] = []
        if let month, !month.isEmpty {
            query.append(URLQueryItem(name: "month", value: month))
        }
        return Endpoint(method: .get, path: "/groups/\(PathComponent.encode(id))/awards", query: query)
    }

    /// The months that have awards.
    static func groupAwardMonths(_ id: String) -> Endpoint {
        Endpoint(method: .get, path: "/groups/\(PathComponent.encode(id))/awards/months")
    }

    /// The trophy cabinet of the signed in player.
    static let myTrophies = Endpoint(method: .get, path: "/me/trophies")

    // MARK: Submissions

    static func createSubmission(challengeID: String) -> Endpoint {
        Endpoint(method: .post, path: "/challenges/\(PathComponent.encode(challengeID))/submissions")
    }

    static func submission(_ id: String) -> Endpoint {
        Endpoint(method: .get, path: "/submissions/\(PathComponent.encode(id))")
    }

    static func vote(_ id: String) -> Endpoint {
        Endpoint(method: .post, path: "/submissions/\(PathComponent.encode(id))/vote")
    }

    static func media(_ key: String) -> Endpoint {
        Endpoint(method: .get, path: "/media/\(PathComponent.encode(key))")
    }

    // MARK: v3 — safety, banter, captain, house fixture

    /// The house rules of the player (SPEC.md, section 6.1).
    static let acceptTerms = Endpoint(method: .post, path: "/me/accept-terms")

    /// The push switches of the player (SPEC.md, section 6.4).
    static let notificationPrefs = Endpoint(method: .get, path: "/me/notification-prefs")
    static let updateNotificationPrefs = Endpoint(method: .patch, path: "/me/notification-prefs")

    /// The players the signed in player blocked (SPEC.md, section 6.2).
    static let myBlocks = Endpoint(method: .get, path: "/me/blocks")

    static func blockUser(_ id: String) -> Endpoint {
        Endpoint(method: .post, path: "/users/\(PathComponent.encode(id))/block")
    }

    static func unblockUser(_ id: String) -> Endpoint {
        Endpoint(method: .delete, path: "/users/\(PathComponent.encode(id))/block")
    }

    /// Delete my own proof (SPEC.md, section 6.2).
    static func deleteSubmission(_ id: String) -> Endpoint {
        Endpoint(method: .delete, path: "/submissions/\(PathComponent.encode(id))")
    }

    static func reportSubmission(_ id: String) -> Endpoint {
        Endpoint(method: .post, path: "/submissions/\(PathComponent.encode(id))/report")
    }

    static func reportComment(_ id: String) -> Endpoint {
        Endpoint(method: .post, path: "/comments/\(PathComponent.encode(id))/report")
    }

    static func deleteComment(_ id: String) -> Endpoint {
        Endpoint(method: .delete, path: "/comments/\(PathComponent.encode(id))")
    }

    static func comments(_ submissionID: String) -> Endpoint {
        Endpoint(method: .get, path: "/submissions/\(PathComponent.encode(submissionID))/comments")
    }

    static func addComment(_ submissionID: String) -> Endpoint {
        Endpoint(method: .post, path: "/submissions/\(PathComponent.encode(submissionID))/comments")
    }

    static func reactions(_ submissionID: String) -> Endpoint {
        Endpoint(method: .post, path: "/submissions/\(PathComponent.encode(submissionID))/reactions")
    }

    /// Veto a fixture (SPEC.md, section 6.3).
    static func vetoChallenge(_ id: String) -> Endpoint {
        Endpoint(method: .post, path: "/challenges/\(PathComponent.encode(id))/veto")
    }

    /// Choose the captain fixture of the matchweek (SPEC.md, section 6.6).
    static func setCaptain(groupID: String) -> Endpoint {
        Endpoint(method: .put, path: "/groups/\(PathComponent.encode(groupID))/week/captain")
    }

    /// Write the house fixture of the matchweek (SPEC.md, section 6.7).
    static func addHouseFixture(groupID: String) -> Endpoint {
        Endpoint(method: .post, path: "/groups/\(PathComponent.encode(groupID))/week/house-fixture")
    }

    /// The owner removes a member of the club (SPEC.md, section 6.2).
    static func removeMember(groupID: String, userID: String) -> Endpoint {
        Endpoint(
            method: .post,
            path: "/groups/\(PathComponent.encode(groupID))/members/\(PathComponent.encode(userID))/remove"
        )
    }

    /// The owner lifts the ban of a member (SPEC.md, section 6.2).
    static func unbanMember(groupID: String, userID: String) -> Endpoint {
        Endpoint(
            method: .delete,
            path: "/groups/\(PathComponent.encode(groupID))/members/\(PathComponent.encode(userID))/ban"
        )
    }

    /// The members the owner removed from the club.
    static func bans(groupID: String) -> Endpoint {
        Endpoint(method: .get, path: "/groups/\(PathComponent.encode(groupID))/bans")
    }

    /// The preview of the club behind an invite code (SPEC.md, section 6.9).
    ///
    /// The app asks the API for the normal Group JSON. `GET /join/:code` stays the
    /// HTML page of the browser — it is never called by the app.
    static func joinPreview(code: String) -> Endpoint {
        Endpoint(method: .get, path: "/groups/preview/\(PathComponent.encode(code))")
    }
}
