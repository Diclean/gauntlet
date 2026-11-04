import Foundation
import UIKit

/// Media captured live with the camera (photo or short video).
enum CapturedMedia: Sendable {
    case photo(data: Data)
    case video(url: URL, fileName: String, mimeType: String)

    var mediaType: MediaType {
        switch self {
        case .photo: .photo
        case .video: .video
        }
    }

    var byteCount: Int {
        switch self {
        case let .photo(data): data.count
        case let .video(url, _, _): (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
    }

    /// Deletes the file of a captured video.
    ///
    /// A capture only lives on the disk until it is uploaded: the file never stays in
    /// the temporary directory of the app (a photo lives in the memory only).
    func discard() {
        guard case let .video(url, _, _) = self else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

enum CaptureError: LocalizedError, Sendable {
    case cameraUnavailable
    case photoEncodingFailed
    case videoTooLarge
    case cancelled

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable: String(localized: "capture.camera_unavailable")
        case .photoEncodingFailed: String(localized: "capture.encoding_failed")
        case .videoTooLarge: String(localized: "capture.video_too_large")
        case .cancelled: String(localized: "capture.cancelled")
        }
    }
}

enum CaptureLimits {
    /// Maximum video duration in seconds (enforced by the picker as well).
    static let maxVideoDuration: TimeInterval = 30
    /// Maximum video file size in bytes.
    static let maxVideoBytes = 50 * 1024 * 1024
    /// Maximum edge length of a photo after resizing.
    static let maxPhotoDimension: CGFloat = 2048
    /// JPEG quality used when compressing photos.
    static let photoQuality: CGFloat = 0.8
}

enum ImageCompressor {
    /// Downscales to `maxDimension` and re-encodes as JPEG.
    static func jpegData(from image: UIImage, maxDimension: CGFloat = CaptureLimits.maxPhotoDimension) -> Data? {
        let resized = resizedImage(image, maxDimension: maxDimension)
        return resized.jpegData(compressionQuality: CaptureLimits.photoQuality)
    }

    static func resizedImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension, longest > 0 else { return image }
        let scale = maxDimension / longest
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
