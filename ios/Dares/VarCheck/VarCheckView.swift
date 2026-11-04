import SwiftUI

/// Screen 2 — VAR check. The card stack, the swipe, the two calls and the undo toast.
struct VarCheckView: View {
    let model: GroupViewModel

    @Environment(AppState.self) private var appState
    @State private var dragOffset: CGSize = .zero
    @State private var isFlying = false
    @State private var undoCall: UndoCall?
    @State private var isLoading = false
    /// How many calls I already made in this matchweek.
    @State private var madeCalls = 0
    /// The proof I just called — the banter of the VAR card is only open after the call.
    @State private var calledCard: Submission?
    @State private var menuSubmission: Submission?
    @State private var banterSubmission: Submission?
    @State private var toast = ToastModel()

    /// The call that can still be taken back.
    struct UndoCall: Identifiable, Equatable {
        let id: String
        let submissionID: String
        let approve: Bool
        let canUndo: Bool
    }

    private var queue: [Submission] {
        model.pendingVotes
    }

    private var top: Submission? {
        queue.first
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(hex: 0x111111).ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 18)
                    .padding(.top, 8)

                if let top {
                    cardStack(top)
                        .padding(.top, 14)

                    if let calledCard {
                        banterBar(calledCard)
                            .padding(.horizontal, 18)
                            .padding(.top, 12)
                    }
                } else {
                    emptyState
                        .padding(.top, 40)
                }

                Spacer(minLength: 0)

                hint
                    .padding(.bottom, 12)

