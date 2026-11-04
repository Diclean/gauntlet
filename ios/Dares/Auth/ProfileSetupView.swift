import SwiftUI

/// First launch after sign in: pick a display name and an avatar emoji.
struct ProfileSetupView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var emoji = "🦊"
    @State private var isSaving = false

    private let emojis = ["🦊", "🐻", "🐼", "🐸", "🦄", "🐙", "🦖", "🐧", "🦉", "🐝", "🦁", "🐬"]

    var body: some View {
        NavigationStack {
            Form {
                Section("setup.name.section") {
                    TextField("setup.name.placeholder", text: $displayName)
                        .textContentType(.nickname)
                        .submitLabel(.done)
                }

                Section("setup.emoji.section") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(emojis, id: \.self) { candidate in
                            Button {
                                emoji = candidate
                                Haptics.selection()
                            } label: {
                                Text(candidate)
                                    .font(.system(size: 32))
                                    .frame(width: 44, height: 44)
                                    .background(
                                        candidate == emoji ? Color.accentColor.opacity(0.2) : Color.clear,
                                        in: Circle()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("setup.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("setup.save") {
                        isSaving = true
                        Task {
                            let saved = await appState.updateProfile(
                                displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                                avatarEmoji: emoji
                            )
                            isSaving = false
                            if saved { dismiss() }
                        }
                    }
                    .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
    }
}

#Preview("Profile setup") {
    ProfileSetupView()
        .environment(AppState.preview())
}
