import SwiftUI

/// First launch after sign in: pick a display name and an avatar emoji.
struct ProfileSetupView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var emoji = "🦊"
    @State private var isSaving = false

    private let emojis = ["🦊", "🐻", "🐼", "🐸", "🦄", "🐙", "🦖", "🐧", "🐉", "🐝", "🦁", "🐬"]

    var body: some View {
        ZStack {
            Color.ink.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Text("Join the club")
                    .displayStyle(32)
                    .foregroundStyle(Color.paper)

                Text("PICK A NAME AND A FACE")
                    .labelStyle(8)
                    .foregroundStyle(Color.paper.opacity(0.55))

                TextField("", text: $displayName, prompt: Text.gauntletPlaceholder("Your name", size: 15))
                    .textContentType(.nickname)
                    .submitLabel(.done)
                    .font(.anton(22))
                    .foregroundStyle(Color.paper)
                    .tint(Color.card)
                    .padding(.horizontal, 12)
                    .frame(height: 52)
                    .overlay {
                        Rectangle().stroke(Color.paper.opacity(0.4), lineWidth: 1.5)
                    }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                    ForEach(emojis, id: \.self) { candidate in
                        Button {
                            emoji = candidate
                            Haptics.selection()
                        } label: {
                            Text(candidate)
                                .font(.system(size: 26))
                                .frame(width: 46, height: 46)
                                .background(candidate == emoji ? Color.card : Color.paper.opacity(0.06))
                                .foregroundStyle(candidate == emoji ? Color.ink : Color.paper)
                                .overlay {
                                    Rectangle().stroke(
                                        candidate == emoji ? Color.card : Color.paper.opacity(0.3),
                                        lineWidth: 1.5
                                    )
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer(minLength: 0)

                BrutalButton(title: isSaving ? "Saving…" : "Save", trailing: "→") {
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
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
    }
}

#Preview("Profile setup") {
    ProfileSetupView()
        .environment(AppState.preview())
}