                if top != nil {
                    calls
                        .padding(.horizontal, 18)
                        .padding(.bottom, 84)
                } else {
                    Spacer().frame(height: 84)
                }
            }

            if let undoCall {
                undoToast(undoCall)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 150)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: undoCall)
        .animation(Gauntlet.spring(), value: dragOffset)
        .brutalToast(toast, bottomPadding: 168)
        .sheet(item: $menuSubmission) { submission in
            ProofMenuSheet(
                submission: submission,
                myUserID: model.myUserID ?? "",
                api: appState.api,
                onDeleted: {
                    Task { await model.load(api: appState.api, myUserID: appState.user?.id ?? "") }
                    toast.show("Proof deleted. The points are gone.")
                },
                onReported: {
                    Task { await model.load(api: appState.api, myUserID: appState.user?.id ?? "") }
                    toast.show("Reported. It's hidden for you.")
                },
                onBlocked: {
                    Task { await model.load(api: appState.api, myUserID: appState.user?.id ?? "") }
                    toast.show("Blocked. You won't see them anymore.")
                }
            )
        }
        .sheet(item: $banterSubmission) { submission in
            BanterSheet(submission: submission, api: appState.api)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .bottom) {
            Text("VAR check")
                .displayStyle(30)
                .foregroundStyle(Color.paper)
            Spacer(minLength: 8)
            if !queue.isEmpty {
                liveChip
            }
        }
    }

    /// The live chip: the card in front of me and the pile that is left to call.
    ///
    /// The first card is card one, not card zero, and the total shrinks as the cards
    /// are called.
    private var liveChip: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.red)
                .frame(width: 7, height: 7)
            Text("\(cardPosition) OF \(cardsLeft)")
                .labelStyle(9)
                .foregroundStyle(Color.paper)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .overlay {
            Rectangle()
                .stroke(Color.paper, lineWidth: 1.5)
        }
        .accessibilityLabel(Text("Card \(cardPosition) of \(cardsLeft)"))
    }

    /// The cards that are still to be called, the one in front of me included.
    private var cardsLeft: Int {
        queue.count
    }

    /// The position of the card in front of me. The pile shrinks as the cards are
    /// called, so the position never runs past the total.
    private var cardPosition: Int {
        min(madeCalls + 1, max(cardsLeft, 1))
    }

    // MARK: - Cards

    private func cardStack(_ top: Submission) -> some View {
        ZStack {
            // The card underneath.
            if queue.count > 1 {
                RoundedRectangle(cornerRadius: 0, style: .continuous)
                    .fill(Color(hex: 0x222222))
                    .frame(height: VarCheckView.cardHeight)
                    .brutalBorder(Color.paper.opacity(0.33))
                    .rotationEffect(.degrees(Gauntlet.Rotation.varCardBack))
                    .offset(x: -6)
            }

            VCard(top: top, dragOffset: dragOffset)
                .frame(height: VarCheckView.cardHeight)
                .offset(dragOffset)
                .rotationEffect(.degrees(Gauntlet.Rotation.varCard))
                .offset(x: 10)
                .gesture(dragGesture)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 38)
        .overlay(alignment: .topTrailing) {
            // The "⋯" of the proof. It sits on the card, but outside of the swipe.
            Button {
                menuSubmission = top
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.paper)
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.55))
                    .overlay {
                        Rectangle().stroke(Color.paper.opacity(0.6), lineWidth: 1.5)
                    }
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            .padding(.trailing, 42)
            .accessibilityLabel(Text("More"))
        }
        .animation(Gauntlet.spring(), value: dragOffset)
        .accessibilityElement(children: .contain)
        .accessibilityActions {
            Button("Goal") { call(approve: true) }
            Button("No goal") { call(approve: false) }
        }
    }

    /// The banter of the proof I just called.
    private func banterBar(_ submission: Submission) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("YOU CALLED IT")
                .labelStyle(8)
                .foregroundStyle(Color.paper.opacity(0.5))
            BanterBar(
                submission: submission,
                onToggleReaction: { emoji in
                    toggleReaction(submission, emoji: emoji)
                },
                onOpenBanter: { banterSubmission = submission }
            )
        }
    }

    /// The height of the proof card.
    static let cardHeight: CGFloat = 420

    /// The swipe: right is a goal, left is no goal. Released early, the card springs back.
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard !isFlying else { return }
                dragOffset = value.translation
            }
            .onEnded { value in
                guard !isFlying else { return }
                let threshold: CGFloat = 90
                if value.translation.width > threshold {
                    dragOffset = CGSize(width: 520, height: value.translation.height)
                    call(approve: true)
                } else if value.translation.width < -threshold {
                    dragOffset = CGSize(width: -520, height: value.translation.height)
                    call(approve: false)
                } else {
                    withAnimation(Gauntlet.spring()) {
                        dragOffset = .zero
                    }
                }
            }
    }

    // MARK: - Hint and calls

    private var hint: some View {
        Text("← NO GOAL · SWIPE · GOAL →")
            .labelStyle(8)
            .foregroundStyle(Color.paper.opacity(0.6))
            .padding(.bottom, 8)
    }

    private var calls: some View {
        HStack(spacing: 12) {
            callButton(title: "No goal", isGoal: false) {
                call(approve: false)
            }
            callButton(title: "Goal", isGoal: true) {
                call(approve: true)
            }
        }
    }

    private func callButton(title: String, isGoal: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isGoal {
                    // The ball is an SF Symbol — no emoji as an icon.
                    Image(systemName: "soccerball")
                        .font(.system(size: 19, weight: .bold))
                } else {
                    // The red card.
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.paper)
                        .frame(width: 14, height: 20)
                        .overlay {
                            Rectangle()
                                .stroke(Color.ink.opacity(0.25), lineWidth: 1.5)
                        }
                }
                Text(title)
                    .displayStyle(19)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(isGoal ? Color.pitch : Color.red)
            .foregroundStyle(isGoal ? Color.ink : Color.paper)
            .brutalBorder(Color.paper)
        }
        .buttonStyle(.plain)
        .rotationEffect(.degrees(isGoal ? Gauntlet.Rotation.callGoal : Gauntlet.Rotation.callNoGoal))
        .disabled(isLoading)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("Nothing in the VAR")
                .displayStyle(24)
                .foregroundStyle(Color.paper)
            Text("Every proof of this matchweek has been called.")
                .font(.subheadline)
                .foregroundStyle(Color.paper.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Undo toast

    private func undoToast(_ undo: UndoCall) -> some View {
        HStack(spacing: 10) {
            Text(undo.approve ? "GOAL CALLED" : "NO GOAL CALLED")
                .labelStyle(9)
                .foregroundStyle(Color.paper)
            Spacer(minLength: 8)
            if undo.canUndo {
                Button {
                    undoCall = nil
                    Task { await revert(undo) }
                } label: {
                    Text("UNDO")
                        .labelStyle(9)
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.card)
                }
                .buttonStyle(.plain)
            } else {
                Text("DECISION FINAL")
                    .labelStyle(9)
                    .foregroundStyle(Color.paper.opacity(0.6))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(hex: 0x1B1B1D))
        .brutalBorder(Color.paper)
    }

    // MARK: - Actions

    private func call(approve: Bool) {
        guard let top, !isFlying else { return }
        isFlying = true
        Haptics.vote()
        let submission = top
        Task {
            let updated = await model.vote(on: submission, approve: approve, api: appState.api)
            isFlying = false
            dragOffset = .zero
            madeCalls += 1
            // The banter of the card opens after the call.
            calledCard = updated ?? submission
            let canUndo = updated?.status == .pending
            undoCall = UndoCall(
                id: submission.id,
                submissionID: submission.id,
                approve: approve,
                canUndo: canUndo
            )
            // The toast lives for four seconds.
            try? await Task.sleep(for: .seconds(4))
            if undoCall?.id == submission.id {
                undoCall = nil
            }
        }
    }

    private func toggleReaction(_ submission: Submission, emoji: ReactionEmoji) {
        Task {
            guard let updated = await model.toggleReaction(
                on: submission,
                emoji: emoji,
                api: appState.api
            ) else { return }
            calledCard = updated
            Haptics.selection()
        }
    }

    private func revert(_ undo: UndoCall) async {
        guard let submission = model.feed.first(where: { $0.id == undo.submissionID }) else { return }
        _ = await model.vote(on: submission, approve: !undo.approve, api: appState.api)
    }
}

