import SwiftUI

struct ProfileView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var emoji = "🦊"
    @State private var isSaving = false
    @State private var showingDeleteConfirmation = false
    @State private var errorMessage: String?

    private let emojis = ["🦊", "🐻", "🐼", "🐸", "🦄", "🐙", "🦖", "🐧", "🦉", "🐝", "🦁", "🐬"]

    var body: some View {
        NavigationStack {
            Form {
                Section("profile.section.identity") {
                    HStack(spacing: 14) {
                        AvatarView(emoji: emoji, size: 56)
                        TextField("profile.name.placeholder", text: $displayName)
                            .textContentType(.nickname)
                    }

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                        ForEach(emojis, id: \.self) { candidate in
                            Button {
                                emoji = candidate
                                Haptics.selection()
                            } label: {
                                Text(candidate)
                                    .font(.system(size: 28))
                                    .frame(width: 42, height: 42)
                                    .background(
                                        candidate == emoji ? Color.accentColor.opacity(0.2) : Color.clear,
                                        in: Circle()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)

                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("profile.save")
                        }
                    }
                    .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }

                if appState.isDemoMode {
                    Section {
                        Button("demo.exit") {
                            Task {
                                await appState.exitDemoMode()
                                dismiss()
                            }
                        }
                    } footer: {
                        Text("demo.exit.hint")
                    }
                } else {
                    Section {
                        Button("profile.sign_out") {
                            Task {
                                await appState.signOut()
                                dismiss()
                            }
                        }
                    }
                }

                Section {
                    Button("profile.delete", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                } footer: {
                    Text("profile.delete.hint")
                }
            }
            .navigationTitle("profile.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.close") { dismiss() }
                }
            }
            .onAppear(perform: loadValues)
            .confirmationDialog(
                Text("profile.delete.confirm.title"),
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("profile.delete", role: .destructive) { deleteAccount() }
                Button("action.cancel", role: .cancel) {}
            } message: {
                Text("profile.delete.confirm.message")
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

    private func loadValues() {
        guard let user = appState.user else { return }
        displayName = user.displayName
        emoji = user.avatarEmoji ?? "🙂"
    }

    private func save() {
        isSaving = true
        Task {
            let saved = await appState.updateProfile(
                displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                avatarEmoji: emoji
            )
            isSaving = false
            if saved {
                Haptics.success()
                dismiss()
            }
        }
    }

    private func deleteAccount() {
        Task {
            let deleted = await appState.deleteAccount()
            if deleted {
                dismiss()
            } else {
                errorMessage = appState.errorMessage
            }
        }
    }
}

#Preview("Profile") {
    ProfileView()
        .environment(AppState.preview())
}
