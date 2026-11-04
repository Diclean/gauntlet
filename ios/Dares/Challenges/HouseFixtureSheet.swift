import SwiftUI

/// The sheet that writes the house fixture of the matchweek (DESIGN.md, section 10).
struct HouseFixtureSheet: View {
    let groupID: String
    let api: any APIClientProtocol

    var onAdded: (Challenge) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var description = ""
    @State private var difficulty: Difficulty = .easy
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.ink.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        field(title: "THE FIXTURE", placeholder: "Sunset on the gasometer", text: $title)
                        field(
                            title: "THE RULES",
                            placeholder: "One photo, one bottle, no excuses.",
                            text: $description
                        )

                        difficultyPicker
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                }
                .scrollIndicators(.hidden)

                BrutalButton(
                    title: isSaving ? "DROPPING…" : "DROP IT",
                    trailing: "→",
                    background: .card,
                    foreground: .ink,
                    borderColor: .paper,
                    shadowColor: .paper
                ) {
                    save()
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 || isSaving)
                .opacity(title.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 ? 0.5 : 1)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 18)
            }
        }
        .presentationBackground(Color.ink)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .alert(
            Text("alert.error.title"),
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            ),
            actions: { Button("alert.ok") { errorMessage = nil } },
            message: { Text(errorMessage ?? "") }
        )
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("House fixture")
                    .displayStyle(28)
                    .foregroundStyle(Color.paper)
                Text("ONE EXTRA FIXTURE · WRITTEN BY THE MAN OF THE MATCH")
                    .labelStyle(8)
                    .foregroundStyle(Color.paper.opacity(0.55))
            }
            Spacer(minLength: 6)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.paper)
                    .frame(width: 34, height: 34)
                    .overlay {
                        Rectangle().stroke(Color.paper.opacity(0.6), lineWidth: 1.5)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Close"))
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private func field(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .labelStyle(8)
                .foregroundStyle(Color.paper.opacity(0.6))
            TextField("", text: text, prompt: Text.gauntletPlaceholder(placeholder), axis: .vertical)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.paper)
                .tint(Color.card)
                .lineLimit(1 ... 3)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .overlay {
                    Rectangle().stroke(Color.paper.opacity(0.5), lineWidth: 1.5)
                }
        }
    }

    private var difficultyPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DIFFICULTY")
                .labelStyle(8)
                .foregroundStyle(Color.paper.opacity(0.6))
            BrutalSegmented(
                options: Difficulty.allCases.map { candidate in
                    BrutalSegmented.Option(
                        value: candidate,
                        title: "\(candidate.title.uppercased()) \(DemoStore.points(for: candidate))"
                    )
                },
                selection: $difficulty
            )
        }
    }

    // MARK: - Actions

    private func save() {
        isSaving = true
        Task {
            do {
                let challenge = try await api.addHouseFixture(
                    groupID: groupID,
                    request: HouseFixtureRequest(
                        title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                        description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                        difficulty: difficulty
                    )
                )
                isSaving = false
                Haptics.success()
                dismiss()
                onAdded(challenge)
            } catch {
                isSaving = false
                errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
