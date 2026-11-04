import SwiftUI

// MARK: - Domain presentation

extension Difficulty {
    var title: String {
        switch self {
        case .easy: String(localized: "difficulty.easy")
        case .medium: String(localized: "difficulty.medium")
        case .hard: String(localized: "difficulty.hard")
        }
    }

    var color: Color {
        switch self {
        case .easy: .green
        case .medium: .orange
        case .hard: .red
        }
    }
}

extension MyChallengeStatus {
    var title: String {
        switch self {
        case .todo: String(localized: "status.todo")
        case .pending: String(localized: "status.pending")
        case .accepted: String(localized: "status.accepted")
        case .rejected: String(localized: "status.rejected")
        }
    }

    var color: Color {
        switch self {
        case .todo: .secondary
        case .pending: .orange
        case .accepted: .green
        case .rejected: .red
        }
    }
}

extension SubmissionStatus {
    var title: String {
        switch self {
        case .pending: String(localized: "status.pending")
        case .accepted: String(localized: "status.accepted")
        case .rejected: String(localized: "status.rejected")
        case .expired: String(localized: "status.expired")
        }
    }

    var color: Color {
        switch self {
        case .pending: .orange
        case .accepted: .green
        case .rejected: .red
        case .expired: .secondary
        }
    }
}

extension MediaType {
    var iconName: String {
        switch self {
        case .photo: "photo"
        case .video: "video"
        }
    }
}

// MARK: - Reusable views

struct DifficultyBadge: View {
    let difficulty: Difficulty

    var body: some View {
        Text(difficulty.title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(difficulty.color.opacity(0.18), in: Capsule())
            .foregroundStyle(difficulty.color)
            .accessibilityLabel(Text(difficulty.title))
    }
}

struct PointsBadge: View {
    let points: Int

    var body: some View {
        Label {
            Text("\(points)")
        } icon: {
            Image(systemName: "star.fill")
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.accentColor.opacity(0.18), in: Capsule())
        .foregroundStyle(Color.accentColor)
    }
}

struct StatusChip: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}

struct AvatarView: View {
    let emoji: String?
    let size: CGFloat

    init(emoji: String?, size: CGFloat = 40) {
        self.emoji = emoji
        self.size = size
    }

    var body: some View {
        Circle()
            .fill(Color.accentColor.opacity(0.18))
            .frame(width: size, height: size)
            .overlay {
                Text(emoji ?? "🙂")
                    .font(.system(size: size * 0.55))
            }
            .accessibilityHidden(true)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

/// The small "DEMO" label of the navigation bar: the app runs offline on sample data.
struct DemoBadge: View {
    var body: some View {
        Text("demo.badge")
            .font(.caption2.weight(.heavy))
            .monospaced()
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .foregroundStyle(.white)
            .accessibilityLabel(Text("demo.badge.accessibility"))
    }
}
