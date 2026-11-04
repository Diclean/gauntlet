import SwiftUI

/// Screen 4 — The Table. The leaderboard of the matchweek or of the season.
/// The title race is the second mode of the same tab, like in the mock.
struct TableView: View {
    enum Mode: Hashable {
        case table
        case race
    }

    let model: GroupViewModel
    /// The title race is a dark screen: the tab bar follows.
    @Binding var isDark: Bool

    @Environment(AppState.self) private var appState
    @State private var scope: LeaderboardScope = .week
    @State private var mode: Mode = .table
    @State private var showingReceipt = false
    @State private var showingAwards = false
    @State private var showingSettings = false

    private var rows: [TableRow] {
        model.tableRows(scope: scope)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            (mode == .race ? Color.ink : Color.paper)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if mode == .race {
                        TitleRaceView(model: model) {
                            withAnimation { mode = .table }
                        }
                        .padding(.top, 8)
                    } else {
                        tableContent
                    }
                    Spacer(minLength: 120)
                }
            }
            .scrollIndicators(.hidden)
        }
        .fullScreenCover(isPresented: $showingReceipt) {
            ReceiptView(model: model)
        }
        .fullScreenCover(isPresented: $showingAwards) {
            AwardsNightView(model: model)
        }
        .fullScreenCover(isPresented: $showingSettings) {
            GroupSettingsView(model: model)
        }
        .onChange(of: mode) { _, newValue in
            isDark = newValue == .race
        }
    }

    // MARK: - The table

    private var tableContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("The Table")
                .displayStyle(42)
                .foregroundStyle(Color.ink)
                .padding(.horizontal, 16)
                .padding(.top, 8)

            BrutalSegmented(
                options: [
                    .init(value: LeaderboardScope.week, title: "MATCHWEEK \(model.week?.number ?? 0)"),
                    .init(value: LeaderboardScope.all, title: "SEASON"),
                ],
                selection: $scope,
                onDark: false
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)

            table
                .padding(.horizontal, 10)
                .padding(.top, 10)

            clubForm
                .padding(.horizontal, 16)
                .padding(.top, 12)

            HStack(spacing: 6) {
                tableLink(title: "Race") {
                    withAnimation {
                        mode = .race
                    }
                }
                tableLink(title: "Receipt") {
                    showingReceipt = true
                }
                tableLink(title: "Awards") {
                    showingAwards = true
                }
                tableLink(title: "Club") {
                    showingSettings = true
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
        }
    }

    private var table: some View {
        VStack(spacing: 0) {
            headerRow

            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                let isLast = index == rows.count - 1
                if isLast, rows.count > 1 {
                    relegationLine
                }
                tableRow(row, isLeader: row.rank == 1, isLast: isLast)
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("#")
                .frame(width: 28, alignment: .leading)
            Text("PLAYER")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("W")
                .frame(width: 26, alignment: .leading)
            Text("FORM")
                .frame(width: 84, alignment: .leading)
            Text("PTS")
                .frame(width: 44, alignment: .trailing)
        }
        .labelStyle(8)
        .foregroundStyle(Color.ink.opacity(0.55))
        .padding(.horizontal, 3)
        .padding(.bottom, 6)
    }

    private func tableRow(_ row: TableRow, isLeader: Bool, isLast: Bool) -> some View {
        HStack(spacing: 0) {
            Text("\(row.rank)")
                .displayStyle(18)
                .frame(width: 28, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(row.user.avatarEmoji ?? "🙂")
                        .font(.system(size: 14))
                    Text(row.user.displayName)
                        .displayStyle(14)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                movementLabel(row.movement)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(row.wins)")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, alignment: .leading)

            FormSquares(results: row.form, size: 13)
                .frame(width: 84, alignment: .leading)

            Text("\(row.points)")
                .displayStyle(17)
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 7)
        .background(rowBackground(isLeader: isLeader, isLast: isLast))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.ink.opacity(0.12))
                .frame(height: 1.5)
        }
        .accessibilityElement(children: .combine)
    }

    private func rowBackground(isLeader: Bool, isLast: Bool) -> Color {
        if isLeader { return .card }
        if isLast { return Color(hex: 0xFDE4E6) }
        return .clear
    }

    private func movementLabel(_ movement: Int) -> some View {
        SwiftUI.Group {
            if movement > 0 {
                Text("▲ \(movement)")
                    .foregroundStyle(Color(hex: 0x00A65A))
            } else if movement < 0 {
                Text("▼ \(-movement)")
                    .foregroundStyle(Color.red)
            } else {
                Text("— 0")
                    .foregroundStyle(Color.ink.opacity(0.45))
            }
        }
        .labelStyle(8)
    }

    private var relegationLine: some View {
        HStack(spacing: 4) {
            Text("▼")
            Text("RELEGATION ZONE — \(forfeitText)")
        }
        .labelStyle(8)
        .foregroundStyle(Color.red)
        .padding(.horizontal, 4)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.red)
                .frame(height: 2)
                .mask {
                    // The dashed line of the mock.
                    HStack(spacing: 0) {
                        ForEach(0 ..< 60, id: \.self) { index in
                            Rectangle()
                                .fill(Color.red)
                                .frame(width: index.isMultiple(of: 2) ? 5 : 3)
                        }
                    }
                }
                .padding(.horizontal, -4)
        }
    }

    private var forfeitText: String {
        (model.group?.forfeit ?? Group.defaultForfeit).uppercased()
    }

    // MARK: - Club form

    private var clubForm: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Club form")
                    .labelStyle(8)
                Text("EVERYONE SCORED")
                    .labelStyle(8)
                    .foregroundStyle(Color.ink.opacity(0.55))
            }
            Spacer(minLength: 8)
            Text("🔥 \(model.clubForm()) weeks")
                .displayStyle(20)
                .foregroundStyle(Color.flame)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.paper)
        .brutalBorder(Color.ink)
        .hardShadow(Color.ink, offset: 3)
        .accessibilityElement(children: .combine)
    }

    /// A small link to the other screens of the club.
    private func tableLink(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .labelStyle(8.5)
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .overlay {
                    Rectangle().stroke(Color.ink, lineWidth: 1.5)
                }
        }
        .buttonStyle(.plain)
    }
}

#Preview("Table") {
    struct TablePreview: View {
        @State private var isDark = false
        var body: some View {
            NavigationStack {
                TableView(model: .preview(), isDark: $isDark)
                    .environment(AppState.preview())
            }
        }
    }
    return TablePreview()
}
