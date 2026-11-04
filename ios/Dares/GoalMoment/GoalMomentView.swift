import SwiftUI

/// Screen 3 — the moment a proof is accepted (or rejected) by the VAR.
struct GoalMomentView: View {
    let submission: Submission
    let confirmedBy: [User]
    /// The points of the accepted fixture.
    let points: Int
    /// The streak of the player, in weeks.
    let streak: Int
    /// True when the proof was thrown out.
    let isAccepted: Bool
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            (isAccepted ? Color.pitch : Color.red)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 20)

                title

                Spacer(minLength: 8)

                polaroid
                    .padding(.top, 10)
                    .overlay(alignment: .topTrailing) {
                        Text("+\(points)")
                            .font(.anton(30))
                            .foregroundStyle(Color.ink)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.card)
                            .overlay {
                                Rectangle().stroke(Color.ink, lineWidth: 2)
                            }
                            .hardShadow(Color.ink, offset: 3)
                            .rotationEffect(.degrees(Gauntlet.Rotation.plus25))
                            .offset(x: 14, y: -12)
                    }

                Spacer(minLength: 10)

                confirmation

                bonusChips
                    .padding(.top, 12)

                Spacer(minLength: 16)

                Button {
                    onDismiss()
                } label: {
                    Text(isAccepted ? "Back to matchday" : "Back to matchday")
                        .displayStyle(17)
                        .foregroundStyle(isAccepted ? Color.paper : Color.paper)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.ink)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 22)
                .padding(.bottom, 16)
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Pieces

    private var title: some View {
        VStack(spacing: 6) {
            Text(isAccepted ? "Goal!" : "No goal")
                .displayStyle(108)
                .foregroundStyle(isAccepted ? Color.ink : Color.paper)
                .rotationEffect(.degrees(Gauntlet.Rotation.goal))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(isAccepted ? "VAR confirms" : "VAR overturned")
                .displayStyle(22)
                .tracking(1.6)
                .foregroundStyle(isAccepted ? Color.ink : Color.paper)
        }
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(isAccepted ? "Goal! VAR confirms" : "No goal. VAR overturned"))
    }

    private var polaroid: some View {
        VStack(spacing: 0) {
            ProofMediaView(submission: submission)
                .frame(width: 132, height: 136)
                .clipped()

            Text(submission.challengeTitle.uppercased())
                .labelStyle(7.5)
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, 6)
        }
        .padding(7)
        .padding(.bottom, 18)
        .background(Color.paper)
        .brutalBorder(Color.ink)
        .hardShadow(Color.ink, offset: 5)
        .rotationEffect(.degrees(Gauntlet.Rotation.polaroid))
        .accessibilityHidden(true)
    }

    private var confirmation: some View {
        VStack(spacing: 2) {
            Text(confirmedByText)
                .labelStyle(10)
            Text("\(confirmedBy.count) / \(max(confirmedBy.count, 2)) CALLS · DECISION FINAL")                .labelStyle(10)
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(isAccepted ? Color.ink : Color.paper)
        .padding(.horizontal, 22)
    }

    private var confirmedByText: String {
        let names = confirmedBy.map { "\($0.avatarEmoji ?? "") \($0.displayName)".trimmingCharacters(in: .whitespaces) }
        if names.isEmpty {
            return isAccepted ? "CONFIRMED BY THE VAR" : "THROWN OUT BY THE VAR"
        }
        return "CONFIRMED BY " + names.joined(separator: " + ")
    }

    private var bonusChips: some View {
        HStack(spacing: 8) {
            if isAccepted {
                Text("First to score +10")
                    .displayStyle(13)
                    .foregroundStyle(Color.card)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.ink)
                    .brutalBorder(Color.ink)
            } else {
                Text("No points this week")
                    .displayStyle(13)
                    .foregroundStyle(Color.paper)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.ink)
                    .brutalBorder(Color.ink)
            }

            Text(streak > 0 ? "🔥 \(streak)-week streak" : "No streak")
                .displayStyle(13)
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.card)
                .brutalBorder(Color.ink)
        }
        .padding(.horizontal, 22)
    }
}

#Preview("Goal") {
    GoalMomentView(
        submission: MockData.submissions[1],
        confirmedBy: [MockData.other, MockData.friend],
        points: 25,
        streak: 4,
        isAccepted: true
    ) { }
}
