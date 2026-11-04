import SwiftUI

/// Screen 1 — Matchday. The club, the matchweek, the scoreboard and the fixtures.
struct MatchdayView: View {
    let model: GroupViewModel
    let onProveIt: (Challenge) -> Void
    var onOpenFixture: (Challenge) -> Void = { _ in }
    var onAddHouseFixture: () -> Void = {}

    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.ink.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ClubHeader(
                        clubName: model.group?.name.uppercased() ?? DemoSeed.clubName,
                        initials: AppConfig.clubInitials,
                        avatarEmoji: appState.user?.avatarEmoji
                    )
                    .padding(.bottom, 6)

                    matchweekTitle
                        .padding(.horizontal, 18)

                    scoreboard
                        .padding(.horizontal, 18)
                        .padding(.top, 12)

                    captainLine
                        .padding(.horizontal, 18)
                        .padding(.top, 8)

                    fixturesList
                        .padding(.horizontal, 18)
                        .padding(.top, 10)

                    if let banner = awardsBanner {
                        awardsBannerView(banner)
                            .padding(.horizontal, 18)
                            .padding(.top, 18)
                    }

                    Spacer(minLength: 120)
                }
            }
            .scrollIndicators(.hidden)

            if let next = model.nextFixture {
                BrutalButton(
                    title: "Prove it",
                    trailing: "→",
                    background: .card,
                    foreground: .ink,
                    borderColor: .paper,
                    shadowColor: .paper
                ) {
                    onProveIt(next)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 74)
            }
        }
    }

    // MARK: - Pieces

    private var matchweekTitle: some View {
        HStack(alignment: .lastTextBaseline, spacing: 10) {
            Text("Matchweek")
                .displayStyle(46)
                .foregroundStyle(Color.paper)
            Text("\(model.week?.number ?? 0)")
                .displayStyle(46)
                .foregroundStyle(Color.card)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Matchweek \(model.week?.number ?? 0)"))
    }

    private var scoreboard: some View {
        GeometryReader { proxy in
            let unit = proxy.size.width / 3.15
            HStack(spacing: 0) {
                boardCell(
                    title: "Full time in",
                    value: countdown,
                    valueColor: .card
                )
                .frame(width: unit * 1.35)

                Rectangle()
                    .fill(Color.paper)
                    .frame(width: 2)

                boardCell(
                    title: "You scored",
                    value: "\(model.scoredCount) / \(model.fixtureCount)",
                    valueColor: .paper
                )
                .frame(width: unit)

                Rectangle()
                    .fill(Color.paper)
                    .frame(width: 2)

                boardCell(
                    title: "Rank",
                    value: rankText,
                    valueColor: .paper
                )
                .frame(width: unit * 0.8)
            }
        }
        .frame(height: 58)
        .brutalBorder(Color.paper)
    }

    private func boardCell(title: String, value: String, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .labelStyle(7.5)
                .foregroundStyle(Color.paper.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(value)
                .displayStyle(20)
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
    }

    private var fixturesList: some View {
        VStack(spacing: 0) {
            ForEach(model.myFixtures) { fixture in
                Button {
                    onOpenFixture(fixture)
                } label: {
                    FixtureRow(fixture: fixture)
                }
                .buttonStyle(.plain)
                if fixture.id != model.myFixtures.last?.id {
                    Rectangle()
                        .fill(Color.paper.opacity(0.15))
                        .frame(height: 1.5)
                }
            }

            if model.houseFixture?.allowed == true {
                BrutalDashedRow(
                    title: "ADD THE HOUSE FIXTURE",
                    note: "UNTIL WED 23:59"
                ) {
                    onAddHouseFixture()
                }
                .padding(.top, 10)
            }
        }
    }

    /// The captain line: the armband of the matchweek.
    @ViewBuilder
    private var captainLine: some View {
        if let captain = model.captainFixture {
            HStack(spacing: 8) {
                CaptainBadge(size: 18)
                Text("CAPTAIN \(String(format: "%02d", captain.position))")
                    .labelStyle(9)
                    .foregroundStyle(Color.card)
                Text(captain.title.uppercased())
                    .labelStyle(8.5)
                    .foregroundStyle(Color.paper.opacity(0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var awardsBanner: String? {
        guard let awards = model.awards, !awards.awards.isEmpty else { return nil }
        let month = AwardKey.monthName(for: awards.month)
        return "🏆 \(month) AWARDS IS LIVE"
    }

    private func awardsBannerView(_ text: String) -> some View {
        HStack(spacing: 8) {
            Text(text)
                .labelStyle(9)
                .foregroundStyle(Color.ink)
            Spacer(minLength: 4)
            Text("→")
                .displayStyle(13)
                .foregroundStyle(Color.ink)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.card)
        .brutalBorder(Color.paper)
    }

    private var countdown: String {
        guard let week = model.week else { return "—" }
        return MatchdayView.remaining(to: week.endsAt)
    }

    private var rankText: String {
        let rank = model.myRank
        guard rank > 0 else { return "—" }
        switch rank {
        case 1: return "1ST"
        case 2: return "2ND"
        case 3: return "3RD"
        default: return "\(rank)TH"
        }
    }

    /// `4D 22:55` — the time that is left before full time.
    static func remaining(to deadline: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(deadline.timeIntervalSince(now)))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 {
            return String(format: "%dD %02d:%02d", days, hours, minutes)
        }
        return String(format: "%02d:%02d", hours, minutes)
    }
}

/// One fixture of the matchday: the outlined number, the title, the meta and the pill.
struct FixtureRow: View {
    let fixture: Challenge

    var body: some View {
        HStack(spacing: 10) {
            OutlinedNumber(text: String(format: "%02d", fixture.position), size: 22)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(fixture.title)
                    .displayStyle(14)
                    .foregroundStyle(Color.paper)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\(fixture.difficulty.title.uppercased()) · \(fixture.points) PTS")
                    .labelStyle(8.5)
                    .foregroundStyle(Color.paper.opacity(0.6))
                if let author = fixture.createdBy {
                    Text("BY \(author.displayName.uppercased())")
                        .labelStyle(7.5)
                        .foregroundStyle(Color.card.opacity(0.85))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                if fixture.isHouse {
                    FixtureHousePill()
                }
                if fixture.isCaptain {
                    CaptainBadge(size: 18)
                }
                if fixture.isNew {
                    FixtureNewPill()
                }
                StatusPill(kind: StatusPill.Kind(fixture.myStatus))
            }
            .fixedSize()
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The `HOUSE` pill of a fixture that a member of the club wrote.
struct FixtureHousePill: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "house.fill")
                .font(.system(size: 8, weight: .bold))
            Text("HOUSE")
                .labelStyle(7.5)
        }
        .foregroundStyle(Color.paper)
        .padding(.horizontal, 5)
        .padding(.vertical, 5)
        .overlay {
            Rectangle().stroke(Color.paper.opacity(0.7), lineWidth: 1.5)
        }
        .fixedSize()
    }
}

/// The `NEW` pill of a fixture that replaced another one.
struct FixtureNewPill: View {
    var body: some View {
        Text("NEW")
            .labelStyle(7.5)
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 5)
            .padding(.vertical, 5)
            .background(Color.card)
            .overlay {
                Rectangle().stroke(Color.card, lineWidth: 1.5)
            }
            .fixedSize()
    }
}

extension StatusPill.Kind {
    init(_ status: MyChallengeStatus) {
        switch status {
        case .accepted: self = .fullTime
        case .pending: self = .inVAR
        case .rejected: self = .red
        case .todo: self = .toPlay
        }
    }
}

#Preview("Matchday") {
    NavigationStack {
        MatchdayView(model: .preview()) { _ in }
            .environment(AppState.preview())
    }
}
