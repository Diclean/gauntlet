import Foundation

/// The bundled sample proofs of the demo. The demo never downloads anything: a proof
/// is a file that ships with the app.
enum DemoMedia {
    /// The folder of the bundle that holds the sample proofs.
    static let folder = "DemoMedia"

    /// The bundle that holds the sample proofs. In the tests the app is the host, so the
    /// main bundle is not the right one.
    static let bundle: Bundle = Bundle(for: DemoAPIClient.self)

    /// The media key of a bundled asset, used as `mediaUrl` of a demo submission.
    /// The asset name carries its extension, for example `demo-proof-1.jpg`.
    static func key(_ assetName: String) -> String {
        "demo-media/\(assetName)"
    }

    /// The media key of a bundled photo, `demo-proof-1.jpg` … `demo-proof-6.jpg`.
    static func photoKey(_ index: Int) -> String {
        key("demo-proof-\(index).jpg")
    }

    /// The media key of the bundled video.
    static var videoKey: String {
        key("demo-proof-video.mp4")
    }

    /// The file of a bundled asset.
    static func url(for key: String) -> URL? {
        let name = (key as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        guard !base.isEmpty else { return nil }
        let candidates = ext.isEmpty ? ["jpg", "mp4"] : [ext]
        for candidate in candidates {
            if let url = bundle.url(forResource: base, withExtension: candidate) {
                return url
            }
            if let url = bundle.url(forResource: base, withExtension: candidate, subdirectory: folder) {
                return url
            }
        }
        return nil
    }

    /// The bytes of a bundled asset.
    static func data(for key: String) -> Data? {
        guard let url = url(for: key) else { return nil }
        return try? Data(contentsOf: url)
    }
}
