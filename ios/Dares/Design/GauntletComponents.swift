import SwiftUI
import UIKit

// MARK: - Brutal button

/// The primary call to action: a square-cornered block with a hard offset shadow.
struct BrutalButton: View {
    let title: String
    var subtitle: String?
    var trailing: String?
    var background: Color = .card
    var foreground: Color = .ink
    var borderColor: Color = .paper
    var shadowColor: Color = .paper
    var rotation: Double = 0
    var isEnabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .displayStyle(19)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let subtitle {
                    Text(subtitle)
                        .labelStyle(9)
                        .foregroundStyle(foreground.opacity(0.65))
                }
                if let trailing {
                    Text(trailing)
                        .displayStyle(19)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(background)
            .foregroundStyle(foreground)
            .brutalBorder(borderColor)
            .hardShadow(shadowColor)
        }
        .buttonStyle(.plain)
        .rotationEffect(.degrees(rotation))
        .opacity(isEnabled ? 1 : 0.5)
        .disabled(!isEnabled)
    }
}

/// The secondary action: a bordered block, no fill.
struct BrutalOutlineButton: View {
    let title: String
    var foreground: Color = .paper
    var borderColor: Color = .paper
    var shadowColor: Color = .paper
    /// The colour behind the block — the hard shadow needs an opaque base.
    var background: Color = .ink
    var rotation: Double = 0
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .displayStyle(17)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(background)
                .foregroundStyle(foreground)
                .brutalBorder(borderColor)
                .hardShadow(shadowColor)
        }
        .buttonStyle(.plain)
        .rotationEffect(.degrees(rotation))
    }
}

// MARK: - Pills

/// The status pill of a fixture: `FT ✓`, `IN VAR`, `RED ✕` or `TO PLAY`.
struct StatusPill: View {
    enum Kind {
        case fullTime
        case inVAR
        case red
        case toPlay

        var label: String {
            switch self {
            case .fullTime: "FT ✓"
            case .inVAR: "IN VAR"
            case .red: "RED ✕"
            case .toPlay: "TO PLAY"
            }
        }

        var background: Color {
            switch self {
            case .fullTime: .pitch
            case .inVAR: .card
            case .red: .red
            case .toPlay: .clear
            }
        }

        var foreground: Color {
            switch self {
            case .fullTime: .ink
            case .inVAR: .ink
            case .red: .paper
            case .toPlay: .paper
            }
        }

        var border: Color {
            switch self {
            case .toPlay: .paper
            default: background
            }
        }
    }

    let kind: Kind

    var body: some View {
        Text(kind.label)
            .labelStyle(8.5)
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(kind.background)
            .foregroundStyle(kind.foreground)
            .brutalBorder(kind.border, width: 1.5)
            .fixedSize()
    }
}

// MARK: - Mono label

/// The house label: SF Mono, uppercase, letter spaced, 8–10pt.
struct MonoLabel: View {
    let text: String
    var size: CGFloat = 9
    var color: Color = .paper
    var opacity: Double = 1

    var body: some View {
        Text(text)
            .labelStyle(size)
            .foregroundStyle(color.opacity(opacity))
    }
}

// MARK: - Outlined number
//
// Fixture numbers 01–05 are Anton with a stroke only, no fill (DESIGN.md, section 3).

/// Anton text drawn as an outline. UIKit draws the glyph outline with a negative
/// stroke width, which is the only way to get a true hollow display face.
struct OutlinedNumber: View {
    let text: String
    var size: CGFloat = 22
    var stroke: Color = .paper
    var lineWidth: CGFloat = 1.2

    var body: some View {
        OutlinedText(text: text, size: size, stroke: stroke, lineWidth: lineWidth)
            .accessibilityLabel(Text(text))
    }
}

/// Anton text drawn as an outline. UIKit draws the glyph outline with a negative
/// stroke width, which is the only way to get a true hollow display face.
struct OutlinedText: UIViewRepresentable {
    let text: String
    var size: CGFloat = 22
    var stroke: Color = .paper
    var lineWidth: CGFloat = 1.5

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 1
        label.textAlignment = .center
        label.attributedText = attributedText
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        if label.attributedText?.string != text {
            label.attributedText = attributedText
        }
    }

    private var attributedText: NSAttributedString {
        let base = UIFont(name: "Anton-Regular", size: size)
            ?? UIFont.systemFont(ofSize: size, weight: .heavy)
        let font = UIFontMetrics(forTextStyle: .body).scaledFont(for: base)
        return NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: UIColor.clear,
                .strokeColor: UIColor(stroke),
                .strokeWidth: -lineWidth,
            ]
        )
    }
}

