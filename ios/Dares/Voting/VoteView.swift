import SwiftUI

struct VoteView: View {
    let model: GroupViewModel
    let onSelect: (Submission) -> Void

    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            if model.pendingVotes.isEmpty {
                EmptyStateView(
                    icon: "checkmark.circle.fill",
                    title: String(localized: "vote.empty.title"),
                    message: String(localized: "vote.empty.message")
                )
                .listRowSeparator(.hidden)
            } else {
                Section("vote.section") {
                    ForEach(model.pendingVotes) { submission in
                        Button {
                            onSelect(submission)
                        } label: {
                            SubmissionRow(submission: submission, showsVoteButtons: false)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .refreshable {
            await model.load(api: appState.api, myUserID: appState.user?.id ?? "")
        }
    }
}

#Preview("Vote") {
    NavigationStack {
        VoteView(model: .preview()) { _ in }
            .environment(AppState.preview())
    }
}
