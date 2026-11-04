import Foundation

/// Runtime configuration read from `Info.plist` (which is filled from the `.xcconfig` files).
enum AppConfig {
    static let baseURL: URL = {
        let fallback = URL(string: "http://localhost:8787") ?? URL(fileURLWithPath: "/dev/null")
        guard
            let raw = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
            !raw.isEmpty,
            let url = URL(string: raw),
            url.scheme != nil
        else {
            return fallback
        }
        return url
    }()

    /// The API base URL as shown in the UI (debug helper).
    static var baseURLDescription: String {
        baseURL.absoluteString
    }

    /// `-demo` starts the app in the offline demo mode (DESIGN.md, section 9).
    static var isDemoLaunchArgument: Bool {
        ProcessInfo.processInfo.arguments.contains("-demo")
    }
}
