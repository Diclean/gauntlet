import SwiftUI

/// Profile → Blocked: the members the player blocked (SPEC.md, section 6.2).
/// The block is one way and silent — the other member never hears about it.
struct BlockedUsersView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var users: [User] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.ink.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Blocked")
                        .displayStyle(32)
                        .foregroundStyle(Color.paper)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    Text("THEIR PROOFS AND COMMENTS ARE GONE FOR YOU")
                        .labelStyle(8.5)
                        .foregroundStyle(Color.paper.opacity(0.55))
                        .padding(.horizontal, 16)
                        .padding(.top, 4)

                    if isLoading {
                        ProgressView()
                            .tint(Color.card)
                            .padding(.top, 40)
                    } else if users.isEmpty {
                        emptyState
                            .padding(.horizontal, 16)
                            .padding(.top, 30)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(users.enumerated()), id: \.element.id) { index, user in
                                row(user)
                                if index < users.count - 1 {
                                    Rectangle()
                                        .fill(Color.paper.opacity(0.15))
                                        .frame(height: 1.5)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                    }

                    Spacer(minLength: 40)
                }
            }
            .scrollIndicators(.hidden)
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

    private func row(_ user: User) -> some View {
        HStack(spacing: 12) {
            Text(user.avatarEmoji ?? "🙂")
                .font(.system(size: 18))
                .frame(width: 32, height: 32)
                .background(Color.paper.opacity(0.08))
            Text(user.displayName.uppercased())
                .displayStyle(15)
                .foregroundStyle(Color.paper)
            Spacer(minLength: 6)
            Button {
                unblock(user)
            } label: {
                Text("UNBLOCK")
                    .labelStyle(8)
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.card)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("Nobody blocked")
                .displayStyle(22)
                .foregroundStyle(Color.paper)
            Text("When somebody is out of line, block them here.")
                .font(.subheadline)
                .foregroundStyle(Color.paper.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .overlay {
            Rectangle().stroke(Color.paper.opacity(0.3), lineWidth: 1.5)
        }
    }

    // MARK: - Actions

    private func load() async {
        isLoading = true
        do {
            users = try await appState.api.blockedUsers()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    private func unblock(_ user: User) {
        Task {
            do {
                _ = try await appState.api.unblockUser(user.id)
                users.removeAll { $0.id == user.id }
                Haptics.selection()
            } catch {
                errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

#Preview("Blocked") {
    BlockedUsersView()
        .environment(AppState.preview())
}