/// The proof card of the VAR check: the media, the stamp and the caption.
struct VCard: View {
    let top: Submission
    let dragOffset: CGSize

    private var isGoal: Bool { dragOffset.width > 40 }
    private var isNoGoal: Bool { dragOffset.width < -40 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ProofMediaView(submission: top, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .frame(height: VarCheckView.cardHeight)
                .clipped()

            // The stamp of the goal: it fades in while the card is dragged to the right.
            StampView(title: "Goal", color: .pitch)
                .padding(16)
                .opacity(isNoGoal ? 0 : 1)

            if isNoGoal {
                StampView(title: "No goal", color: .red)
                    .padding(16)
                    .transition(.scale.combined(with: .opacity))
            }

            VStack {
                Spacer()
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(top.user.avatarEmoji ?? "🙂")
                            .font(.system(size: 13))
                        Text("\(top.user.displayName.uppercased()) · \(Formatting.relative(top.createdAt).uppercased())")
                            .labelStyle(10)
                            .foregroundStyle(Color.paper)
                    }
                    Text(top.challengeTitle)
                        .displayStyle(19)
                        .foregroundStyle(Color.paper)
                    if let caption = top.caption, !caption.isEmpty {
                        Text(caption)
                            .font(.subheadline)
                            .foregroundStyle(Color.paper.opacity(0.9))
                            .lineLimit(2)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 44)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
        }
        .frame(height: VarCheckView.cardHeight)
        .clipShape(Rectangle())
        .brutalBorder(Color.paper)
        .hardShadow(Color.black, offset: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(top.user.displayName), \(top.challengeTitle)"))
    }
}

#Preview("VAR") {
    NavigationStack {
        VarCheckView(model: .preview())
            .environment(AppState.preview())
    }
}
