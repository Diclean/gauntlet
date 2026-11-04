import SwiftUI

/// The trophy cabinet of the profile: everything the player has won.
struct TrophyCabinetView: View {
    @Environment(AppState.self) private var appState
    @State private var trophies: [Trophy] = []

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        ZStack {
            Color.ink.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Trophy cabinet")
                        .displayStyle(34)
                        .foregroundStyle(Color.paper)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    if trophies.isEmpty {
                        emptyState
                            .padding(.horizontal, 16)
                            .padding(.top, 40)
                    } else {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(trophies) { trophy in
                                trophyCard(trophy)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                    }

                    Spacer(minLength: 80)
                }
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Trophy cabinet")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.ink, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            trophies = (try? await appState.api.trophies()) ?? []
        }
    }

    private func trophyCard(_ trophy: Trophy) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(trophy.award.icon)
                .font(.system(size: 22))
                .foregroundStyle(Color.card)
                .frame(width: 40, height: 40)
                .background(Color.paper.opacity(0.08))

            Text(trophy.award.title)
                .displayStyle(14)
                .foregroundStyle(Color.paper)
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            Text(AwardKey.monthName(for: trophy.month))
                .labelStyle(8)
                .foregroundStyle(Color.card)

            Text(trophy.groupName.uppercased())
                .labelStyle(7.5)
                .foregroundStyle(Color.paper.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .brutalBorder(Color.paper.opacity(0.5))
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("No silverware yet.")
                .displayStyle(22)
                .foregroundStyle(Color.paper)
            Text("Next ceremony on the 1st.")
                .font(.subheadline)
                .foregroundStyle(Color.paper.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .overlay {
            Rectangle()
                .stroke(Color.paper.opacity(0.3), lineWidth: 1.5)
                .padding(.horizontal, 16)
        }
    }
}

#Preview("Trophy cabinet") {
    NavigationStack {
        TrophyCabinetView()
            .environment(AppState.preview())
    }
}
