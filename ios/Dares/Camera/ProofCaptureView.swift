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
            .navigationTitle("capture.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
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
            .alert(
                Text("alert.error.title"),
                isPresented: Binding(
                    get: { upload.errorMessage != nil },
                    set: { if !$0 { upload.errorMessage = nil } }
                ),
                actions: { Button("alert.ok") { upload.errorMessage = nil } },
                message: { Text(upload.errorMessage ?? "") }
            )
        }
    }

    // MARK: - Capture step

    private var capturePrompt: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "camera.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)

            Text("capture.challenge.title")
                .font(.headline)
            Text(challenge.title)
                .font(.title3.bold())
                .multilineTextAlignment(.center)

            if CameraPicker.isCameraAvailable {
                Button {
                    showingCamera = true
                } label: {
                    Label("capture.open_camera", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 32)
            } else {
                VStack(spacing: 12) {
                    Label("capture.camera_unavailable", systemImage: "camera.badge.ellipsis")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    Text("capture.camera_unavailable_hint")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
            }

            if canUseSampleImage {
                Button {
                    useSampleImage()
                } label: {
                    Label("capture.use_sample", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            Text("capture.camera_only_note")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 16)
        }
    }

    // MARK: - Preview step

    private func preview(_ media: CapturedMedia) -> some View {
        VStack(spacing: 0) {
            mediaPreview(media)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)

            VStack(spacing: 12) {
                TextField("capture.caption.placeholder", text: $caption, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1 ... 3)
                    .onChange(of: caption) { _, value in
                        if value.count > 200 {
                            caption = String(value.prefix(200))
                        }
                    }

                if upload.isUploading {
                    ProgressView(value: upload.fraction) {
                        Text("capture.uploading")
                    }
                    .progressViewStyle(.linear)
                }

                HStack {
                    Button("capture.retake") {
                        captured = nil
                        caption = ""
                        upload.fraction = 0
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button {
                        uploadProof(media)
                    } label: {
                        Label("capture.upload", systemImage: "arrow.up.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(upload.isUploading)
                }
            }
            .padding()
            .background(Color(uiColor: .systemGroupedBackground))
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
