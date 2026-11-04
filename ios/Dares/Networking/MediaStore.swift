import Foundation

/// Downloads and caches proof media. Media is never public: every request carries the bearer token.
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
        let name = "dares-media-\(abs(path.hashValue)).\(fileExtension)"
        let url = URL.temporaryDirectory.appending(path: name)
        try data.write(to: url, options: .atomic)
        videoCache[path] = url
        return url
    }
}
