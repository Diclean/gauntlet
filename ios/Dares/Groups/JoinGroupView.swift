import SwiftUI

/// The join of a club with an invite code.
struct JoinGroupView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.ink.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 18) {
                    Text("Join a club")
                        .displayStyle(32)
                        .foregroundStyle(Color.paper)

                    Text("INVITE CODE")
                        .labelStyle(8)
                        .foregroundStyle(Color.paper.opacity(0.7))

                    TextField("", text: $code, prompt: Text.gauntletPlaceholder("K7M2PQ", size: 24, color: Color.card.opacity(0.7)))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .tracking(4)
                        .foregroundStyle(Color.card)
                        .tint(Color.card)
                        .padding(.horizontal, 12)
                        .frame(height: 56)
                        .overlay {
                            Rectangle().stroke(Color.paper.opacity(0.4), lineWidth: 1.5)
                        }
                        .onChange(of: code) { _, newValue in
                            code = String(newValue.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
                        }

                    Text("Six characters, no zeroes, no O. Ask the club.")
                        .labelStyle(8)
                        .foregroundStyle(Color.paper.opacity(0.5))

                    if appState.isDemoMode {
                        Text("Demo: the code of Tuesday Training is prefilled.")
                            .labelStyle(8)
                            .foregroundStyle(Color.card)
                    }

                    Spacer(minLength: 0)

                    BrutalButton(title: isSubmitting ? "Joining…" : "Join the club", trailing: "→") {
                        join()
                    }
                    .disabled(code.count != 6 || isSubmitting)

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                        .foregroundStyle(Color.card)
                }
            }
            .onAppear {
                // The demo prefills the invite code of a club that really exists.
                if appState.isDemoMode, code.isEmpty {
                    code = "TRN4XP"
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

    private func join() {
        isSubmitting = true
        Task {
            do {
                let response = try await appState.api.joinGroup(
                    JoinGroupRequest(inviteCode: code)
                )
                await appState.addGroup(response.group)
                dismiss()
            } catch {
                errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
            isSubmitting = false
        }
    }
}

#Preview("Join club") {
    JoinGroupView()
        .environment(AppState.preview())
}
