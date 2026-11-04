import CryptoKit
import Foundation

/// Downloads and caches proof media. Media is never public: every request carries the bearer token.
///
/// The files live in the temporary directory of the app, but they are written with the
/// complete file protection: they are unreadable while the device is locked. `purge()`
/// deletes them when the player signs out or deletes the account.
actor MediaStore {
    private var imageCache: [String: Data] = [:]
    private var videoCache: [String: URL] = [:]

    func data(for path: String, using client: any APIClientProtocol) async throws -> Data {
        if let cached = imageCache[path] {
            return cached
        }
        let data = try await client.mediaData(for: path)
        if data.count <= 8_000_000 {
            imageCache[path] = data
        }
        return data
    }

    /// Downloads a video once and returns a local file URL that `AVPlayer` can stream.
    func videoURL(
        for path: String,
        using client: any APIClientProtocol,
        fileExtension: String = "mp4"
    ) async throws -> URL {
        if let cached = videoCache[path] {
            return cached
        }
        let data = try await client.mediaData(for: path)
        let name = "dares-media-\(MediaStore.digest(of: path)).\(fileExtension)"
        let url = URL.temporaryDirectory.appending(path: name)
        try FileManager.default.writeProtected(data, to: url)
        videoCache[path] = url
        return url
    }

    /// Deletes every cached file and empties both caches.
    ///
    /// The proofs of a club never stay on the disk of a device that is signed out.
    func purge() {
        for url in videoCache.values {
            try? FileManager.default.removeItem(at: url)
        }
        videoCache.removeAll()
        imageCache.removeAll()
    }

    /// The number of files that are cached on the disk — the tests use it.
    var cachedVideoCount: Int { videoCache.count }

    /// The number of photos that are cached in the memory — the tests use it.
    var cachedImageCount: Int { imageCache.count }

    /// A short, stable digest of a path: the name of the file on the disk.
    private static func digest(of path: String) -> String {
        let hash = SHA256.hash(data: Data(path.utf8))
        return hash.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
