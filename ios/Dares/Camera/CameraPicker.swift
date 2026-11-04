import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Camera-only capture. The photo library is never offered.
struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (CapturedMedia) -> Void
    let onCancel: () -> Void

    static var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = ["public.image", "public.movie"]
        picker.videoMaximumDuration = CaptureLimits.maxVideoDuration
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCapture: (CapturedMedia) -> Void
        private let onCancel: () -> Void

        init(onCapture: @escaping (CapturedMedia) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let mediaType = info[.mediaType] as? String else {
                onCancel()
                return
            }

            if mediaType == UTType.movie.identifier {
                guard let url = info[.mediaURL] as? URL else {
                    onCancel()
                    return
                }
                do {
                    let copied = try copyVideoToTemporaryLocation(url)
                    guard copied.byteCount <= CaptureLimits.maxVideoBytes else {
                        throw CaptureError.videoTooLarge
                    }
                    onCapture(copied)
                } catch {
                    onCancel()
                }
                return
            }

            guard let image = info[.originalImage] as? UIImage,
                  let data = ImageCompressor.jpegData(from: image)
            else {
                onCancel()
                return
            }
            onCapture(.photo(data: data))
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }

        private func copyVideoToTemporaryLocation(_ url: URL) throws -> CapturedMedia {
            let fileExtension = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
            let destination = URL.temporaryDirectory
                .appending(path: "dares-proof-\(UUID().uuidString).\(fileExtension)")
            let data = try Data(contentsOf: url)
            try data.write(to: destination, options: .atomic)
            return .video(
                url: destination,
                fileName: "proof.\(fileExtension)",
                mimeType: fileExtension.lowercased() == "mov" ? "video/quicktime" : "video/mp4"
            )
        }
    }
}
