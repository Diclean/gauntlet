import SwiftUI

/// The settings of a club: the invite code, the members and the settings of the owner.
struct GroupSettingsView: View {
    let model: GroupViewModel

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var challengesPerWeek = 5
    @State private var theme = ""
    @State private var language = "en"
    @State private var timezone = ""
    @State private var forfeit = ""
    @State private var isSaving = false
    @State private var showingLeaveConfirmation = false
    @State private var errorMessage: String?
    /// The member the owner wants to remove from the club.
    @State private var memberToRemove: Member?
    /// The members the owner removed from the club.
    @State private var bannedMembers: [BannedMember] = []

    private var inviteCode: String {
        model.group?.inviteCode ?? ""
    }

    /// The link that is shared in the group chat (SPEC.md, section 6.8).
    private var inviteLink: String {
        if let url = model.group?.inviteUrl, !url.isEmpty {
            return url
        }
        return "\(AppConfig.baseURLDescription)/join/\(inviteCode)"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.ink.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    header

                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            inviteCard
                            membersCard

                            if model.isOwner {
                                bannedCard
                                settingsCard
                            }

                            leaveButton
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 40)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            // The bar of the system would put its glass pill behind the button: the
            // screen carries its own header, like the other sheets of the house.
            .toolbar(.hidden, for: .navigationBar)
            .onAppear(perform: loadValues)
            .task {
                await loadBans()
            }
            .confirmationDialog(
                Text("settings.leave.confirm.title"),
                isPresented: $showingLeaveConfirmation,
                titleVisibility: .visible
            ) {
                Button("settings.leave", role: .destructive) { leave() }
                Button("action.cancel", role: .cancel) {}
            } message: {
                Text("settings.leave.confirm.message")
            }
            .confirmationDialog(
                Text("Remove from club?"),
                isPresented: Binding(
                    get: { memberToRemove != nil },
                    set: { if !$0 { memberToRemove = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remove from club", role: .destructive) { removeMember() }
                Button("action.cancel", role: .cancel) { memberToRemove = nil }
            } message: {
                Text("\(memberToRemove?.user.displayName ?? "") is out of the club. Their proofs of this matchweek expire and they cannot come back with the invite code.")
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

    // MARK: - Cards

    /// The header of the sheet: the name of the screen and the square ✕ of the house.
    private var header: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Text("Club settings")
                .displayStyle(30)
                .foregroundStyle(Color.paper)
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
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var inviteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("INVITE CODE")
                .labelStyle(8)
                .foregroundStyle(Color.paper.opacity(0.55))
            HStack {
                Text(inviteCode)
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(Color.card)
                Spacer(minLength: 8)
                ShareLink(item: inviteShareText) {
                    Text("Share")
                        .labelStyle(9)
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.card)
                }
            }
            .padding(12)
            .overlay {
                Rectangle().stroke(Color.paper.opacity(0.35), lineWidth: 1.5)
            }

            Text("INVITE LINK")
                .labelStyle(8)
                .foregroundStyle(Color.paper.opacity(0.55))
                .padding(.top, 6)

            HStack(spacing: 10) {
                Text(inviteLink)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.paper.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .textSelection(.enabled)
                Spacer(minLength: 6)
                ShareLink(item: inviteLinkShareText) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.paper)
                        .frame(width: 34, height: 30)
                        .overlay {
                            Rectangle().stroke(Color.paper.opacity(0.6), lineWidth: 1.5)
                        }
                }
                .accessibilityLabel(Text("Share the invite link"))
            }
            .padding(12)
            .overlay {
                Rectangle().stroke(Color.paper.opacity(0.35), lineWidth: 1.5)
            }

            Text("THE LINK OPENS THE JOIN SCREEN — NOBODY JOINS WITHOUT SAYING YES.")
                .labelStyle(7.5)
                .foregroundStyle(Color.paper.opacity(0.45))
        }
    }

    private var membersCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PLAYERS")
                .labelStyle(8)
                .foregroundStyle(Color.paper.opacity(0.55))
            VStack(spacing: 0) {
                ForEach(model.members) { member in
                    HStack(spacing: 10) {
                        Text(member.user.avatarEmoji ?? "🙂")
                            .font(.system(size: 18))
                            .frame(width: 30, height: 30)
                            .background(Color.paper.opacity(0.08))
                        Text(member.user.displayName.uppercased())
                            .displayStyle(15)
                            .foregroundStyle(Color.paper)
                        if member.user.id == model.group?.ownerId {
                            Text("OWNER")
                                .labelStyle(7.5)
                                .foregroundStyle(Color.card)
                        }
                        Spacer(minLength: 4)
                        Text(Formatting.relative(member.joinedAt).uppercased())
                            .labelStyle(7.5)
                            .foregroundStyle(Color.paper.opacity(0.45))
                        if model.isOwner, member.user.id != model.group?.ownerId {
                            Button {
                                memberToRemove = member
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Color.paper.opacity(0.8))
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        Rectangle().stroke(Color.paper.opacity(0.4), lineWidth: 1.5)
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("Remove \(member.user.displayName)"))
                        }
                    }
                    .padding(.vertical, 8)
                    .overlay(alignment: .top) {
                        if member.id != model.members.first?.id {
                            Rectangle()
                                .fill(Color.paper.opacity(0.15))
                                .frame(height: 1.5)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .overlay {
                Rectangle().stroke(Color.paper.opacity(0.35), lineWidth: 1.5)
            }
        }
    }

    /// The members the owner removed from the club.
    private var bannedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BANNED")
                .labelStyle(8)
                .foregroundStyle(Color.paper.opacity(0.55))

            if bannedMembers.isEmpty {
                Text("NOBODY IS OUT OF THE CLUB.")
                    .labelStyle(8)
                    .foregroundStyle(Color.paper.opacity(0.45))
                    .padding(.vertical, 10)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(bannedMembers.enumerated()), id: \.element.id) { index, banned in
                        HStack(spacing: 10) {
                            Text(banned.user.avatarEmoji ?? "🙂")
                                .font(.system(size: 18))
                                .frame(width: 30, height: 30)
                                .background(Color.paper.opacity(0.08))
                            Text(banned.user.displayName.uppercased())
                                .displayStyle(15)
                                .foregroundStyle(Color.paper.opacity(0.8))
                            Spacer(minLength: 4)
                            Text(Formatting.relative(banned.bannedAt).uppercased())
                                .labelStyle(7.5)
                                .foregroundStyle(Color.paper.opacity(0.45))
                            Button {
                                unban(banned)
                            } label: {
                                Text("UNBAN")
                                    .labelStyle(8)
                                    .foregroundStyle(Color.ink)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.card)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 8)
                        .overlay(alignment: .top) {
                            if index < bannedMembers.count - 1 {
                                Rectangle()
                                    .fill(Color.paper.opacity(0.15))
                                    .frame(height: 1.5)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .overlay {
                    Rectangle().stroke(Color.paper.opacity(0.35), lineWidth: 1.5)
                }
            }
        }
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("THE CLUB")
                .labelStyle(8)
                .foregroundStyle(Color.paper.opacity(0.55))

            field(title: "NAME", text: $name)
            field(title: "THEME", text: $theme)

            HStack {
                Text("FIXTURES PER MATCHWEEK")
                    .labelStyle(8)
                    .foregroundStyle(Color.paper.opacity(0.7))
                Spacer(minLength: 8)
                Stepper(value: $challengesPerWeek, in: 3 ... 10) {
                    Text("\(challengesPerWeek)")
                        .font(.anton(16))
                        .foregroundStyle(Color.card)
                }
                .labelsHidden()
            }
            .padding(.horizontal, 12)
            .frame(height: 46)
            .overlay {
                Rectangle().stroke(Color.paper.opacity(0.35), lineWidth: 1.5)
            }

            VStack(alignment: .leading, spacing: 6) {
                field(title: "FORFEIT — WHAT THE RELEGATION ZONE BUYS", text: $forfeit)
                Text("Shown on the relegation line, on the receipt and on the Wooden Spoon.")
                    .labelStyle(7.5)
                    .foregroundStyle(Color.paper.opacity(0.5))
            }

            BrutalButton(title: isSaving ? "Saving…" : "Save", trailing: "→") {
                save()
            }
            .disabled(isSaving)
        }
    }

    private func field(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .labelStyle(8)
                .foregroundStyle(Color.paper.opacity(0.7))
            TextField(title, text: text)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.paper)
                .tint(Color.card)
                .padding(.horizontal, 12)
                .frame(height: 46)
                .overlay {
                    Rectangle().stroke(Color.paper.opacity(0.35), lineWidth: 1.5)
                }
        }
    }

    private var leaveButton: some View {
        Button {
            showingLeaveConfirmation = true
        } label: {
            Text("Leave the club")
                .labelStyle(9)
                .foregroundStyle(Color.red)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .overlay {
                    Rectangle().stroke(Color.red, lineWidth: 1.5)
                }
        }
        .buttonStyle(.plain)
    }

    private var inviteShareText: String {
        String(format: String(localized: "settings.invite.share_text"), inviteCode)
    }

    /// The text that is shared in the group chat: the club and its link.
    private var inviteLinkShareText: String {
        "Join \(model.group?.name ?? "the club") on \(AppConfig.appName): \(inviteLink)"
    }

    // MARK: - Actions

    private func loadValues() {
        guard let group = model.group else { return }
        name = group.name
        challengesPerWeek = group.challengesPerWeek
        theme = group.theme ?? ""
        language = group.language
        timezone = group.timezone
        forfeit = group.forfeit
    }

    private func loadBans() async {
        guard model.isOwner else { return }
        bannedMembers = (try? await appState.api.bannedMembers(groupID: model.groupID)) ?? []
    }

    private func removeMember() {
        guard let member = memberToRemove else { return }
        memberToRemove = nil
        Task {
            do {
                _ = try await appState.api.removeMember(
                    groupID: model.groupID,
                    userID: member.user.id
                )
                await model.load(api: appState.api, myUserID: appState.user?.id ?? "")
                await loadBans()
            } catch {
                errorMessage = model.errorMessage ?? (error as? APIError)?.errorDescription
            }
        }
    }

    private func unban(_ banned: BannedMember) {
        Task {
            do {
                _ = try await appState.api.unbanMember(
                    groupID: model.groupID,
                    userID: banned.user.id
                )
                bannedMembers.removeAll { $0.id == banned.id }
            } catch {
                errorMessage = model.errorMessage ?? (error as? APIError)?.errorDescription
            }
        }
    }

    private func save() {
        isSaving = true
        Task {
            let trimmedTheme = theme.trimmingCharacters(in: .whitespacesAndNewlines)
            let saved = await model.updateGroup(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                challengesPerWeek: challengesPerWeek,
                theme: trimmedTheme.isEmpty ? nil : trimmedTheme,
                language: language,
                timezone: timezone,
                forfeit: forfeit.trimmingCharacters(in: .whitespacesAndNewlines),
                api: appState.api
            )
            isSaving = false
            if saved {
                await appState.loadGroups()
            } else {
                errorMessage = model.errorMessage
            }
        }
    }

    private func leave() {
        Task {
            let left = await model.leave(api: appState.api)
            if left {
                appState.removeGroup(id: model.groupID)
                dismiss()
            } else {
                errorMessage = model.errorMessage
            }
        }
    }
}

#Preview("Club settings") {
    GroupSettingsView(model: .preview())
        .environment(AppState.preview())
}
