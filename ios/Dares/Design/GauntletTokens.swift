import SwiftUI

// MARK: - Colour tokens (DESIGN.md, section 2)
//
// The palette is closed: six colours, each with exactly one meaning. There is no
// seventh colour anywhere in the app.

extension Color {
    /// `#0B0B0C` — dark backgrounds, text on light surfaces.
    static let ink = Color(hex: 0x0B0B0C)
    /// `#FFFFFF` — light backgrounds (The Table), text on dark surfaces.
    static let paper = Color(hex: 0xFFFFFF)
    /// `#FFD60A` — yellow card. Primary CTA, "In VAR", leader row, current tab.
    static let card = Color(hex: 0xFFD60A)
    /// `#E5202E` — red card. Rejected, "No goal", relegation, badges.
    static let red = Color(hex: 0xE5202E)
    /// `#00C46A` — accepted, "Goal", the GOAL! screen.
    static let pitch = Color(hex: 0x00C46A)
    /// `#FF6B00` — streak numbers only.
    static let flame = Color(hex: 0xFF6B00)
    /// `#FBFBF7` — receipt paper only.
    static let receipt = Color(hex: 0xFBFBF7)

    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

// MARK: - Type (DESIGN.md, section 3)

extension Font {
    /// Anton — the display face. UPPERCASE, for titles, fixture names, buttons,
    /// scores and the numbers of the table.
    static func anton(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("Anton-Regular", size: size, relativeTo: style)
    }

    /// SF Mono — labels, meta, receipt. Uppercase and letter spaced.
    static func monoLabel(_ size: CGFloat, relativeTo style: Font.TextStyle = .caption2) -> Font {
        .system(size: size, weight: .bold, design: .monospaced).leading(.standard)
    }
}

// MARK: - Metrics

enum Gauntlet {
    /// Every card, pill and button has square corners (DESIGN.md, section 4).
    static let corner: CGFloat = 2
    /// The border of every surface: 2pt.
    static let border: CGFloat = 2
    /// Hard offset shadows only: 4,4 with no blur.
    static let shadowOffset: CGFloat = 4
    /// Anton is the display face; it needs a touch more tracking than the system face.
    static let displayTracking: CGFloat = 0.4
    /// Letter spacing of the mono labels (~0.1em).
    static let labelTracking: CGFloat = 0.9

    /// The rotations that are part of the identity (DESIGN.md, section 4).
    enum Rotation {
        static let varCard: Double = 5
        static let varCardBack: Double = -3
        static let callNoGoal: Double = -2
        static let callGoal: Double = 2
        static let goal: Double = -5
        static let plus25: Double = 8
        static let polaroid: Double = 4
        static let stamp: Double = -14
        static let envelope: Double = -2
        static let pennant: Double = -3
        static let bonusSticker: Double = 10
    }

    /// The spring used by the VAR card, the stamps and the GOAL! entrance.
    static func spring(_ response: CGFloat = 0.35, _ damping: CGFloat = 0.7) -> Animation {
        .spring(response: response, dampingFraction: damping)
    }
}

// MARK: - Shared helpers

extension Text {
    /// The placeholder of a text field.
    ///
    /// The placeholder of the system is nearly invisible on the dark background of the
    /// club: it uses the mono face and the secondary colour of the house instead, which
    /// keeps a contrast of more than 4.5:1 on the ink.
    static func gauntletPlaceholder(
        _ text: String,
        size: CGFloat = 13,
        color: Color = Color.paper.opacity(0.72)
    ) -> Text {
        Text(text)
            .font(.monoLabel(size))
            .foregroundStyle(color)
    }
}

extension View {
    /// A 2pt square-cornered border.
    func brutalBorder(_ color: Color, width: CGFloat = Gauntlet.border) -> some View {
        overlay(
            Rectangle()
                .stroke(color, lineWidth: width)
        )
    }

    /// The hard offset shadow: a copy of the block, 4pt to the right and down, no blur.
    /// It is drawn *behind* the content, so the text never gets a ghost.
    func hardShadow(_ color: Color, offset: CGFloat = Gauntlet.shadowOffset) -> some View {
        background {
            Rectangle()
                .fill(color)
                .offset(x: offset, y: offset)
        }
    }

    /// Uppercase Anton display text.
    func displayStyle(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> some View {
        font(.anton(size, relativeTo: style))
            .tracking(Gauntlet.displayTracking)
            .textCase(.uppercase)
    }

    /// Uppercase mono label text with the house letter spacing.
    func labelStyle(_ size: CGFloat, relativeTo style: Font.TextStyle = .caption2) -> some View {
        font(.monoLabel(size, relativeTo: style))
            .tracking(Gauntlet.labelTracking)
            .textCase(.uppercase)
    }
}
