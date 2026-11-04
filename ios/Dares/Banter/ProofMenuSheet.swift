import SwiftUI

/// The "⋯" menu of a proof: report it, block its author or delete it (DESIGN.md,
/// section 10).
struct ProofMenuSheet: View {
    enum Stage: Equatable {
        case menu
        case report
        case confirmBlock
        case confirmDelete
    }

    let submission: Submission
    let myUserID: String
    let api: any APIClientProtocol

    var onDeleted: () -> Void
    var onReported: () -> Void
    var onBlocked: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var stage: Stage = .menu
    @State private var reason: ReportReason?
    @State private var note = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var isMine: Bool { submission.user.id == myUserID }

    var body: some View {
        ZStack {
            Color.ink.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        switch stage {
                        case .menu:
                            menuRows
                        case .report:
                            reportRows
                        case .confirmBlock:
                            confirmBlock
                        case .confirmDelete:
                            confirmDelete
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
            }
        }
        .presentationBackground(Color.ink)
        .presentationDetents(stage == .report ? [.fraction(0.85), .large] : [.height(330), .medium, .large])
        .presentationDragIndicator(.hidden)
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

    private var header: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(headline)
                    .displayStyle(24)
                    .foregroundStyle(Color.paper)
                Text(subtitle)
                    .labelStyle(8)
                    .foregroundStyle(Color.paper.opacity(0.55))
            }
            Spacer(minLength: 6)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.paper)
                    .frame(width: 34, height: 34)
                    .overlay {
                        Rectangle().stroke(Color.paper.opacity(0.6), lineWidth: 1.5)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Close"))
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var headline: String {
        switch stage {
        case .menu: "Proof"
        case .report: "Report proof"
        case .confirmBlock: "Block \(submission.user.displayName)?"
        case .confirmDelete: "Delete your proof?"
        }
    }

    private var subtitle: String {
        switch stage {
        case .menu: submission.challengeTitle.uppercased()
        case .report: "SAY WHY — IT IS HIDDEN FOR YOU AT ONCE"
        case .confirmBlock: "YOU WILL NOT SEE THEIR PROOF ANYMORE"
        case .confirmDelete: "POINTS FOR THIS FIXTURE WILL BE REMOVED"
        }
    }

    private var menuRows: some View {
        VStack(spacing: 10) {
            if !isMine {
                BrutalRowButton(
                    title: "REPORT PROOF",
                    systemImage: "exclamationmark.bubble"
                ) {
                    stage = .report
                }

                BrutalRowButton(
                    title: "BLOCK \(submission.user.displayName.uppercased())",
                    systemImage: "hand.raised",
                    isDestructive: true
                ) {
                    stage = .confirmBlock
                }
            }

            if isMine {
                BrutalRowButton(
                    title: "DELETE MY PROOF",
                    systemImage: "trash",
                    isDestructive: true
                ) {
                    stage = .confirmDelete
                }
            }

            Text("REPORTED CONTENT IS HIDDEN FOR YOU. BLOCKING IS SILENT.")
                .labelStyle(7.5)
                .foregroundStyle(Color.paper.opacity(0.45))
                .padding(.top, 4)
        }
    }

    private var reportRows: some View {
        VStack(spacing: 10) {
            ForEach(ReportReason.allCases) { candidate in
                Button {
                    reason = candidate
                    Haptics.selection()
                } label: {
                    BrutalRowLabel(
                        title: candidate.title.uppercased(),
                        systemImage: icon(for: candidate),
                        isSelected: reason == candidate
                    )
                }
                .buttonStyle(.plain)
            }

            TextField(
                "",
                text: $note,
                prompt: Text.gauntletPlaceholder("A note for the owner (optional)", size: 12),
                axis: .vertical
            )
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.paper)
                .tint(Color.card)
                .lineLimit(1 ... 3)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .overlay {
                    Rectangle().stroke(Color.paper.opacity(0.45), lineWidth: 1.5)
                }

            BrutalButton(
                title: isWorking ? "REPORTING…" : "REPORT",
                trailing: "→",
                background: .card,
                foreground: .ink,
                borderColor: .paper,
                shadowColor: .paper
            ) {
                report()
            }
            .disabled(reason == nil || isWorking)
            .opacity(reason == nil ? 0.5 : 1)
        }
    }

    private var confirmBlock: some View {
        VStack(spacing: 12) {
            Text("You will not see the proofs or the comments of \(submission.user.displayName) anymore. They are not told about it.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.paper.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)

            BrutalRowButton(
                title: "BLOCK \(submission.user.displayName.uppercased())",
                systemImage: "hand.raised",
                isDestructive: true
            ) {
                block()
            }

            BrutalRowButton(title: "NOT NOW", systemImage: "arrow.uturn.backward") {
                stage = .menu
            }
        }
    }

    private var confirmDelete: some View {
        VStack(spacing: 12) {
            Text("Your proof and the points of this fixture are removed. The other members do not see it any more.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.paper.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)

            BrutalRowButton(
                title: "DELETE MY PROOF",
                systemImage: "trash",
                isDestructive: true
            ) {
                delete()
            }

            BrutalRowButton(title: "KEEP IT", systemImage: "arrow.uturn.backward") {
                stage = .menu
            }
        }
    }

    private func icon(for reason: ReportReason) -> String {
        switch reason {
        case .nudity: "eye.slash"
        case .violence: "burst"
        case .harassment: "exclamationmark.bubble"
        case .dangerous: "exclamationmark.triangle"
        case .spam: "envelope.badge"
        case .other: "ellipsis.circle"
        }
    }

    // MARK: - Actions

    private func report() {
        guard let reason else { return }
        isWorking = true
        Task {
            do {
                _ = try await api.reportSubmission(
                    id: submission.id,
                    request: ReportRequest(
                        reason: reason,
                        note: note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    )
                )
                isWorking = false
                dismiss()
                onReported()
            } catch {
                isWorking = false
                errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func block() {
        isWorking = true
        Task {
            do {
                _ = try await api.blockUser(submission.user.id)
                isWorking = false
                dismiss()
                onBlocked()
            } catch {
                isWorking = false
                errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func delete() {
        isWorking = true
        Task {
            do {
                _ = try await api.deleteSubmission(id: submission.id)
                isWorking = false
                dismiss()
                onDeleted()
            } catch {
                isWorking = false
                errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
