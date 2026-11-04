import SwiftUI

/// The list of the clubs of the signed in player: "Your clubs".
struct GroupsListView: View {
    /// Only one sheet can be presented at a time, so every presentation goes through this enum.
    private enum ActiveSheet: Identifiable {
        case create
        case join
        case profile

        var id: String {
            switch self {
            case .create: "create"
            case .join: "join"
            case .profile: "profile"
            }
        }
    }

    @Environment(AppState.self) private var appState

    @State private var activeSheet: ActiveSheet?
    @State private var showingProfileSetup = false
    @State private var showingHouseRules = false

    var body: some View {
        @Bindable var router = appState.router

        NavigationStack(path: $router.path) {
            ZStack(alignment: .bottom) {
                Color.ink.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header

                        if appState.groups.isEmpty {
                            emptyState
                                .padding(.top, 30)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(appState.groups) { group in
                                    NavigationLink(value: AppRoute.group(group.id)) {
                                        ClubRow(group: group)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 6)
                        }

                        actions
                            .padding(.horizontal, 16)
                            .padding(.top, 20)

                        Spacer(minLength: 40)
                    }
                }
                .scrollIndicators(.hidden)
            }
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case let .group(id):
                    GroupHomeView(groupID: id)
                }
            }
            .refreshable {
                await appState.loadGroups()
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .create:
                CreateGroupView()
            case .join:
                JoinGroupView()
            case .profile:
                ProfileView()
            }
        }
        .fullScreenCover(isPresented: $showingProfileSetup) {
            ProfileSetupView()
        }
        .fullScreenCover(isPresented: $showingHouseRules) {
            HouseRulesView()
        }
        .onChange(of: appState.needsProfileSetup) { _, needsSetup in
            showingProfileSetup = needsSetup
        }
        .onChange(of: appState.needsHouseRules) { _, needsRules in
            showingHouseRules = needsRules && !appState.needsProfileSetup
        }
        .onAppear {
            showingProfileSetup = appState.needsProfileSetup
            showingHouseRules = appState.needsHouseRules && !appState.needsProfileSetup
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your clubs")
                    .displayStyle(34)
                    .foregroundStyle(Color.paper)
                Text("\(appState.groups.count) CLUB\(appState.groups.count == 1 ? "" : "S")")
                    .labelStyle(8.5)
                    .foregroundStyle(Color.paper.opacity(0.55))
            }

            Spacer(minLength: 8)

            Button {
                activeSheet = .profile
            } label: {
                Text(appState.user?.avatarEmoji ?? "🙂")
                    .font(.system(size: 22))
                    .frame(width: 40, height: 40)
                    .background(Color.paper.opacity(0.08))
                    .overlay {
                        Rectangle().stroke(Color.paper.opacity(0.4), lineWidth: 1.5)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Profile"))
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: - Pieces

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("No club yet")
                .displayStyle(24)
                .foregroundStyle(Color.paper)
            Text("Create one and invite the lads.")
                .font(.subheadline)
                .foregroundStyle(Color.paper.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .overlay {
            Rectangle().stroke(Color.paper.opacity(0.3), lineWidth: 1.5)
        }
        .padding(.horizontal, 16)
    }

    private var actions: some View {
        VStack(spacing: 12) {
            BrutalButton(title: "Create club", trailing: "→") {
                activeSheet = .create
            }
            BrutalOutlineButton(title: "Join with a code") {
                activeSheet = .join
            }
        }
    }
}

/// One club of the list.
private struct ClubRow: View {
    let group: Group

    var body: some View {
        HStack(spacing: 12) {
            ClubCrest(initials: AppConfig.clubInitials, size: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(group.name.uppercased())
                    .displayStyle(17)
                    .foregroundStyle(Color.paper)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                HStack(spacing: 6) {
                    Text("\(group.memberCount) PLAYERS")
                        .labelStyle(8)
                        .foregroundStyle(Color.paper.opacity(0.55))
                    if let theme = group.theme, !theme.isEmpty {
                        Text("•")
                            .labelStyle(8)
                            .foregroundStyle(Color.paper.opacity(0.4))
                        Text(theme.uppercased())
                            .labelStyle(8)
                            .foregroundStyle(Color.paper.opacity(0.55))
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 4)

            Text("→")
                .displayStyle(16)
                .foregroundStyle(Color.card)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color.paper.opacity(0.05))
        .overlay {
            Rectangle().stroke(Color.paper.opacity(0.35), lineWidth: 1.5)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Clubs") {
    GroupsListView()
        .environment(AppState.preview())
}
