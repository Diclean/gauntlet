import SwiftUI

/// Screen 5 — the full-time receipt of a matchweek.
struct ReceiptView: View {
    let model: GroupViewModel

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var sharedImage: Image?
    @State private var isRendering = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(hex: 0x1C1C1E).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    receiptPaper
                        .padding(.horizontal, 18)
                        .padding(.top, 48)

                    Spacer(minLength: 110)
                }
            }
            .scrollIndicators(.hidden)

            shareButton
                .padding(.horizontal, 18)
                .padding(.bottom, 22)
        }
        .overlay(alignment: .topLeading) {
            Button {
                dismiss()
            } label: {
                Text("✕")
                    .displayStyle(16)
                    .foregroundStyle(Color.paper)
                    .frame(width: 36, height: 36)
                    .overlay {
                        Rectangle().stroke(Color.paper.opacity(0.5), lineWidth: 1.5)
                    }
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .padding(.leading, 14)
            .accessibilityLabel(Text("Close"))
        }
        .task {
            await renderReceipt()
        }
    }

    // MARK: - The paper

    private var receiptPaper: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                Text("\(clubName) · EST. \(establishedYear)")
                    .labelStyle(9.5)
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)

                Text("Full-time receipt")
                    .displayStyle(25)
                    .foregroundStyle(Color.ink)
                    .padding(.vertical, 2)

                Text("\(matchweekLine)")
                    .labelStyle(9.5)
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)

                Text(playerLine)
                    .labelStyle(9.5)
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 13)
            .padding(.top, 14)

            dash
                .padding(.top, 7)
                .padding(.horizontal, 13)

            VStack(spacing: 4) {
                ForEach(receiptLines) { line in
                    receiptLine(line)
                }
            }
            .padding(.horizontal, 13)
            .padding(.top, 7)

            dash
                .padding(.top, 7)
                .padding(.horizontal, 13)

            HStack {
                Text("Total")
                    .displayStyle(22)
                Spacer(minLength: 8)
                Text("\(total) PTS")
                    .displayStyle(22)
            }
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 13)
            .padding(.top, 2)

            HStack {
                Text("Rank")
                    .labelStyle(9.5)
                Spacer(minLength: 8)
                Text(rankText)
                    .labelStyle(9.5)
            }
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 13)
            .padding(.top, 4)

            if let manOfTheMatch = receipt?.manOfTheMatch {
                HStack {
                    Text("⭐ MAN OF THE MATCH")
                        .labelStyle(9.5)
                    Spacer(minLength: 8)
                    Text(manOfTheMatch.displayName.uppercased())
                        .labelStyle(9.5)
                }
                .foregroundStyle(Color.card)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.ink)
                .padding(.horizontal, 13)
                .padding(.top, 7)
            }

            if let spoon = receipt?.woodenSpoon {
                HStack {
                    Text("🥄 WOODEN SPOON")
                        .labelStyle(9.5)
                    Spacer(minLength: 8)
                    Text("\(spoon.displayName.uppercased()) (PAYS)")
                        .labelStyle(9.5)
                }
                .foregroundStyle(Color.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .overlay {
                    Rectangle()
                        .stroke(Color.ink, lineWidth: 1.5)
                }
                .padding(.horizontal, 13)
                .padding(.top, 4)
            }

            BarcodeView()
                .padding(.horizontal, 13)
                .padding(.top, 9)
                .padding(.bottom, 4)

            Text("NO REFUNDS ON RED CARDS.\nSCREENSHOT IT. SEND IT TO THE GC.")
                .labelStyle(9.5)
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 13)
                .padding(.bottom, 16)
        }
        .background(Color.receipt, in: ReceiptShape())
    }

    private var dash: some View {
        Rectangle()
            .fill(Color.ink.opacity(0.55))
            .frame(height: 1.5)
            .mask {
                HStack(spacing: 0) {
                    ForEach(0 ..< 80, id: \.self) { index in
                        Rectangle()
                            .fill(Color.black)
                            .frame(width: index.isMultiple(of: 2) ? 5 : 3)
                    }
                }
            }
    }

    private func receiptLine(_ line: ReceiptLine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(line.label)
                .labelStyle(9.5)
                .strikethrough(line.struck, color: Color.ink.opacity(0.5))
                .foregroundStyle(line.struck ? Color.ink.opacity(0.5) : Color.ink)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Text("\(line.points)")
                .labelStyle(9.5)
                .foregroundStyle(line.struck ? Color.ink.opacity(0.5) : Color.ink)
        }
    }

    // MARK: - Share

    private var shareButton: some View {
        SwiftUI.Group {
            if let sharedImage {
                ShareLink(
                    item: sharedImage,
                    preview: SharePreview("Full-time receipt", image: sharedImage)
                ) {
                    shareLabel
                }
            } else {
                Button {
                    Task { await renderReceipt() }
                } label: {
                    shareLabel
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var shareLabel: some View {
        HStack(spacing: 8) {
            Text("Share to the group chat")
                .displayStyle(17)
            // The arrow is an SF Symbol — no emoji as an icon.
            Image(systemName: "arrow.up.right")
                .font(.system(size: 17, weight: .bold))
        }
        .foregroundStyle(Color.ink)
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .background(Color.card)
        .brutalBorder(Color.paper)
        .hardShadow(Color.paper)
    }

    /// Renders the receipt into an image so it can be shared in the group chat.
    private func renderReceipt() async {
        guard !isRendering else { return }
        isRendering = true
        defer { isRendering = false }
        let renderer = ImageRenderer(content: receiptPaper)
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(width: 340, height: 560)
        guard let cgImage = renderer.cgImage else { return }
        sharedImage = Image(decorative: cgImage, scale: 1)
    }

    // MARK: - Data

    private var receipt: ReceiptResponse? {
        model.receipt
    }

    private var receiptLines: [ReceiptLine] {
        receipt?.lines ?? []
    }

    private var total: Int {
        receipt?.player.total ?? 0
    }

    private var clubName: String {
        (receipt?.club.name ?? model.group?.name ?? DemoSeed.clubName).uppercased()
    }

    private var forfeit: String {
        receipt?.club.forfeit ?? Group.defaultForfeit
    }

    private var establishedYear: String {
        guard let week = model.week else { return "2026" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy"
        return formatter.string(from: week.startsAt)
    }

    private var matchweekLine: String {
        guard let week = receipt?.week else { return "MATCHWEEK 0" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd"
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "MMM"
        let from = formatter.string(from: week.startsAt)
        let to = formatter.string(from: week.endsAt)
        let month = dayFormatter.string(from: week.startsAt).uppercased()
        return "MATCHWEEK \(week.number) · \(from)–\(to) \(month)"
    }

    private var playerLine: String {
        guard let player = receipt?.player.user else { return "PLAYER: —" }
        return "PLAYER: \(player.displayName.uppercased()) \(player.avatarEmoji ?? "") #\(String(format: "%02d", shirtNumber(for: player)))"
    }

    private var rankText: String {
        guard let player = receipt?.player else { return "—" }
        let rank: String
        switch player.rank {
        case 1: rank = "1ST"
        case 2: rank = "2ND"
        case 3: rank = "3RD"
        default: rank = "\(player.rank)TH"
        }
        let movement: String
        if player.rankDelta > 0 {
            movement = " ▲\(player.rankDelta)"
        } else if player.rankDelta < 0 {
            movement = " ▼\(-player.rankDelta)"
        } else {
            movement = " — 0"
        }
        return rank + movement
    }

    /// The shirt number of a member of the club.
    private func shirtNumber(for user: User) -> Int {
        let index = model.members.firstIndex { $0.user.id == user.id } ?? 0
        return index + 7
    }
}

#Preview("Receipt") {
    NavigationStack {
        ReceiptView(model: .preview())
            .environment(AppState.preview())
    }
}
