import Foundation
import Observation

/// Tracks the progress of a multipart upload.
@MainActor
@Observable
final class UploadProgressModel {
    var fraction: Double = 0
    var isUploading = false
    var errorMessage: String?
}
