import SwiftUI

/// Screen 7 — the awards night. Six envelopes, one after the other.
struct AwardsNightView: View {
    let model: GroupViewModel

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var isOpen = false
    @State private var showPlayerOfTheMonth = false

    private var awards: [Award] {
        model.awards?.awards ?? []
    }

    private var current: Award? {
        awards.indices.contains(index) ? awards[index] : nil
    }

    var body: some View {
        ZStack {
            Color.ink.ignoresSafeArea()

            if showPlayerOfTheMonth, let potm = awards.first(where: { $0.award == .playerOfTheMonth }) {
                PlayerOfTheMonthView(model: model, award: potm)
                    .transition(.opacity)
            } else if let current {
                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, 18)
                        .padding(.top, 10)

                    progress
                        .padding(.horizontal, 18)
                        .padding(.top, 12)

                    envelope(current)
                        .padding(.horizontal, 24)
                        .padding(.top, 22)

                    nominees(current)
                        .padding(.horizontal, 18)
                        .padding(.top, 18)

                    Spacer(minLength: 12)

                    actionButton
                        .padding(.horizontal, 18)
                        .padding(.bottom, 22)
                }
                .transition(.opacity)
            } else {
                emptyState
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.7), value: isOpen)
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.7), value: showPlayerOfTheMonth)
        .overlay(alignment: showPlayerOfTheMonth ? .topLeading : .topTrailing) {
            // On the Player of the Month card the close button moves to the top left:
            // the red "+50" sticker sits in the top right corner of the pennant.
            Button {
                dismiss()
            } label: {
                Text("✕")
                    .displayStyle(16)
                    .foregroundStyle(closeColor)
                    .frame(width: 36, height: 36)
                    .overlay {
                        Rectangle().stroke(closeColor.opacity(0.5), lineWidth: 1.5)
                    }
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            .padding(showPlayerOfTheMonth ? .leading : .trailing, 14)
            .accessibilityLabel(Text("Close"))
        }
    }

    /// The close button sits on the yellow card of the Player of the Month and on the
    /// ink background of the ceremony.
    private var closeColor: Color {
        showPlayerOfTheMonth ? .ink : .paper
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 7, height: 7)
                Text("LIVE FROM THE GROUP CHAT")
                    .labelStyle(8.5)
                    .foregroundStyle(Color.card)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(monthName)
                    .displayStyle(52)
                    .foregroundStyle(Color.paper)
                OutlinedText(text: "AWARDS", size: 52, stroke: Color.paper, lineWidth: 1.8)
                    .frame(height: 52)
                    .accessibilityLabel(Text("Awards"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var monthName: String {
        guard let month = model.awards?.month else { return "" }
        return AwardKey.monthName(for: month).capitalized
    }

    // MARK: - Progress

    private var progress: some View {
        HStack(spacing: 4) {
            ForEach(awards.indices, id: \.self) { position in
                Rectangle()
                    .fill(position <= index ? Color.card : Color.paper.opacity(0.2))
                    .frame(height: 5)
            }
        }
    }

    // MARK: - Envelope

    private func envelope(_ award: Award) -> some View {
        ZStack(alignment: .top) {
            // The body of the envelope.
            Color.card

            // The flap of the envelope.
            EnvelopeFlapShape()
                .fill(Color(hex: 0xE8C000))
                .frame(height: 84)
                .scaleEffect(x: 1, y: isOpen ? -1 : 1, anchor: .top)
                .opacity(isOpen ? 0 : 1)

            // The text of the card.
            VStack(spacing: 0) {
                Spacer(minLength: isOpen ? 76 : 92)

                VStack(spacing: 5) {
                    Text("AWARD \(index + 1) OF \(awards.count)")
                        .labelStyle(8)
                        .foregroundStyle(Color.ink.opacity(0.7))
                    Text(award.award.title.uppercased())
                        .displayStyle(25)
                        .foregroundStyle(Color.ink)
                        .multilineTextAlignment(.center)
                    Text("AND THE WINNER IS…")
                        .labelStyle(8)
                        .foregroundStyle(Color.ink.opacity(0.7))
                        .padding(.top, 3)
                }
                .padding(.horizontal, 12)

                if isOpen, let winner = award.winners.first {
                    VStack(spacing: 4) {
                        Text(winner.avatarEmoji ?? "🏆")
                            .font(.system(size: 40))
                        Text(winner.displayName.uppercased())
                            .displayStyle(22)
                            .foregroundStyle(Color.ink)
                    }
                    .padding(.top, 12)
                    .transition(.scale.combined(with: .opacity))
                }

                Spacer(minLength: 12)
            }
            .foregroundStyle(Color.ink)

            // The seal.
            if !isOpen {
                Text("G")
                    .font(.anton(13))
                    .foregroundStyle(Color.card)
                    .frame(width: 44, height: 44)
                    .background(Color.ink, in: Circle())
                    .overlay {
                        Circle().stroke(Color.card, lineWidth: 3)
                    }
                    .offset(y: 38)
            }
        }
        .frame(height: isOpen ? 268 : 208)
        .clipShape(Rectangle())
        .brutalBorder(Color.paper)
        .hardShadow(Color.paper, offset: 6)
        .rotationEffect(.degrees(Gauntlet.Rotation.envelope))
        .onTapGesture {
            open()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text("Award \(index + 1) of \(awards.count): \(award.award.title)"))
        .accessibilityAction(named: "Open the envelope") {
            open()
        }
    }

    private func open() {
        guard !isOpen else { return }
        Haptics.vote()
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.7)) {
            isOpen = true
        }
        if reduceMotion {
            Haptics.success()
        }
    }

    // MARK: - Nominees

    private func nominees(_ award: Award) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("NOMINEES")
                .labelStyle(8)
                .foregroundStyle(Color.paper.opacity(0.6))

            HStack(spacing: 8) {
                ForEach(award.nominees) { nominee in
                    VStack(spacing: 3) {
                        Text(nominee.user.avatarEmoji ?? "🙂")
                            .font(.system(size: 18))
                        Text(nominee.user.displayName.uppercased())
                            .displayStyle(12)
                            .foregroundStyle(Color.paper)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(valueLabel(for: nominee.value))
                            .labelStyle(7)
                            .foregroundStyle(Color.paper.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 4)
                    .overlay {
                        Rectangle()
                            .stroke(Color.paper.opacity(0.4), lineWidth: 1.5)
                    }
                }
            }
        }
    }

    private func valueLabel(for value: Int) -> String {
        guard let current else { return "\(value) PTS" }
        return switch current.award {
        case .playerOfTheMonth: "\(value) PTS"
        case .goldenBoot: "\(value) GOALS"
        case .toughestRef: "\(value) CALLS"
        case .comebackKid: "▲\(value)"
        case .firstToScore: "\(value) FIRSTS"
        case .woodenSpoon: "\(value) PTS"
        }
    }

    // MARK: - Action

    private var actionButton: some View {
        SwiftUI.Group {
            if isOpen {
                Button {
                    next()
                } label: {
                    Text(index == awards.count - 1 ? "The winner of the night" : "Next award")
                        .displayStyle(17)
                        .foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Color.paper)
                        .brutalBorder(Color.paper)
                        .hardShadow(Color.card)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    open()
                } label: {
                    Text("Tap to open the envelope")
                        .displayStyle(17)
                        .foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Color.paper)
                        .brutalBorder(Color.paper)
                        .hardShadow(Color.card)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func next() {
        Haptics.success()
        if index == awards.count - 1 {
            withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.7)) {
                showPlayerOfTheMonth = true
            }
        } else {
            withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.7)) {
                index += 1
                isOpen = false
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("No awards yet")
                .displayStyle(24)
                .foregroundStyle(Color.paper)
            Text("The ceremony is on the 1st of the month.")
                .font(.subheadline)
                .foregroundStyle(Color.paper.opacity(0.6))
        }
    }
}

#Preview("Awards") {
    NavigationStack {
        AwardsNightView(model: .preview())
            .environment(AppState.preview())
    }
}