// MARK: - Stamp

/// The `GOAL` / `NO GOAL` stamp that lands on the VAR card.
struct StampView: View {
    let title: String
    var color: Color
    var size: CGFloat = 40

    var body: some View {
        Text(title)
            .displayStyle(size)
            .tracking(1.2)
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.4))
            .overlay {
                Rectangle()
                    .stroke(color, lineWidth: 4)
                    .padding(-2)
            }
            .rotationEffect(.degrees(Gauntlet.Rotation.stamp))
    }
}

// MARK: - Form squares

/// The last five matchweeks: `W` (won), `D` (drew), `L` (lost).
struct FormSquares: View {
    enum Result: String {
        case win = "W"
        case draw = "D"
        case loss = "L"

        var background: Color {
            switch self {
            case .win: .pitch
            case .draw: Color(hex: 0xB9B9B9)
            case .loss: .red
            }
        }

        var foreground: Color {
            switch self {
            case .win, .loss: .paper
            case .draw: .ink
            }
        }
    }

    let results: [Result]
    var size: CGFloat = 12

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(results.enumerated()), id: \.offset) { _, result in
                Text(result.rawValue)
                    .font(.system(size: size * 0.58, weight: .bold, design: .monospaced))
                    .foregroundStyle(result.foreground)
                    .frame(width: size, height: size)
                    .background(result.background)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Form"))
        .accessibilityValue(Text(results.map(\.rawValue).joined(separator: " ")))
    }
}

// MARK: - Segmented control

/// The square segmented control of The Table and of the title race.
struct BrutalSegmented<Value: Hashable>: View {
    struct Option {
        let value: Value
        let title: String
    }

    let options: [Option]
    @Binding var selection: Value
    var onDark: Bool = true

    var body: some View {
        let active: Color = onDark ? .paper : .ink
        let idle: Color = onDark ? .paper : .ink
        let activeText: Color = onDark ? .ink : .paper
        return HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                let isSelected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .labelStyle(9)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(isSelected ? active : Color.clear)
                        .foregroundStyle(isSelected ? activeText : idle)
                }
                .buttonStyle(.plain)
                if index < options.count - 1 {
                    Rectangle()
                        .fill(active)
                        .frame(width: 2)
                }
            }
        }
        .brutalBorder(active)
    }
}

// MARK: - Barcode

/// The barcode of the full-time receipt.
struct BarcodeView: View {
    var height: CGFloat = 30

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            Canvas { context, _ in
                var x: CGFloat = 0
                var index = 0
                while x < width {
                    let pattern = [2.0, 1.0, 1.0, 3.0, 1.0, 2.0, 1.0, 4.0]
                    let barWidth = pattern[index % pattern.count]
                    let isBar = index % 3 != 2
                    if isBar {
                        context.fill(
                            Path(CGRect(x: x, y: 0, width: barWidth, height: height)),
                            with: .color(Color.ink)
                        )
                    }
                    x += barWidth + 1
                    index += 1
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - Club header

/// The crest, the club name and the avatar of the signed in player.
struct ClubHeader: View {
    let clubName: String
    let initials: String
    let avatarEmoji: String?

    var body: some View {
        HStack(spacing: 8) {
            ClubCrest(initials: initials, size: 22)
            Text(clubName)
                .labelStyle(10)
                .foregroundStyle(Color.paper)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            Text(avatarEmoji ?? "🙂")
                .font(.system(size: 20))
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Section heading

/// A small uppercase heading with a rule under it.
struct SectionHeading: View {
    let text: String
    var color: Color = .paper
    var ruleColor: Color = .paper

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .labelStyle(8.5)
                .foregroundStyle(color)
            Rectangle()
                .fill(ruleColor.opacity(0.25))
                .frame(height: 1.5)
        }
    }
}
