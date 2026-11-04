import SwiftUI

// MARK: - Crest
//
// The club crest: a shield that is flat on top and points at the bottom
// (`polygon(0 0, 100% 0, 100% 62%, 50% 100%, 0 62%)` in the reference mock).

struct CrestShape: Shape {
    var shoulder: CGFloat = 0.62

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let shoulderY = rect.maxY * shoulder
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: shoulderY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: shoulderY))
        path.closeSubpath()
        return path
    }
}

/// The club crest with its letters (e.g. "SL" for Sunday League FC).
struct ClubCrest: View {
    let initials: String
    var size: CGFloat = 26
    var foreground: Color = .ink
    var background: Color = .card

    var body: some View {
        Text(initials)
            .font(.anton(size * 0.42))
            .foregroundStyle(foreground)
            .frame(width: size, height: size * 1.16)
            .background(background, in: CrestShape())
            .accessibilityHidden(true)
    }
}

// MARK: - Receipt paper
//
// The receipt has zig-zag (torn) edges at the top and the bottom.

struct ReceiptShape: Shape {
    /// The height of one tooth of the zig-zag.
    var tooth: CGFloat = 8
    /// The width of one tooth of the zig-zag.
    var step: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Top edge: a zig-zag from left to right.
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        var x = rect.minX
        var up = true
        while x < rect.maxX {
            let next = min(x + step, rect.maxX)
            path.addLine(to: CGPoint(x: next, y: rect.minY + (up ? 0 : tooth)))
            x = next
            up.toggle()
        }

        // Right edge, bottom edge (mirrored zig-zag) and left edge.
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        x = rect.maxX
        up = true
        while x > rect.minX {
            let next = max(x - step, rect.minX)
            path.addLine(to: CGPoint(x: next, y: rect.maxY - (up ? 0 : tooth)))
            x = next
            up.toggle()
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Pennant
//
// The Player of the Month card: a banner that points at the bottom
// (`polygon(0 0, 100% 0, 100% 91%, 50% 100%, 0 91%)`).

struct PennantShape: Shape {
    var shoulder: CGFloat = 0.91

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let shoulderY = rect.maxY * shoulder
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: shoulderY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: shoulderY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Envelope flap

/// The flap of the awards envelope: a triangle that folds down from the top.
struct EnvelopeFlapShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
