import Foundation
import Observation

enum AppRoute: Hashable, Sendable {
    case group(String)
}

/// Navigation state owned by `AppState`.
@MainActor
@Observable
final class AppRouter {
    var path: [AppRoute] = []
    /// Set when a push notification points at a specific submission.
    var pendingSubmissionID: String?

    func open(groupID: String, submissionID: String? = nil) {
        pendingSubmissionID = submissionID
        path = [.group(groupID)]
    }
}

/// Receives push payloads (deep links) from the notification delegate.
@MainActor
final class DeepLinkRouter {
    static let shared = DeepLinkRouter()

    var handler: ((String?, String?) -> Void)?

    func handle(groupID: String?, submissionID: String?) {
        handler?(groupID, submissionID)
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
