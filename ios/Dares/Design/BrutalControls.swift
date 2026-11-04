import SwiftUI

// MARK: - Square row
//
// The rows of the sheets and of the menus: a square bordered block with a label,
// an optional SF Symbol on the left and an optional note on the right.

struct BrutalRowButton: View {
    let title: String
    var systemImage: String?
    var note: String?
    var isDestructive: Bool = false
    var isHighlighted: Bool = false
    var action: () -> Void

    private var foreground: Color {
        isDestructive ? .red : (isHighlighted ? .ink : .paper)
    }

    private var background: Color {
        isHighlighted ? .card : .clear
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(foreground)
                }
                Text(title)
                    .displayStyle(15)
                    .foregroundStyle(foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let note {
                    Text(note)
                        .labelStyle(8)
                        .foregroundStyle(foreground.opacity(0.65))
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(background)
            .brutalBorder(isHighlighted ? .paper : foreground.opacity(0.85), width: 1.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A row of a sheet that only carries a label — used for the reasons of a report.
struct BrutalRowLabel: View {
    let title: String
    var systemImage: String?
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isSelected ? Color.ink : Color.paper)
            }
            Text(title)
                .displayStyle(15)
                .foregroundStyle(isSelected ? Color.ink : Color.paper)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(Color.ink)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(isSelected ? Color.card : Color.clear)
        .brutalBorder(isSelected ? Color.card : Color.paper.opacity(0.85), width: 1.5)
    }
}

// MARK: - Dashed row
//
// The row that adds the house fixture: a dashed border says "not there yet".

struct BrutalDashedRow: View {
    let title: String
    var note: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text("+")
                    .displayStyle(16)
                    .foregroundStyle(Color.card)
                Text(title)
                    .displayStyle(13)
                    .foregroundStyle(Color.paper)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let note {
                    Text(note)
                        .labelStyle(8)
                        .foregroundStyle(Color.paper.opacity(0.6))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .overlay {
                Rectangle()
                    .stroke(
                        Color.paper.opacity(0.55),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Square toggle
//
// The switch of the notification preferences: a square, yellow when it is on.

struct BrutalSquareToggle: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            Rectangle()
                .fill(isOn ? Color.card : Color.clear)
            Rectangle()
                .stroke(isOn ? Color.card : Color.paper.opacity(0.7), lineWidth: 2)
            if isOn {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(Color.ink)
            }
        }
        .frame(width: 26, height: 26)
        .animation(.easeInOut(duration: 0.12), value: isOn)
        .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - Captain badge
//
// The yellow armband: a square with an Anton "C".

struct CaptainBadge: View {
    var size: CGFloat = 20

    var body: some View {
        Text("C")
            .font(.anton(size * 0.6))
            .tracking(0)
            .foregroundStyle(Color.ink)
            .frame(width: size, height: size)
            .background(Color.card)
            .overlay {
                Rectangle().stroke(Color.ink, lineWidth: 1.5)
            }
            .accessibilityLabel(Text("Captain"))
    }
}

// MARK: - Toast
//
// The short message that slides in at the bottom of a screen.

struct BrutalToast: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Text(text)
                .labelStyle(9)
                .foregroundStyle(Color.paper)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(Color(hex: 0x1B1B1D))
        .brutalBorder(Color.paper)
    }
}

/// The toast of a screen: it shows itself and disappears again.
@MainActor
@Observable
final class ToastModel {
    private(set) var message: String?
    private var task: Task<Void, Never>?

    func show(_ text: String, after seconds: TimeInterval = 3) {
        task?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            message = text
        }
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                self?.message = nil
            }
        }
    }

    func hide() {
        task?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            message = nil
        }
    }
}

extension View {
    /// Shows the toast of the screen at the bottom, above the tab bar.
    func brutalToast(_ model: ToastModel, bottomPadding: CGFloat = 92) -> some View {
        overlay(alignment: .bottom) {
            if let message = model.message {
                BrutalToast(text: message)
                    .padding(.horizontal, 18)
                    .padding(.bottom, bottomPadding)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.message)
    }
}
