import SwiftUI

/// Screen 8 — the Player of the Month card and the winners of the night.
struct PlayerOfTheMonthView: View {
    let model: GroupViewModel
    let award: Award

    @Environment(AppState.self) private var appState
    @State private var sharedImage: Image?
    @State private var showingCabinet = false

    private var winner: User? {
        award.winners.first
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.card.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    pennant
                        .padding(.horizontal, 34)
                        .padding(.top, 54)

                    others
                        .padding(.horizontal, 16)
                        .padding(.top, 18)

                    Spacer(minLength: 80)
                }
            }
            .scrollIndicators(.hidden)

            buttons
                .padding(.horizontal, 16)
                .padding(.bottom, 22)
        }
        .task {
            await renderCard()
        }
        .fullScreenCover(isPresented: $showingCabinet) {
            NavigationStack {
                TrophyCabinetView()
                    .toolbarBackground(Color.ink, for: .navigationBar)
                    .toolbarColorScheme(.dark, for: .navigationBar)
            }
        }
    }

    // MARK: - The card

    private var pennant: some View {
        VStack(spacing: 0) {
            Text("PLAYER OF THE MONTH · \(AwardKey.shortMonth(for: month))")
                .font(.anton(12))
                .foregroundStyle(Color.ink)
                .textCase(.uppercase)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(Color.paper)
                .overlay {
                    Rectangle()
                        .stroke(Color.ink, lineWidth: 3)
                }

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(award.value)")
                        .displayStyle(54)
                        .foregroundStyle(Color.card)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("POINTS IN \(AwardKey.monthName(for: month))")
                        .labelStyle(7.5)
                        .foregroundStyle(Color.paper.opacity(0.7))
                }
                Spacer(minLength: 8)
                Text(winner?.avatarEmoji ?? "🏆")
                    .font(.system(size: 54))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            Text((winner?.displayName ?? "").uppercased())
                .displayStyle(32)
                .foregroundStyle(Color.paper)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 2)

            Text("\(clubName) · #\(String(format: "%02d", shirtNumber))")
                .labelStyle(7.5)
                .foregroundStyle(Color.paper.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 4)

            statGrid
                .padding(.horizontal, 14)
                .padding(.top, 8)

            Spacer(minLength: 0)
        }
        .frame(height: 280)
        .background(Color.ink, in: PennantShape())
        .overlay {
            PennantShape()
                .stroke(Color.ink, lineWidth: 0)
        }
        .clipShape(PennantShape())
        .rotationEffect(.degrees(Gauntlet.Rotation.pennant))
        .overlay(alignment: .topTrailing) {
            Text("+50")
                .font(.anton(18))
                .foregroundStyle(Color.paper)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.red)
                .overlay {
                    Rectangle().stroke(Color.ink, lineWidth: 2)
                }
                .hardShadow(Color.ink, offset: 3)
                .rotationEffect(.degrees(Gauntlet.Rotation.bonusSticker))
                .offset(x: 14, y: -12)
        }
        .accessibilityElement(children: .combine)
    }

    private var statGrid: some View {
        let stats = award.stats ?? [:]
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0)], spacing: 0) {
            statCell(label: "Goals", value: stats["goals"], fallback: 0)
            statCell(label: "Red cards", value: stats["redCards"], fallback: 0)
            statCell(label: "First to score", value: stats["firstToScore"], fallback: 0)
            statCell(label: "Best week", value: stats["bestWeek"], fallback: award.value)
        }
        .overlay {
            Rectangle()
                .fill(Color.paper.opacity(0.25))
                .frame(height: 1.5)
                .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func statCell(label: String, value: Int?, fallback: Int) -> some View {
        HStack {
            Text(label.uppercased())
                .labelStyle(8)
                .foregroundStyle(Color.paper.opacity(0.8))
            Spacer(minLength: 4)
            Text("\(value ?? fallback)")
                .displayStyle(13)
                .foregroundStyle(Color.card)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.paper.opacity(0.25))
                .frame(height: 1.5)
        }
    }

    // MARK: - Also tonight

    private var others: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("ALSO TONIGHT")
                .labelStyle(8)
                .foregroundStyle(Color.ink)

            ForEach(otherAwards) { other in
                HStack(spacing: 8) {
                    Text(other.award.icon)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.card)
                        .frame(width: 24, height: 24)
                        .background(Color.ink)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(other.award.title)
                            .displayStyle(13)
                            .foregroundStyle(Color.ink)
                        Text("\(other.award.metric) · \(other.value)")
                            .labelStyle(7.5)
                            .foregroundStyle(Color.ink.opacity(0.7))
                    }

                    Spacer(minLength: 4)

                    Text(other.winners.first?.displayName.uppercased() ?? "—")
                        .displayStyle(13)
                        .foregroundStyle(Color.ink)
                }
                .padding(.vertical, 5)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.ink)
                        .frame(height: 2)
                }
            }
        }
    }

    private var otherAwards: [Award] {
        (model.awards?.awards ?? []).filter { $0.award != .playerOfTheMonth }
    }

    // MARK: - Buttons

    private var buttons: some View {
        HStack(spacing: 8) {
            Button {
                showingCabinet = true
            } label: {
                Text("Trophy cabinet")
                    .displayStyle(14)
                    .foregroundStyle(Color.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .overlay {
                        Rectangle().stroke(Color.ink, lineWidth: 2)
                    }
            }
            .buttonStyle(.plain)

            SwiftUI.Group {
                if let sharedImage {
                    ShareLink(item: sharedImage, preview: SharePreview("Player of the month", image: sharedImage)) {
                        shareLabel
                    }
                } else {
                    Button {
                        Task { await renderCard() }
                    } label: {
                        shareLabel
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var shareLabel: some View {
        HStack(spacing: 8) {
            Text("Share")
                .displayStyle(14)
            // The arrow is an SF Symbol — no emoji as an icon.
            Image(systemName: "arrow.up.right")
                .font(.system(size: 14, weight: .bold))
        }
        .foregroundStyle(Color.card)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(Color.ink)
        .overlay {
            Rectangle().stroke(Color.ink, lineWidth: 2)
        }
        .hardShadow(Color.paper, offset: 3)
    }

    private func renderCard() async {
        let renderer = ImageRenderer(content: pennant)
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(width: 320, height: 320)
        guard let cgImage = renderer.cgImage else { return }
        sharedImage = Image(decorative: cgImage, scale: 1)
    }

    // MARK: - Data

    private var month: String {
        model.awards?.month ?? ""
    }

    private var clubName: String {
        (model.group?.name ?? DemoSeed.clubName).uppercased()
    }

    private var shirtNumber: Int {
        guard let winner else { return 7 }
        let index = model.members.firstIndex { $0.user.id == winner.id } ?? 0
        return index + 7
    }
}

#Preview("Player of the month") {
    NavigationStack {
        PlayerOfTheMonthView(model: .preview(), award: MockData.award)
            .environment(AppState.preview())
    }
}
