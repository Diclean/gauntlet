import Foundation

// MARK: - Domain presentation

extension Difficulty {
    var title: String {
        switch self {
        case .easy: String(localized: "difficulty.easy")
        case .medium: String(localized: "difficulty.medium")
        case .hard: String(localized: "difficulty.hard")
        }
    }
}
