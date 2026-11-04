import Foundation

/// The proof that is uploaded for a challenge: a photo or a short video plus a caption.
struct ProofUpload: Sendable {
    let mediaType: MediaType
    let caption: String?
    let data: Data
    let fileName: String
    let mimeType: String

    init(
        mediaType: MediaType,
        caption: String? = nil,
        data: Data,
        fileName: String = "proof.jpg",
        mimeType: String = "image/jpeg"
    ) {
        self.mediaType = mediaType
        self.caption = caption
        self.data = data
        self.fileName = fileName
        self.mimeType = mimeType
    }
}
