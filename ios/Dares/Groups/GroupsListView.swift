import SwiftUI

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

    var body: some View {
        @Bindable var router = appState.router

        NavigationStack(path: $router.path) {
            List {
                if appState.groups.isEmpty {
                    EmptyStateView(
                        icon: "person.3.fill",
                        title: String(localized: "groups.empty.title"),
                        message: String(localized: "groups.empty.message"),
                        actionTitle: String(localized: "groups.empty.action")
                    ) {
                        activeSheet = .create
                    }
                    .listRowSeparator(.hidden)
                } else {
                    Section {
                        ForEach(appState.groups) { group in
                            NavigationLink(value: AppRoute.group(group.id)) {
                                GroupRow(group: group)
                            }
                        }
                    } header: {
                        Text("groups.section")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("groups.title")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 8) {
                        Button {
                            activeSheet = .profile
                        } label: {
                            Image(systemName: "person.crop.circle")
                        }
                        .accessibilityLabel(Text("profile.title"))
                        if appState.isDemoMode {
                            DemoBadge()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            activeSheet = .create
                        } label: {
                            Label("groups.create", systemImage: "plus.circle")
                        }
                        Button {
                            activeSheet = .join
                        } label: {
                            Label("groups.join", systemImage: "link")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(Text("groups.add"))
                }
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
            .overlay {
                if appState.isLoadingGroups && appState.groups.isEmpty {
                    ProgressView()
                }
            }
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
        .onChange(of: appState.needsProfileSetup) { _, needsSetup in
            showingProfileSetup = needsSetup
        }
        .onAppear {
            showingProfileSetup = appState.needsProfileSetup
        }
    }
}

private struct GroupRow: View {
    let group: Group

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(0.16))
                    .frame(width: 46, height: 46)
                Image(systemName: "flag.fill")
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(group.name)
                    .font(.headline)
                HStack(spacing: 6) {
                    Label {
                        Text("\(group.memberCount)")
                    } icon: {
                        Image(systemName: "person.2")
                    }
                    .labelStyle(.titleAndIcon)

                    if let theme = group.theme, !theme.isEmpty {
                        Text("•")
                        Text(theme)
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview("Groups") {
    GroupsListView()
        .environment(AppState.preview())
}
