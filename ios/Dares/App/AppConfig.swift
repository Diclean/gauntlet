import Foundation

/// Runtime configuration read from `Info.plist` (which is filled from the `.xcconfig` files).
enum AppConfig {
    /// The name of the app. It lives in one place: the display name of the bundle and
    /// every place the app names itself (DESIGN.md).
    static let appName = "Gauntlet"

    /// The letters of the crest of the club.
    static let clubInitials = "SL"

    /// The API base URL of the app.
    ///
    /// A release build only talks over https: a plain http URL would send the bearer
    /// token of the player in clear. When the URL of the build is not allowed, the app
    /// fails closed — it points at a host that never resolves and no request leaves
    /// the device.
    static let baseURL: URL = {
        let fallback = requiresHTTPS
            ? URL(string: "https://api.invalid") ?? URL(fileURLWithPath: "/dev/null")
            : URL(string: "http://localhost:8787") ?? URL(fileURLWithPath: "/dev/null")
        guard
            let raw = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
            !raw.isEmpty,
            let url = URL(string: raw),
            url.scheme != nil
        else {
            return fallback
        }
        return isAllowedBaseURL(url) ? url : fallback
    }()

    /// The API base URL as shown in the UI (debug helper).
    static var baseURLDescription: String {
        baseURL.absoluteString
    }

    /// True when a release build has to refuse a plain http API.
    static var requiresHTTPS: Bool {
        #if DEBUG
        return false
        #else
        return true
        #endif
    }

    /// True when the app may talk to this URL.
    ///
    /// https is always allowed. http is only allowed in a debug build, where the API
    /// runs on the laptop of the developer.
    static func isAllowedBaseURL(_ url: URL, requiresHTTPS: Bool = AppConfig.requiresHTTPS) -> Bool {
        switch url.scheme?.lowercased() {
        case "https":
            return true
        case "http":
            return !requiresHTTPS
        default:
            return false
        }
    }

    /// True while the unit tests of the app run. The tests never ask for the
    /// permission of the notifications: the dialog of the system would block them.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// `-demo` starts the app in the offline demo mode (DESIGN.md, section 9).
    ///
    /// The launch argument is a developer tool: it only exists in a debug build. The
    /// demo itself stays reachable in every build through the "Try the demo" button.
    static var isDemoLaunchArgument: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-demo")
        #else
        return false
        #endif
    }

    /// `-demo-sim-delay <seconds>` changes how long the demo waits before the club
    /// calls the proof of the player. Useful to take screenshots of a quiet demo.
    static var demoSimulationDelay: TimeInterval {
        let arguments = ProcessInfo.processInfo.arguments
        guard
            let index = arguments.firstIndex(of: "-demo-sim-delay"),
            index + 1 < arguments.count,
            let seconds = Double(arguments[index + 1])
        else {
            return 45
        }
        return seconds
    }
}
