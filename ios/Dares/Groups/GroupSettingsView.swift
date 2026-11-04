import SwiftUI

struct GroupSettingsView: View {
    let model: GroupViewModel

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var challengesPerWeek = 5
    @State private var theme = ""
    @State private var language = "en"
    @State private var timezone = ""
    @State private var isSaving = false
    @State private var showingLeaveConfirmation = false
    @State private var errorMessage: String?

    private var inviteCode: String {
        model.group?.inviteCode ?? ""
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("settings.invite.section") {
                    HStack {
                        Text(inviteCode)
                            .font(.title3.monospaced().weight(.semibold))
                        Spacer()
                        ShareLink(item: inviteShareText) {
                            Label("settings.share", systemImage: "square.and.arrow.up")
                                .labelStyle(.iconOnly)
                        }
                        .accessibilityLabel(Text("settings.share"))
                    }
                    Text("settings.invite.hint")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("settings.members.section") {
                    ForEach(model.members) { member in
                        HStack(spacing: 10) {
                            AvatarView(emoji: member.user.avatarEmoji, size: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(member.user.displayName)
                                if member.user.id == model.group?.ownerId {
                                    Text("settings.owner")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(Formatting.relative(member.joinedAt))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if model.isOwner {
                    Section("settings.group.section") {
                        TextField("group.name.placeholder", text: $name)

                        Stepper(value: $challengesPerWeek, in: 3 ... 10) {
                            HStack {
                                Text("group.challenges_per_week")
                                Spacer()
                                Text("\(challengesPerWeek)")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }

                        TextField("group.theme.placeholder", text: $theme, axis: .vertical)
                            .lineLimit(1 ... 3)

                        Picker("group.language", selection: $language) {
                            Text("language.english").tag("en")
                        }

                        TextField("group.timezone", text: $timezone)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        Text("settings.owner.note")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button {
                            save()
                        } label: {
                            if isSaving {
                                ProgressView()
                            } else {
                                Text("settings.save")
                            }
                        }
                        .disabled(isSaving)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showingLeaveConfirmation = true
                    } label: {
                        Text("settings.leave")
                    }
                }
            }
            .navigationTitle("group.settings.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.done") { dismiss() }
                }
            }
            .onAppear(perform: loadValues)
            .confirmationDialog(
                Text("settings.leave.confirm.title"),
                isPresented: $showingLeaveConfirmation,
                titleVisibility: .visible
            ) {
                Button("settings.leave", role: .destructive) { leave() }
                Button("action.cancel", role: .cancel) {}
            } message: {
                Text("settings.leave.confirm.message")
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

    private var inviteShareText: String {
        String(format: String(localized: "settings.invite.share_text"), inviteCode)
    }

    private func loadValues() {
        guard let group = model.group else { return }
        name = group.name
        challengesPerWeek = group.challengesPerWeek
        theme = group.theme ?? ""
        language = group.language
        timezone = group.timezone
    }

    private func save() {
        isSaving = true
        Task {
            let trimmedTheme = theme.trimmingCharacters(in: .whitespacesAndNewlines)
            let saved = await model.updateGroup(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                challengesPerWeek: challengesPerWeek,
                theme: trimmedTheme.isEmpty ? nil : trimmedTheme,
                language: language,
                timezone: timezone,
                api: appState.api
            )
            isSaving = false
            if saved {
                await appState.loadGroups()
            } else {
                errorMessage = model.errorMessage
            }
        }
    }

    private func leave() {
        Task {
            let left = await model.leave(api: appState.api)
            if left {
                appState.removeGroup(id: model.groupID)
                dismiss()
            } else {
                errorMessage = model.errorMessage
            }
        }
    }
}

#Preview("Group settings") {
    GroupSettingsView(model: .preview())
        .environment(AppState.preview())
}
