import SwiftUI

/// The detail of a fixture: the title, the difficulty, the status, the armband and
/// the veto (DESIGN.md, section 10).
struct ChallengeDetailView: View {
    let challengeID: String
    let model: GroupViewModel

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var showingCapture = false
    @State private var isWorking = false

    private var challenge: Challenge? {
        model.fixtures.first { $0.id == challengeID }
    }

    var body: some View {
        ZStack {
            Color.ink.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    if let challenge {
                        VStack(alignment: .leading, spacing: 16) {
                            titleBlock(challenge)

                            HStack(spacing: 8) {
                                MetaChip(title: challenge.difficulty.title.uppercased())
                                MetaChip(title: "\(challenge.points) PTS")
                                StatusPill(kind: StatusPill.Kind(challenge.myStatus))
                            }

                            Text(challenge.description)
                                .font(.body)
                                .foregroundStyle(Color.paper.opacity(0.75))

                            statusLine(challenge)

                            captainToggle(challenge)

                            VStack(alignment: .leading, spacing: 6) {
                                Label("The camera only — the photo library is never used.", systemImage: "lock.shield")
                                Label("One proof per fixture. Resubmit if it gets a red card.", systemImage: "info.circle")
                            }
                            .labelStyle(8)
                            .foregroundStyle(Color.paper.opacity(0.5))
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 12)
                        .padding(.bottom, 18)
                    } else {
                        ProgressView()
                            .tint(Color.card)
                            .padding()
                    }
                }
                .scrollIndicators(.hidden)

                if let challenge {
                    VStack(alignment: .leading, spacing: 14) {
                        vetoBlock(challenge)

                        BrutalButton(
                            title: "Prove it",
                            trailing: "→",
                            background: .card,
                            foreground: .ink,
                            borderColor: .paper,
                            shadowColor: .paper
                        ) {
                            showingCapture = true
                        }
                        .disabled(challenge.myStatus == .accepted)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 18)
                    .background {
                        Rectangle()
                            .fill(Color.ink)
                            .ignoresSafeArea(edges: .bottom)
                    }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.paper)
                    .frame(width: 38, height: 38)
                    .background(Color.ink.opacity(0.6))
                    .overlay {
                        Rectangle().stroke(Color.paper.opacity(0.6), lineWidth: 1.5)
                    }
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .padding(.trailing, 14)
            .accessibilityLabel(Text("Close"))
        }
        .presentationDetents([.fraction(0.76), .large])
        .presentationDragIndicator(.hidden)
        .sheet(isPresented: $showingCapture, onDismiss: {
            Task { await model.load(api: appState.api, myUserID: appState.user?.id ?? "") }
        }) {
            if let challenge {
                ProofCaptureView(challenge: challenge)
            }
        }
    }

    // MARK: - Pieces

    private func titleBlock(_ challenge: Challenge) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("FIXTURE \(String(format: "%02d", challenge.position))")
                    .labelStyle(8.5)
                    .foregroundStyle(Color.paper.opacity(0.55))
                if challenge.isNew {
                    FixtureNewPill()
                }
                if challenge.isHouse {
                    FixtureHousePill()
                }
                if challenge.isCaptain {
                    CaptainBadge(size: 18)
                }
            }
            Text(challenge.title)
                .displayStyle(28)
                .foregroundStyle(Color.paper)
                .fixedSize(horizontal: false, vertical: true)
            if let author = challenge.createdBy {
                Text("HOUSE FIXTURE BY \(author.displayName.uppercased())")
                    .labelStyle(8)
                    .foregroundStyle(Color.card.opacity(0.9))
            }
        }
    }

    @ViewBuilder
    private func statusLine(_ challenge: Challenge) -> some View {
        switch challenge.myStatus {
        case .accepted:
            statusNote("FT ✓ — the VAR confirmed your proof.", color: .pitch)
        case .pending:
            statusNote("IN VAR — the club is judging your proof.", color: .card)
        case .rejected:
            statusNote("RED ✕ — VAR said no goal. You can prove it again.", color: .red)
        case .todo:
            statusNote("TO PLAY — nobody has proved it yet.", color: .paper)
        }
    }

    private func statusNote(_ text: String, color: Color) -> some View {
        Text(text)
            .labelStyle(9)
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .overlay {
                Rectangle().stroke(color, lineWidth: 1.5)
            }
    }

    /// The armband: the captain fixture doubles the points of the fixture.
    private func captainToggle(_ challenge: Challenge) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if challenge.isCaptain, captainLocked {
                HStack(spacing: 10) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.paper.opacity(0.7))
                    Text("LOCKED — YOU'VE PLAYED IT")
                        .displayStyle(14)
                        .foregroundStyle(Color.paper.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 14)
                .frame(height: 48)
                .overlay {
                    Rectangle().stroke(Color.paper.opacity(0.35), lineWidth: 1.5)
                }
                .accessibilityElement(children: .combine)
            } else {
                Button {
                    makeCaptain(challenge)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(challenge.isCaptain ? Color.ink : Color.paper)
                        Text(challenge.isCaptain ? "CAPTAIN · ×2" : "MAKE CAPTAIN · ×2")
                            .displayStyle(15)
                            .foregroundStyle(challenge.isCaptain ? Color.ink : Color.paper)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(challenge.isCaptain ? Color.card : Color.clear)
                    .overlay {
                        Rectangle().stroke(challenge.isCaptain ? Color.card : Color.paper, lineWidth: 2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isWorking || captainLocked)
                .opacity(captainLocked ? 0.45 : 1)
                .accessibilityElement(children: .combine)
            }

            Text(captainNote(challenge))
                .labelStyle(7.5)
                .foregroundStyle(Color.paper.opacity(0.45))
        }
    }

    /// The note under the armband.
    private func captainNote(_ challenge: Challenge) -> String {
        if captainLocked {
            if challenge.isCaptain {
                return "THE ARMBAND DOUBLES THE FIXTURE — THE FIRST TO SCORE BONUS STAYS THE SAME."
            }
            return "THE ARMBAND IS LOCKED — YOU ALREADY PLAYED YOUR CAPTAIN FIXTURE."
        }
        return "THE ARMBAND DOUBLES THE FIXTURE — THE FIRST TO SCORE BONUS STAYS THE SAME."
    }

    /// The veto: the club can replace a fixture that nobody wants to play.
    private func vetoBlock(_ challenge: Challenge) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("\(challenge.vetoCount) / \(challenge.vetoThreshold) VETOES")
                    .labelStyle(9)
                    .foregroundStyle(Color.paper.opacity(0.7))
                Spacer(minLength: 4)
                if vetoLimitReached {
                    Text("2 VETOES USED THIS WEEK")
                        .labelStyle(8)
                        .foregroundStyle(Color.red)
                }
            }

            Button {
                veto(challenge)
            } label: {
                Text(challenge.myVeto ? "VETOED — TAP TO UNDO" : "VETO THIS FIXTURE")
                    .displayStyle(15)
                    .foregroundStyle(challenge.myVeto ? Color.ink : Color.red)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(challenge.myVeto ? Color.red : Color.clear)
                    .overlay {
                        Rectangle().stroke(Color.red, lineWidth: 2)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isWorking || (vetoLimitReached && !challenge.myVeto))
            .opacity(vetoLimitReached && !challenge.myVeto ? 0.5 : 1)

            Text("HALF OF THE CLUB REPLACES THE FIXTURE. TWO REPLACEMENTS PER MATCHWEEK.")
                .labelStyle(7.5)
                .foregroundStyle(Color.paper.opacity(0.45))
        }
    }

    // MARK: - State

    /// The armband is locked as soon as I have a proof on my captain fixture.
    private var captainLocked: Bool {
        guard let captain = model.captainFixture else { return false }
        return captain.myStatus == .accepted || captain.myStatus == .pending
    }

    /// The club used both replacements of the matchweek.
    private var vetoLimitReached: Bool {
        (model.week?.vetoesUsed ?? 0) >= 2
    }

    // MARK: - Actions

    private func makeCaptain(_ challenge: Challenge) {
        isWorking = true
        Task {
            let ok = await model.setCaptain(challengeID: challenge.id, api: appState.api)
            isWorking = false
            if ok { Haptics.success() }
        }
    }

    private func veto(_ challenge: Challenge) {
        isWorking = true
        Task {
            let response = await model.veto(challengeID: challenge.id, api: appState.api)
            isWorking = false
            guard let response else { return }
            Haptics.vote()
            if response.replaced {
                dismiss()
            }
        }
    }
}

/// A small chip with the difficulty or the points of a fixture.
struct MetaChip: View {
    let title: String
    var color: Color = .paper

    var body: some View {
        Text(title)
            .labelStyle(8.5)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .overlay {
                Rectangle().stroke(color, lineWidth: 1.5)
            }
    }
}

#Preview("Fixture") {
    NavigationStack {
        ChallengeDetailView(challengeID: MockData.challenges[0].id, model: .preview())
            .environment(AppState.preview())
    }
}
