import SwiftUI
import UIKit

/// Camera-only capture flow: record → preview → caption → upload.
struct ProofCaptureView: View {
    let challenge: Challenge

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var captured: CapturedMedia?
    @State private var showingCamera = false
    @State private var caption = ""
    @State private var upload = UploadProgressModel()

    var body: some View {
        NavigationStack {
            SwiftUI.Group {
                if let captured {
                    preview(captured)
                } else {
                    capturePrompt
                }
            }
            .navigationTitle("Prove it")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.ink, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.card)
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker(
                    onCapture: { media in
                        showingCamera = false
                        captured = media
                    },
                    onCancel: {
                        showingCamera = false
                    }
                )
                .ignoresSafeArea()
            }
            .onDisappear {
                // The capture never stays on the disk: it is deleted when the sheet
                // is closed, uploaded or replaced.
                captured?.discard()
                captured = nil
            }
            .alert(
                Text("Something went wrong"),
                isPresented: Binding(
                    get: { upload.errorMessage != nil },
                    set: { if !$0 { upload.errorMessage = nil } }
                ),
                actions: { Button("OK") { upload.errorMessage = nil } },
                message: { Text(upload.errorMessage ?? "") }
            )
        }
    }

    // MARK: - Capture step

    private var capturePrompt: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 20)

            Text("PROVE IT")
                .labelStyle(9)
                .foregroundStyle(Color.card)

            Text(challenge.title)
                .displayStyle(26)
                .foregroundStyle(Color.paper)
                .multilineTextAlignment(.center)

            Text("THE CAMERA ONLY. THE PHOTO LIBRARY IS NEVER USED.")
                .labelStyle(8)
                .foregroundStyle(Color.paper.opacity(0.55))
                .multilineTextAlignment(.center)

            Spacer(minLength: 20)

            if CameraPicker.isCameraAvailable {
                BrutalButton(title: "Open the camera", trailing: "→") {
                    showingCamera = true
                }
            } else {
                VStack(spacing: 8) {
                    Text("NO CAMERA ON THIS DEVICE")
                        .displayStyle(16)
                        .foregroundStyle(Color.red)
                    Text("Use a sample proof instead.")
                        .labelStyle(9)
                        .foregroundStyle(Color.paper.opacity(0.6))
                }
            }

            if canUseSampleImage {
                BrutalOutlineButton(title: "Use a sample proof") {
                    useSampleImage()
                }
            }

            Spacer(minLength: 20)
        }
        .padding(.horizontal, 18)
    }

    // MARK: - Preview step

    private func preview(_ media: CapturedMedia) -> some View {
        VStack(spacing: 0) {
            mediaPreview(media)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)

            VStack(spacing: 12) {
                TextField("", text: $caption, prompt: Text.gauntletPlaceholder("Caption"), axis: .vertical)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.paper)
                    .tint(Color.card)
                    .lineLimit(1 ... 3)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .overlay {
                        Rectangle().stroke(Color.paper.opacity(0.4), lineWidth: 1.5)
                    }
                    .onChange(of: caption) { _, value in
                        if value.count > 200 {
                            caption = String(value.prefix(200))
                        }
                    }

                if upload.isUploading {
                    ProgressView(value: upload.fraction) {
                        Text("UPLOADING")
                            .labelStyle(8)
                            .foregroundStyle(Color.paper)
                    }
                    .progressViewStyle(.linear)
                    .tint(Color.card)
                }

                HStack(spacing: 10) {
                    BrutalOutlineButton(title: "Retake") {
                        captured?.discard()
                        captured = nil
                        caption = ""
                        upload.fraction = 0
                    }
                    .frame(maxWidth: 110)

                    BrutalButton(title: "Send it", trailing: "→") {
                        uploadProof(media)
                    }
                    .disabled(upload.isUploading)
                }
            }
            .padding(18)
            .background(Color.ink)
        }
    }

    @ViewBuilder
    private func mediaPreview(_ media: CapturedMedia) -> some View {
        switch media {
        case let .photo(data):
            if let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
            }
        case let .video(url, _, _):
            LoopingVideoPlayer(url: url)
                .background(Color.black)
        }
    }

    // MARK: - Actions

    private func uploadProof(_ media: CapturedMedia) {
        let progressModel = upload
        upload.isUploading = true
        upload.fraction = 0

        Task {
            do {
                let proof: ProofUpload
                switch media {
                case let .photo(data):
                    proof = ProofUpload(
                        mediaType: .photo,
                        caption: caption.trimmingCharacters(in: .whitespacesAndNewlines),
                        data: data,
                        fileName: "proof.jpg",
                        mimeType: "image/jpeg"
                    )
                case let .video(url, fileName, mimeType):
                    proof = ProofUpload(
                        mediaType: .video,
                        caption: caption.trimmingCharacters(in: .whitespacesAndNewlines),
                        data: try Data(contentsOf: url),
                        fileName: fileName,
                        mimeType: mimeType
                    )
                }

                _ = try await appState.api.createSubmission(
                    challengeID: challenge.id,
                    media: proof,
                    onProgress: { fraction in
                        Task { @MainActor in progressModel.fraction = fraction }
                    }
                )

                upload.isUploading = false
                Haptics.success()
                // The proof is on the server: the capture leaves the disk of the device.
                media.discard()
                captured = nil
                dismiss()
            } catch {
                upload.isUploading = false
                upload.errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
                Haptics.error()
            }
        }
    }

    /// The sample proof is always available in the demo mode, and in debug builds it
    /// replaces the missing camera of the Simulator.
    private var canUseSampleImage: Bool {
        #if DEBUG
        return !CameraPicker.isCameraAvailable || appState.isDemoMode
        #else
        return appState.isDemoMode
        #endif
    }

    private func useSampleImage() {
        guard
            let url = Bundle.main.url(forResource: "SampleProof", withExtension: "png"),
            let data = try? Data(contentsOf: url),
            let image = UIImage(data: data),
            let compressed = ImageCompressor.jpegData(from: image)
        else {
            return
        }
        captured = .photo(data: compressed)
    }
}

#Preview("Capture") {
    ProofCaptureView(challenge: MockData.challenges[1])
        .environment(AppState.preview())
}
