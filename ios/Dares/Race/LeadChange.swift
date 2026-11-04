import Foundation

/// The lead change of a title race.
///
/// The #1 position of the table can change hands during a season. The dashed marker of
/// the title race is drawn in the matchweek where it changed for the last time.
///
/// The detection is a pure function: it only reads the race and never touches the model,
/// the API or the view.
enum LeadChange {
    /// The matchweek of the most recent change of hands at the top — `nil` when the
    /// leader never changed.
    static func week(of race: RaceResponse) -> Int? {
        week(weeks: race.weeks, series: race.series)
    }

    /// The matchweek of the most recent change of hands at the top.
    ///
    /// The leader is the player with the most **cumulative** points at the end of the
    /// matchweek — the points of the matchweek alone do not decide who is on top.
    ///
    /// - A draw at the top is not a change of hands: the incumbent keeps the lead.
    /// - When the title changes hands more than once, the most recent change wins.
    /// - `nil` when the leader never changed.
    static func week(weeks: [RaceWeek], series: [RaceSeries]) -> Int? {
        guard weeks.count > 1, !series.isEmpty else { return nil }

        var leader: String?
        var change: Int?

        for (index, week) in weeks.enumerated() {
            // The ids are sorted so that a draw always has the same outcome.
            let scores = series
                .map { (id: $0.user.id, points: cumulative($0, at: index)) }
                .sorted { $0.id < $1.id }
            let top = scores.map(\.points).max() ?? 0
            // Nobody has scored yet: there is no leader to follow.
            guard top > 0 else { continue }

            let leaders = scores.filter { $0.points == top }.map(\.id)
            // A draw at the top is not a change of hands — the incumbent keeps the lead.
            if leaders.count > 1, let leader, leaders.contains(leader) { continue }
            guard let newLeader = leaders.first else { continue }

            if let leader, leader != newLeader {
                change = week.number
            }
            leader = newLeader
        }

        return change
    }

    /// The cumulative points of a player at the end of a matchweek.
    private static func cumulative(_ series: RaceSeries, at index: Int) -> Int {
        series.cumulative.indices.contains(index) ? series.cumulative[index] : 0
    }
}
