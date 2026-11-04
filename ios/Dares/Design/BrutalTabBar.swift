import SwiftUI
import UIKit

/// The floating capsule bar of the club screen: MATCH · VAR · FEED · TABLE.
struct BrutalTabBar: View {
    /// The size of the SF Symbols of the tabs.
    private static let symbolSize: CGFloat = 20
    /// The dim of a tab that is not the current one.
    private static let inactiveOpacity: Double = 0.6

    /// The symbol of the VAR tab.
    ///
    /// `video.badge.checkmark` is the house symbol for the check. On a system
    /// where it is missing the checkered flag stands in for it.
    private static let varSymbol: String = {
        UIImage(systemName: "video.badge.checkmark") == nil ? "flag.checkered" : "video.badge.checkmark"
    }()

    enum Tab: String, Hashable, CaseIterable, Identifiable {
        case match
        case varCheck
        case feed
        case table

        var id: String { rawValue }

        var title: String {
            switch self {
            case .match: "MATCH"
            case .varCheck: "VAR"
            case .feed: "FEED"
            case .table: "TABLE"
            }
        }

        /// The SF Symbol of the tab: the ball for the matchday, the check for
        /// the VAR, the grid for the feed and the list for the standings.
        @MainActor
        var symbol: String {
            switch self {
            case .match: "soccerball"
            case .varCheck: BrutalTabBar.varSymbol
            case .feed: "square.grid.2x2"
            case .table: "list.number"
            }
        }

        /// The spoken name of the tab. The VAR says how many proofs wait.
        func accessibilityName(waiting: Int) -> String {
            switch self {
            case .match: "Matchday"
            case .varCheck: waiting > 0 ? "VAR check, \(waiting) waiting" : "VAR check"
            case .feed: "Feed"
            case .table: "The Table"
            }
        }
    }

    @Binding var selection: Tab
    var badgeCount: Int = 0
    /// The bar sits on a dark screen or on the paper of The Table.
    var isDark: Bool = true

    var body: some View {
        let foreground: Color = isDark ? .paper : .ink
        let active: Color = isDark ? .card : .ink
        let background: Color = isDark ? Color(hex: 0x1B1B1D) : Color(hex: 0xF1F1EF)
        let border: Color = isDark ? Color.paper.opacity(0.13) : Color.ink.opacity(0.10)

        return HStack(spacing: 0) {
            ForEach(Tab.allCases) { tab in
                let isSelected = tab == selection
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: Self.symbolSize, weight: .bold))
                            .foregroundStyle(isSelected ? active : foreground)
                            .frame(width: Self.symbolSize, height: Self.symbolSize)
                            .opacity(isSelected ? 1 : Self.inactiveOpacity)
                            .overlay(alignment: .topLeading) {
                                if tab == .varCheck, badgeCount > 0 {
                                    countBadge
                                }
                            }

                        Text(tab.title)
                            .labelStyle(9)
                            .foregroundStyle(isSelected ? active : foreground)
                            .opacity(isSelected ? 1 : Self.inactiveOpacity)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(tab.accessibilityName(waiting: badgeCount)))
                .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 54)
        .background(background)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(border, lineWidth: 1.5)
        }
    }

    /// The red count of the proofs that wait for the VAR.
    ///
    /// A square box at the top-right corner of the symbol, the way the house
    /// draws every count. It only tucks a few points into the symbol.
    private var countBadge: some View {
        Text("\(badgeCount)")
            .font(.system(size: 9, weight: .heavy, design: .monospaced))
            .foregroundStyle(Color.paper)
            .padding(.horizontal, 3)
            .padding(.vertical, 0.5)
            .background(Color.red)
            .fixedSize()
            .offset(x: Self.symbolSize - 3, y: -8)
    }
}
