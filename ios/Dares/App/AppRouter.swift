import Foundation
import Observation

enum AppRoute: Hashable, Sendable {
    case group(String)
}

/// The identifiers that come from outside the app — push payloads, invite links —
/// are checked before they are used.
///
/// Only letters, digits, `_` and `-` are allowed, with 1 to 64 characters. An id
/// with a slash, a dot or a space never reaches the router and never reaches a path
/// of the API (SPEC.md, section 2 — the ids of the API are untrusted input).
enum SafeIdentifier {
    /// The longest id the API can have.
    static let maxLength = 64

    private static let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")

    /// True when the value may be used as an id.
    static func isValid(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= maxLength else { return false }
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// The value when it is safe — `nil` otherwise.
    static func valid(_ value: String?) -> String? {
        guard let value, isValid(value) else { return nil }
        return value
    }
}

/// Navigation state owned by `AppState`.
@MainActor
@Observable
final class AppRouter {
    var path: [AppRoute] = []
    /// Set when a push notification points at a specific submission.
    var pendingSubmissionID: String?
    /// Set when an invite link (`gauntlet://join/<code>`) opens the app.
    var pendingInviteCode: String?

    func open(groupID: String, submissionID: String? = nil) {
        // A hostile id never reaches the navigation stack.
        guard let groupID = SafeIdentifier.valid(groupID) else { return }
        pendingSubmissionID = SafeIdentifier.valid(submissionID)
        path = [.group(groupID)]
    }
}

/// Receives push payloads (deep links) from the notification delegate.
@MainActor
final class DeepLinkRouter {
    static let shared = DeepLinkRouter()

    var handler: ((String?, String?) -> Void)?

    func handle(groupID: String?, submissionID: String?) {
        // The ids of a push payload are untrusted: only a well formed one is routed.
        handler?(SafeIdentifier.valid(groupID), SafeIdentifier.valid(submissionID))
    }
}

/// Holds the APNs device token once the system hands it over.
actor PushTokenStore {
    static let shared = PushTokenStore()

    private var token: String?

    func set(_ newToken: String) {
        token = newToken
    }

    func currentToken() -> String? {
        token
    }
}
