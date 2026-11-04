import AVKit
import SwiftUI
import UIKit

/// Loops a local video file. The file is downloaded first because `/media/<key>` needs the
/// bearer token, which `AVPlayer` cannot send on its own.
@MainActor
final class LoopingVideoController {
    let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?

    func load(url: URL) {
        let item = AVPlayerItem(url: url)
        looper = AVPlayerLooper(player: player, templateItem: item)
        player.isMuted = true
        player.play()
    }

    func stop() {
        player.pause()
        looper = nil
    }
}

struct LoopingVideoPlayer: View {
    let url: URL

    @State private var controller = LoopingVideoController()

    var body: some View {
        VideoPlayer(player: controller.player)
            .onAppear { controller.load(url: url) }
            .onDisappear { controller.stop() }
    }
}

/// Loads a proof photo with the bearer token.
struct AuthenticatedPhotoView: View {
    let path: String

    @Environment(AppState.self) private var appState
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if isLoading {
                ProgressView()
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.largeTitle)
                    Text("media.failed")
                        .font(.footnote)
                }
                .foregroundStyle(.secondary)
            }
        }
        .task(id: path) {
            isLoading = true
            failed = false
            do {
                let data = try await appState.media.data(for: path, using: appState.api)
                image = UIImage(data: data)
            } catch {
                failed = true
            }
            isLoading = false
        }
    }
}

/// Loads a proof video with the bearer token and loops it.
struct AuthenticatedVideoView: View {
    let path: String

    @Environment(AppState.self) private var appState
    @State private var localURL: URL?
    @State private var isLoading = true
    @State private var failed = false

    var body: some View {
        ZStack {
            if let localURL {
                LoopingVideoPlayer(url: localURL)
            } else if isLoading {
                ProgressView()
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "video.badge.exclamationmark")
                        .font(.largeTitle)
                    Text("media.failed")
                        .font(.footnote)
                }
                .foregroundStyle(.secondary)
            }
        }
        .task(id: path) {
            isLoading = true
            failed = false
            do {
                localURL = try await appState.media.videoURL(for: path, using: appState.api)
            } catch {
                failed = true
            }
            isLoading = false
        }
    }
}

/// Shows the media of a submission, whatever its type is.
struct ProofMediaView: View {
    let submission: Submission

    var body: some View {
        switch submission.mediaType {
        case .photo:
            AuthenticatedPhotoView(path: submission.mediaUrl)
        case .video:
            AuthenticatedVideoView(path: submission.mediaUrl)
        }
    }
}
