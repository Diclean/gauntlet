import SwiftUI

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
            Form {
                Section("group.section.name") {
                    TextField("group.name.placeholder", text: $name)
                        .textContentType(.organizationName)
                }

                Section("group.section.challenges") {
                    Stepper(value: $challengesPerWeek, in: 3 ... 10) {
                        HStack {
                            Text("group.challenges_per_week")
                            Spacer()
                            Text("\(challengesPerWeek)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }

                Section("group.section.theme") {
                    TextField("group.theme.placeholder", text: $theme, axis: .vertical)
                        .lineLimit(1 ... 3)
                    Text("group.theme.hint")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("group.section.advanced") {
                    Picker("group.language", selection: $language) {
                        Text("language.english").tag("en")
                        Text("language.french").disabled(true).tag("fr")
                    }
                    TextField("group.timezone", text: $timezone)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("group.create.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.create") { create() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                }
            }
            .overlay {
                if isSubmitting {
                    ProgressView()
                        .padding(12)
                        .background(.regularMaterial, in: .rect(cornerRadius: 10))
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

#Preview("Create group") {
    CreateGroupView()
        .environment(AppState.preview())
}
