import SwiftUI

// MARK: - Reaction chips

/// The six reactions of the banter as square bordered chips (DESIGN.md, section 10).
struct ReactionChips: View {
    let reactions: [Reaction]
    var compact: Bool = false
    var onToggle: (ReactionEmoji) -> Void

    var body: some View {
        HStack(spacing: compact ? 3 : 5) {
            ForEach(reactions) { reaction in
                if let emoji = reaction.reaction {
                    Button {
                        onToggle(emoji)
                    } label: {
                        HStack(spacing: 2) {
                            Text(emoji.rawValue)
                                .font(.system(size: compact ? 11 : 13))
                            Text("\(reaction.count)")
                                .labelStyle(compact ? 7 : 8)
                                .foregroundStyle(reaction.mine ? Color.ink : Color.paper.opacity(0.8))
                        }
                        .padding(.horizontal, compact ? 4 : 6)
                        .padding(.vertical, compact ? 3 : 4)
                        .background(reaction.mine ? Color.card : Color.clear)
                        .overlay {
                            Rectangle()
                                .stroke(
                                    reaction.mine ? Color.card : Color.paper.opacity(0.5),
                                    lineWidth: 1.5
                                )
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("\(emoji.rawValue), \(reaction.count)"))
                }
            }
        }
    }
}

// MARK: - Banter bar

/// The row of the banter under a proof: the reactions and the chip that opens the
/// comments.
struct BanterBar: View {
    let submission: Submission
    var compact: Bool = false
    var onToggleReaction: (ReactionEmoji) -> Void
    var onOpenBanter: () -> Void

    /// The number of comments of the proof.
    private var commentCount: Int { submission.commentCount }

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            ReactionChips(
                reactions: Array(submission.reactions.prefix(compact ? 2 : 6)),
                compact: compact,
                onToggle: onToggleReaction
            )

            if commentCount > 0 || !submission.reactions.isEmpty {
                Button {
                    onOpenBanter()
                } label: {
                    Text("BANTER · \(commentCount)")
                        .labelStyle(compact ? 7 : 8)
                        .foregroundStyle(Color.paper)
                        .padding(.horizontal, compact ? 5 : 7)
                        .padding(.vertical, compact ? 3 : 4)
                        .overlay {
                            Rectangle().stroke(Color.paper.opacity(0.5), lineWidth: 1.5)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Banter, \(commentCount) comment\(commentCount == 1 ? "" : "s")"))
            }
        }
    }
}

// MARK: - Banter sheet

/// The bottom sheet of the banter: the comments of a proof and the input bar.
struct BanterSheet: View {
    let submission: Submission
    let api: any APIClientProtocol

    @Environment(\.dismiss) private var dismiss

    @State private var comments: [Comment] = []
    @State private var draft = ""
    @State private var isLoading = true
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.ink.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header

                Divider()
                    .overlay(Color.paper.opacity(0.25))

                if isLoading {
                    ProgressView()
                        .tint(Color.card)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if comments.isEmpty {
                    emptyState
                } else {
                    commentList
                }

                inputBar
            }
        }
        .presentationBackground(Color.ink)
        .presentationDetents([.fraction(0.62), .large])
        .presentationDragIndicator(.hidden)
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

    private var header: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Text("Banter")
                .displayStyle(28)
                .foregroundStyle(Color.paper)
            Text("\(comments.count) COMMENT\(comments.count == 1 ? "" : "S")")
                .labelStyle(8.5)
                .foregroundStyle(Color.paper.opacity(0.55))
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

    private var commentList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(comments) { comment in
                    commentRow(comment)
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
    }

    private func commentRow(_ comment: Comment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(comment.user.avatarEmoji ?? "🙂")
                .font(.system(size: 18))
                .frame(width: 28, height: 28)
                .background(Color.paper.opacity(0.08))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(comment.user.displayName.uppercased())
                        .displayStyle(13)
                        .foregroundStyle(Color.paper)
                    Text(Formatting.relative(comment.createdAt).uppercased())
                        .labelStyle(7.5)
                        .foregroundStyle(Color.paper.opacity(0.45))
                }
                Text(comment.text)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color.paper.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 12)
        }
        .contextMenu {
            if comment.canDelete {
                Button(role: .destructive) {
                    Task { await delete(comment) }
                } label: {
                    Label("Delete comment", systemImage: "trash")
                }
            } else {
                Button(role: .destructive) {
                    Task { await report(comment) }
                } label: {
                    Label("Report comment", systemImage: "exclamationmark.bubble")
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No banter yet")
                .displayStyle(20)
                .foregroundStyle(Color.paper)
            Text("Say something nice — or something very funny.")
                .font(.subheadline)
                .foregroundStyle(Color.paper.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 30)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("", text: $draft, prompt: Text.gauntletPlaceholder("Say something…"))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.paper)
                .tint(Color.card)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .overlay {
                    Rectangle().stroke(Color.paper.opacity(0.6), lineWidth: 1.5)
                }
                .submitLabel(.send)
                .onSubmit(send)

            Button {
                send()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(Color.ink)
                    .frame(width: 44, height: 44)
                    .background(Color.card)
                    .overlay {
                        Rectangle().stroke(Color.paper, lineWidth: 1.5)
                    }
            }
            .buttonStyle(.plain)
            .disabled(isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
            .accessibilityLabel(Text("Send"))
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background {
            Rectangle()
                .fill(Color.paper.opacity(0.06))
                .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: - Actions

    private func load() async {
        isLoading = true
        do {
            comments = try await api.comments(submissionID: submission.id)
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSending = true
        Task {
            do {
                let comment = try await api.addComment(submissionID: submission.id, text: text)
                comments.append(comment)
                draft = ""
                Haptics.selection()
            } catch {
                errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
            isSending = false
        }
    }

    private func delete(_ comment: Comment) async {
        do {
            _ = try await api.deleteComment(id: comment.id)
            comments.removeAll { $0.id == comment.id }
            Haptics.selection()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func report(_ comment: Comment) async {
        do {
            _ = try await api.reportComment(
                id: comment.id,
                request: ReportRequest(reason: .harassment)
            )
            comments.removeAll { $0.id == comment.id }
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
