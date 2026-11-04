import Foundation

enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case patch = "PATCH"
    case delete = "DELETE"
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
    static let me = Endpoint(method: .get, path: "/me")
    static let updateMe = Endpoint(method: .patch, path: "/me")
    static let deleteMe = Endpoint(method: .delete, path: "/me")
    static let registerDevice = Endpoint(method: .post, path: "/devices")

    // MARK: Groups

    static let groups = Endpoint(method: .get, path: "/groups")
    static let createGroup = Endpoint(method: .post, path: "/groups")
    static let joinGroup = Endpoint(method: .post, path: "/groups/join")

    static func group(_ id: String) -> Endpoint {
        Endpoint(method: .get, path: "/groups/\(id)")
    }

    static func updateGroup(_ id: String) -> Endpoint {
        Endpoint(method: .patch, path: "/groups/\(id)")
    }

    static func leaveGroup(_ id: String) -> Endpoint {
        Endpoint(method: .post, path: "/groups/\(id)/leave")
    }

    static func groupWeek(_ id: String) -> Endpoint {
        Endpoint(method: .get, path: "/groups/\(id)/week")
    }

    static func groupFeed(_ id: String, cursor: String? = nil) -> Endpoint {
        var query: [URLQueryItem] = []
        if let cursor, !cursor.isEmpty {
            query.append(URLQueryItem(name: "cursor", value: cursor))
        }
        return Endpoint(method: .get, path: "/groups/\(id)/feed", query: query)
    }

    /// Pending submissions of the group that still need my vote.
    static func groupPendingVotes(_ id: String) -> Endpoint {
        Endpoint(method: .get, path: "/groups/\(id)/votes/pending")
    }

    static func groupLeaderboard(_ id: String, scope: LeaderboardScope) -> Endpoint {
        Endpoint(
            method: .get,
            path: "/groups/\(id)/leaderboard",
            query: [URLQueryItem(name: "scope", value: scope.rawValue)]
        )
    }

    // MARK: Submissions

    static func createSubmission(challengeID: String) -> Endpoint {
        Endpoint(method: .post, path: "/challenges/\(challengeID)/submissions")
    }

    static func submission(_ id: String) -> Endpoint {
        Endpoint(method: .get, path: "/submissions/\(id)")
    }

    static func vote(_ id: String) -> Endpoint {
        Endpoint(method: .post, path: "/submissions/\(id)/vote")
    }

    static func media(_ key: String) -> Endpoint {
        Endpoint(method: .get, path: "/media/\(key)")
    }
}
