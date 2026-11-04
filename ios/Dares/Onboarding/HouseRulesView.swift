import SwiftUI

/// The house rules of the club (DESIGN.md, section 10). The player has to accept them
/// before the app lets them into a club (SPEC.md, section 6.1).
struct HouseRulesView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var isAccepted = false
    @State private var isSaving = false

    /// The four rules of the house.
    private static let rules: [(number: String, text: String)] = [
        ("01", "Real proof only, live camera."),
        ("02", "No nudity, no hate, no dangerous stunts."),
        ("03", "Bad content gets reported and removed."),
        ("04", "Abusers get blocked and kicked."),
    ]

    var body: some View {
        ZStack {
            Color.ink.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Self.rules, id: \.number) { rule in
                            ruleRow(rule)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay {
                        Rectangle().stroke(Color.paper.opacity(0.35), lineWidth: 1.5)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                }
                .scrollIndicators(.hidden)

                Spacer(minLength: 0)

                footer
            }
            .padding(.bottom, 18)
        }
        .interactiveDismissDisabled()
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("House rules")
                .displayStyle(34)
                .foregroundStyle(Color.paper)
            Text("BEFORE YOU PLAY — READ THE RULES")
                .labelStyle(8.5)
                .foregroundStyle(Color.paper.opacity(0.55))
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
    }

    private func ruleRow(_ rule: (number: String, text: String)) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(rule.number)
                .font(.anton(24))
                .tracking(0.5)
                .foregroundStyle(Color.card)
                .frame(width: 36, alignment: .leading)
            Text(rule.text)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.paper.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                isAccepted.toggle()
                Haptics.selection()
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Rectangle()
                            .fill(isAccepted ? Color.card : Color.clear)
                        Rectangle()
                            .stroke(isAccepted ? Color.card : Color.paper.opacity(0.7), lineWidth: 2)
                        if isAccepted {
                            Image(systemName: "checkmark")
                                .font(.system(size: 15, weight: .black))
                                .foregroundStyle(Color.ink)
                        }
                    }
                    .frame(width: 28, height: 28)

                    Text("I READ THE RULES")
                        .labelStyle(9)
                        .foregroundStyle(Color.paper)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("I read the rules"))
            .accessibilityValue(Text(isAccepted ? "checked" : "unchecked"))

            BrutalButton(
                title: isSaving ? "SAVING…" : "I'M IN",
                trailing: "→",
                background: .card,
                foreground: .ink,
                borderColor: .paper,
                shadowColor: .paper
            ) {
                accept()
            }
            .disabled(!isAccepted || isSaving)
            .opacity(isAccepted ? 1 : 0.5)

            Text("THE HOUSE RULES KEEP THE CLUB SAFE. YOU CAN READ THEM AGAIN IN YOUR PROFILE.")
                .labelStyle(7.5)
                .foregroundStyle(Color.paper.opacity(0.45))
        }
        .padding(.horizontal, 18)
    }

    // MARK: - Actions

    private func accept() {
        isSaving = true
        Task {
            let accepted = await appState.acceptTerms()
            isSaving = false
            if accepted {
                Haptics.success()
                dismiss()
            }
        }
    }
}

#Preview("House rules") {
    HouseRulesView()
        .environment(AppState.preview())
}
