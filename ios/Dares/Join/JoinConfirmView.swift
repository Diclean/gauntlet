import SwiftUI

/// The invite link of a club: `gauntlet://join/<code>` and `https://<host>/join/<code>`
/// (SPEC.md, section 6.8). Both open the join confirmation — the app never joins on
/// its own.
enum InviteLink {
    /// The invite code of a link — `nil` when the link is not an invite.
    static func code(from url: URL) -> String? {
        if url.scheme?.lowercased() == "gauntlet" {
            // gauntlet://join/<code>
            let parts = ([url.host] + url.pathComponents)
                .compactMap { $0 }
                .filter { !$0.isEmpty && $0 != "/" }
            guard parts.first?.lowercased() == "join" else { return nil }
            guard parts.count > 1 else { return nil }
            return SafeIdentifier.valid(parts[1].uppercased())
        }
        // https://<host>/join/<code>
        let parts = url.pathComponents.filter { $0 != "/" }
        guard let index = parts.firstIndex(where: { $0.lowercased() == "join" }) else { return nil }
        guard parts.count > index + 1 else { return nil }
        return SafeIdentifier.valid(parts[index + 1].uppercased())
    }

    /// The link that is shared in the group chat.
    static func url(code: String, host: String) -> URL? {
        URL(string: "gauntlet://join/\(code.uppercased())")
            ?? URL(string: "\(host)/join/\(code.uppercased())")
    }
}

/// The confirmation screen of an invite: the club, its size and one button. The club
/// is never joined before the player presses the button.
struct JoinConfirmView: View {
    let code: String

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var group: Group?
    @State private var isLoading = true
    @State private var isJoining = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.ink.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 20)

                VStack(alignment: .leading, spacing: 6) {
                    Text("You are invited")
                        .displayStyle(30)
                        .foregroundStyle(Color.paper)
                    Text("JOIN THE CLUB — YOU DECIDE")
                        .labelStyle(8.5)
                        .foregroundStyle(Color.paper.opacity(0.55))
                }
                .padding(.horizontal, 18)

                Spacer(minLength: 24)

                clubCard

                Spacer(minLength: 24)

                actions

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
            .overlay {
                if isLoading {
                    Color.black.opacity(0.5)
                    ProgressView()
                        .tint(Color.card)
                }
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

    private var clubCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ClubCrest(initials: initials, size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text((group?.name ?? "CLUB").uppercased())
                        .displayStyle(22)
                        .foregroundStyle(Color.paper)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Text("\(group?.memberCount ?? 0) PLAYERS")
                        .labelStyle(8.5)
                        .foregroundStyle(Color.paper.opacity(0.6))
                }
                Spacer(minLength: 4)
            }

            HStack(spacing: 8) {
                Text("INVITE CODE")
                    .labelStyle(8)
                    .foregroundStyle(Color.paper.opacity(0.55))
                Spacer(minLength: 6)
                Text(code)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(Color.card)
            }
        }
        .padding(14)
        .overlay {
            Rectangle().stroke(Color.paper.opacity(0.4), lineWidth: 1.5)
        }
    }

    private var initials: String {
        let words = (group?.name ?? "GC").split(separator: " ")
        let letters = words.prefix(2).compactMap { $0.first.map(String.init) }
        return letters.joined().uppercased().isEmpty ? "GC" : letters.joined().uppercased()
    }

    private var actions: some View {
        VStack(spacing: 12) {
            BrutalButton(
                title: isJoining ? "JOINING…" : "JOIN THE CLUB",
                trailing: "→",
                background: .card,
                foreground: .ink,
                borderColor: .paper,
                shadowColor: .paper
            ) {
                join()
            }
            .disabled(group == nil || isJoining)
            .opacity(group == nil ? 0.5 : 1)

            BrutalOutlineButton(title: "NOT NOW") {
                dismiss()
            }

            Text("THE CLUB SEES YOUR NAME AND YOUR AVATAR. NOTHING ELSE.")
                .labelStyle(7.5)
                .foregroundStyle(Color.paper.opacity(0.45))
        }
    }

    // MARK: - Actions

    private func load() async {
        isLoading = true
        do {
            group = try await appState.api.joinPreview(code: code)
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    private func join() {
        isJoining = true
        Task {
            do {
                let response = try await appState.api.joinGroup(
                    JoinGroupRequest(inviteCode: code)
                )
                isJoining = false
                Haptics.success()
                dismiss()
                await appState.addGroup(response.group)
            } catch {
                isJoining = false
                errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
