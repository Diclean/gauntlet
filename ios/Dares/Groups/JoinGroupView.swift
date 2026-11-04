import SwiftUI

struct JoinGroupView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("join.section.code") {
                    TextField("join.code.placeholder", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.title2.monospaced())
                        .onChange(of: code) { _, newValue in
                            code = String(newValue.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
                        }
                }

                Section {
                    Text("join.hint")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if appState.isDemoMode {
                        Text("demo.join.hint")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("join.title")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // The demo prefills the invite code of a group that really exists.
                if appState.isDemoMode, code.isEmpty {
                    code = "PL4XZ9"
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.join") { join() }
                        .disabled(code.count != 6 || isSubmitting)
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

#Preview("Join group") {
    JoinGroupView()
        .environment(AppState.preview())
}
