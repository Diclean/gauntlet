import Foundation
import SwiftUI

/// Live countdown to a deadline (e.g. the end of the week).
struct CountdownLabel: View {
    let deadline: Date
    var prefix: String = ""

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(prefix + Self.formatted(remaining: deadline.timeIntervalSince(context.date)))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    static func formatted(remaining: TimeInterval) -> String {
        if remaining <= 0 {
            return String(localized: "countdown.closed")
        }
        let total = Int(remaining.rounded(.down))
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        if days > 0 {
            return String(format: "%dd %02d:%02d:%02d", days, hours, minutes, seconds)
        }
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

enum Formatting {
    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func mediumDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
