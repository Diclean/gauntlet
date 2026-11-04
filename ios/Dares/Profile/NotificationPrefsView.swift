import SwiftUI

/// Profile → Notifications: the six push switches of the player (SPEC.md, section 6.4).
struct NotificationPrefsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var prefs = NotificationPrefs()
    @State private var isLoading = true
    @State private var errorMessage: String?

    /// The six switches, in the order of the design.
    private static let rows: [(key: String, title: String, note: String)] = [
        ("newWeek", "MATCHDAY DROP", "The new fixtures on Monday morning."),
        ("voteNeeded", "VAR CALLS", "Somebody needs your call."),
        ("result", "YOUR RESULTS", "Your proof was accepted — or thrown out."),
        ("deadline", "SUNDAY REMINDER", "The nudge of Sunday evening."),
        ("awards", "AWARDS NIGHT", "The ceremony of the month."),
        ("banter", "BANTER", "Reactions, comments and house fixtures."),
    ]

    var body: some View {
        ZStack {
            Color.ink.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Notifications")
                        .displayStyle(32)
                        .foregroundStyle(Color.paper)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    Text("SIX SWITCHES · NOTHING ELSE")
                        .labelStyle(8.5)
                        .foregroundStyle(Color.paper.opacity(0.55))
                        .padding(.horizontal, 16)
                        .padding(.top, 4)

                    VStack(spacing: 0) {
                        ForEach(Array(Self.rows.enumerated()), id: \.offset) { index, row in
                            preferenceRow(row)
                            if index < Self.rows.count - 1 {
                                Rectangle()
                                    .fill(Color.paper.opacity(0.15))
                                    .frame(height: 1.5)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                    Text("THE CLUB NEVER SENDS YOU A PUSH FOR A FIXTURE YOU DO NOT WANT TO HEAR ABOUT.")
                        .labelStyle(7.5)
                        .foregroundStyle(Color.paper.opacity(0.45))
                        .padding(.horizontal, 16)
                        .padding(.top, 16)

                    Spacer(minLength: 40)
                }
            }
            .scrollIndicators(.hidden)

            if isLoading {
                ProgressView()
                    .tint(Color.card)
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("action.done") { dismiss() }
                    .foregroundStyle(Color.card)
            }
        }
        .task { await load() }
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

    private func preferenceRow(_ row: (key: String, title: String, note: String)) -> some View {
        Button {
            toggle(row.key)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.title)
                        .displayStyle(15)
                        .foregroundStyle(Color.paper)
                    Text(row.note)
                        .labelStyle(7.5)
                        .foregroundStyle(Color.paper.opacity(0.5))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                BrutalSquareToggle(isOn: isOn(row.key))
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private func isOn(_ key: String) -> Bool {
        switch key {
        case "newWeek": prefs.newWeek
        case "voteNeeded": prefs.voteNeeded
        case "result": prefs.result
        case "deadline": prefs.deadline
        case "awards": prefs.awards
        default: prefs.banter
        }
    }

    // MARK: - Actions

    private func load() async {
        isLoading = true
        if let loaded = try? await appState.api.notificationPrefs() {
            prefs = loaded
        }
        isLoading = false
    }

    private func toggle(_ key: String) {
        switch key {
        case "newWeek": prefs.newWeek.toggle()
        case "voteNeeded": prefs.voteNeeded.toggle()
        case "result": prefs.result.toggle()
        case "deadline": prefs.deadline.toggle()
        case "awards": prefs.awards.toggle()
        default: prefs.banter.toggle()
        }
        Haptics.selection()
        let snapshot = prefs
        Task {
            do {
                let saved = try await appState.api.updateNotificationPrefs(snapshot)
                prefs = saved
            } catch {
                errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

#Preview("Notifications") {
    NotificationPrefsView()
        .environment(AppState.preview())
}
