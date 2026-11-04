import SwiftUI

/// The profile of the player: the name, the avatar and the trophy cabinet.
struct ProfileView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var emoji = "🦊"
    @State private var isSaving = false
    @State private var showingDeleteConfirmation = false
    @State private var errorMessage: String?
    @State private var trophies: [Trophy] = []
    @State private var blockedCount = 0

    private let emojis = ["🦊", "🐻", "🐼", "🐸", "🦄", "🐙", "🦖", "🐧", "🐉", "🐝", "🦁", "🐬"]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.ink.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Profile")
                            .displayStyle(34)
                            .foregroundStyle(Color.paper)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)

                        identity
                            .padding(.horizontal, 16)
                            .padding(.top, 16)

                        emojiPicker
                            .padding(.horizontal, 16)
                            .padding(.top, 16)

                        settingsLinks
                            .padding(.horizontal, 16)
                            .padding(.top, 16)

                        trophyCabinet
                            .padding(.horizontal, 16)
                            .padding(.top, 18)

                        BrutalButton(title: "Save", trailing: "→") {
                            save()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 18)
                        .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)

                        footer
                            .padding(.horizontal, 16)
                            .padding(.top, 18)

                        Spacer(minLength: 40)
                    }
                }
                .scrollIndicators(.hidden)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.close") { dismiss() }
                        .foregroundStyle(Color.card)
                }
            }
            .onAppear(perform: loadValues)
            .task {
                trophies = (try? await appState.api.trophies()) ?? []
                let blocked = (try? await appState.api.blockedUsers()) ?? []
                blockedCount = blocked.count
            }
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

    // MARK: - Pieces

    private var identity: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NAME")
                .labelStyle(8)
                .foregroundStyle(Color.paper.opacity(0.55))
            HStack(spacing: 12) {
                Text(emoji)
                    .font(.system(size: 28))
                    .frame(width: 52, height: 52)
                    .background(Color.paper.opacity(0.08))
                    .overlay {
                        Rectangle().stroke(Color.paper.opacity(0.4), lineWidth: 1.5)
                    }
                TextField("", text: $displayName, prompt: Text.gauntletPlaceholder("Your name", size: 15))
                    .textContentType(.nickname)
                    .font(.anton(20))
                    .foregroundStyle(Color.paper)
                    .tint(Color.card)
                    .padding(.horizontal, 10)
                    .frame(height: 52)
                    .overlay {
                        Rectangle().stroke(Color.paper.opacity(0.4), lineWidth: 1.5)
                    }
            }
        }
    }

    private var emojiPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AVATAR")
                .labelStyle(8)
                .foregroundStyle(Color.paper.opacity(0.55))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                ForEach(emojis, id: \.self) { candidate in
                    Button {
                        emoji = candidate
                        Haptics.selection()
                    } label: {
                        Text(candidate)
                            .font(.system(size: 24))
                            .frame(width: 44, height: 44)
                            .background(candidate == emoji ? Color.card : Color.paper.opacity(0.06))
                            .foregroundStyle(candidate == emoji ? Color.ink : Color.paper)
                            .overlay {
                                Rectangle()
                                    .stroke(
                                        candidate == emoji ? Color.card : Color.paper.opacity(0.3),
                                        lineWidth: 1.5
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// The links to the notification switches and to the blocked members.
    private var settingsLinks: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SETTINGS")
                .labelStyle(8)
                .foregroundStyle(Color.paper.opacity(0.55))

            NavigationLink {
                NotificationPrefsView()
                    .toolbarBackground(Color.ink, for: .navigationBar)
                    .toolbarColorScheme(.dark, for: .navigationBar)
            } label: {
                settingsRow(
                    icon: "bell.badge",
                    title: "NOTIFICATIONS",
                    note: "Six switches — the rest is noise."
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                BlockedUsersView()
                    .toolbarBackground(Color.ink, for: .navigationBar)
                    .toolbarColorScheme(.dark, for: .navigationBar)
            } label: {
                settingsRow(
                    icon: "hand.raised",
                    title: "BLOCKED",
                    note: blockedCount == 0
                        ? "Nobody is blocked."
                        : "\(blockedCount) MEMBER\(blockedCount == 1 ? "" : "S") BLOCKED"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func settingsRow(icon: String, title: String, note: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.ink)
                .frame(width: 44, height: 44)
                .background(Color.card)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .displayStyle(16)
                    .foregroundStyle(Color.paper)
                Text(note)
                    .labelStyle(7.5)
                    .foregroundStyle(Color.paper.opacity(0.55))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Text("→")
                .displayStyle(16)
                .foregroundStyle(Color.card)
        }
        .padding(10)
        .overlay {
            Rectangle().stroke(Color.paper.opacity(0.35), lineWidth: 1.5)
        }
        .accessibilityElement(children: .combine)
    }

    private var trophyCabinet: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TROPHY CABINET")
                .labelStyle(8)
                .foregroundStyle(Color.paper.opacity(0.55))

            NavigationLink {
                TrophyCabinetView()
                    .toolbarBackground(Color.ink, for: .navigationBar)
                    .toolbarColorScheme(.dark, for: .navigationBar)
            } label: {
            HStack(spacing: 10) {
                Text("🏆")
                    .font(.system(size: 24))
                    .frame(width: 44, height: 44)
                    .background(Color.card)
                    .foregroundStyle(Color.ink)

                VStack(alignment: .leading, spacing: 3) {
                    Text(trophies.isEmpty ? "No silverware yet." : "\(trophies.count) TROPHY\(trophies.count == 1 ? "" : "S")")
                        .displayStyle(16)
                        .foregroundStyle(Color.paper)
                    Text(trophies.isEmpty ? "Next ceremony on the 1st." : trophies.map(\.award.title).joined(separator: " · "))
                        .labelStyle(7.5)
                        .foregroundStyle(Color.paper.opacity(0.55))
                        .lineLimit(2)
                }

                Spacer(minLength: 4)

                Text("→")
                    .displayStyle(16)
                    .foregroundStyle(Color.card)
            }
            .padding(10)
            .overlay {
                Rectangle().stroke(Color.paper.opacity(0.35), lineWidth: 1.5)
            }
            .accessibilityElement(children: .combine)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            if appState.isDemoMode {
                BrutalOutlineButton(title: "Leave the demo") {
                    Task {
                        await appState.exitDemoMode()
                        dismiss()
                    }
                }
            } else {
                BrutalOutlineButton(title: "Sign out") {
                    Task {
                        await appState.signOut()
                        dismiss()
                    }
                }
            }

            Button {
                showingDeleteConfirmation = true
            } label: {
                Text("Delete account")
                    .labelStyle(9)
                    .foregroundStyle(Color.red)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .overlay {
                        Rectangle().stroke(Color.red, lineWidth: 1.5)
                    }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Actions

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
