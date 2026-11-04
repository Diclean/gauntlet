import SwiftUI

/// The creation of a club.
struct CreateGroupView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var challengesPerWeek = 5
    @State private var theme = ""
    @State private var language = "en"
    @State private var timezone = TimeZone.current.identifier
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.ink.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("New club")
                            .displayStyle(32)
                            .foregroundStyle(Color.paper)

                        group("NAME", text: $name, placeholder: "Sunday League FC")

                        HStack {
                            Text("FIXTURES PER MATCHWEEK")
                                .labelStyle(8)
                                .foregroundStyle(Color.paper.opacity(0.7))
                            Spacer(minLength: 8)
                            Stepper(value: $challengesPerWeek, in: 3 ... 10) {
                                Text("\(challengesPerWeek)")
                                    .font(.anton(16))
                                    .foregroundStyle(Color.card)
                            }
                            .labelsHidden()
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 46)
                        .overlay {
                            Rectangle().stroke(Color.paper.opacity(0.35), lineWidth: 1.5)
                        }

                        group("THEME", text: $theme, placeholder: "One kick, one dares")

                        Text("The theme goes to the club: the fixtures are written in that tone.")
                            .labelStyle(7.5)
                            .foregroundStyle(Color.paper.opacity(0.5))

                        group("TIMEZONE", text: $timezone, placeholder: "Europe/Paris")

                        BrutalButton(title: isSubmitting ? "Creating…" : "Create the club", trailing: "→") {
                            create()
                        }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)

                        Spacer(minLength: 30)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                        .foregroundStyle(Color.card)
                }
            }
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
    }

    private func group(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .labelStyle(8)
                .foregroundStyle(Color.paper.opacity(0.7))
            TextField("", text: text, prompt: Text.gauntletPlaceholder(placeholder, size: 14))
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.paper)
                .tint(Color.card)
                .padding(.horizontal, 12)
                .frame(height: 46)
                .overlay {
                    Rectangle().stroke(Color.paper.opacity(0.35), lineWidth: 1.5)
                }
        }
    }

    private func create() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTheme = theme.trimmingCharacters(in: .whitespacesAndNewlines)
        isSubmitting = true
        Task {
            let request = CreateGroupRequest(
                name: trimmedName,
                challengesPerWeek: challengesPerWeek,
                theme: trimmedTheme.isEmpty ? nil : trimmedTheme,
                language: language,
                timezone: timezone
            )
            do {
                let response = try await appState.api.createGroup(request)
                await appState.addGroup(response.group)
                dismiss()
            } catch {
                errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
            isSubmitting = false
        }
    }
}

#Preview("Create club") {
    CreateGroupView()
        .environment(AppState.preview())
}
