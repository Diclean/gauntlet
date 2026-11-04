import Charts
import SwiftUI

/// Screen 6 — the title race: the cumulative points of the club, matchweek by matchweek.
struct TitleRaceView: View {
    let model: GroupViewModel
    /// Called when the player wants to see the table again.
    var onBack: () -> Void = {}

    enum Mode: String, CaseIterable, Identifiable {
        case all = "ALL PLAYERS"
        case duel = "ME VS RIVAL"
        case perWeek = "PER WEEK"

        var id: String { rawValue }
    }

    @State private var mode: Mode = .all
    @State private var selectedWeek: Int?

    private var race: RaceResponse? { model.race }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.ink.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Button {
                    onBack()
                } label: {
                    HStack(spacing: 6) {
                        Text("←")
                            .displayStyle(13)
                        Text("THE TABLE")
                            .labelStyle(8)
                    }
                    .foregroundStyle(Color.paper.opacity(0.6))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.top, 4)

                header
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                BrutalSegmented(
                    options: Mode.allCases.map { .init(value: $0, title: $0.rawValue) },
                    selection: $mode,
                    onDark: true
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)

                chart
                    .padding(.horizontal, 8)
                    .padding(.top, 10)

                perWeekBars
                    .padding(.horizontal, 16)
                    .padding(.top, 6)

                statChips
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .bottom) {
            Text("Title race")
                .displayStyle(38)
                .foregroundStyle(Color.paper)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("SEASON 1")
                    .labelStyle(8)
                Text(windowLabel)
                    .labelStyle(8)
            }
            .foregroundStyle(Color.paper.opacity(0.6))
        }
    }

    private var windowLabel: String {
        guard let first = windowWeeks.first, let last = windowWeeks.last else { return "" }
        return "MW \(first.number) → \(last.number)"
    }

    // MARK: - The window
    //
    // The chart shows the last eight matchweeks of the season.

    private var windowIndices: [Int] {
        guard let race else { return [] }
        let start = max(race.weeks.count - 8, 0)
        return Array(start..<race.weeks.count)
    }

    private var windowWeeks: [RaceWeek] {
        guard let race else { return [] }
        return windowIndices.compactMap { race.weeks.indices.contains($0) ? race.weeks[$0] : nil }
    }

    private func cumulative(_ series: RaceSeries, at index: Int) -> Int {
        series.cumulative.indices.contains(index) ? series.cumulative[index] : 0
    }

    private func points(_ series: RaceSeries, at index: Int) -> Int {
        series.perWeek.indices.contains(index) ? series.perWeek[index] : 0
    }

    private func number(of index: Int) -> Int? {
        guard let race, race.weeks.indices.contains(index) else { return nil }
        return race.weeks[index].number
    }

    // MARK: - Chart

    @ViewBuilder
    private var chart: some View {
        switch mode {
        case .all, .duel:
            lineChart
        case .perWeek:
            barChart
        }
    }

    private var lineChart: some View {
        Chart {
            leaderHalo
            lines
            endLabels
            leadChangeMark
            crosshair
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Color.paper.opacity(0.1))
                AxisValueLabel {
                    if let points = value.as(Int.self) {
                        Text("\(points)")
                            .labelStyle(7.5)
                            .foregroundStyle(Color.paper.opacity(0.5))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: xAxisValues) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Color.paper.opacity(0.1))
                AxisValueLabel {
                    if let number = value.as(Int.self) {
                        Text("MW\(number)")
                            .labelStyle(7.5)
                            .foregroundStyle(Color.paper.opacity(0.5))
                    }
                }
            }
        }
        .chartPlotStyle { plot in
            plot.background(Color.clear)
        }
        .frame(height: 250)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard let frame = proxy.plotFrame else { return }
                                let origin = geometry[frame].origin
                                let x = value.location.x - origin.x
                                if let week: Int = proxy.value(atX: x) {
                                    selectedWeek = windowIndices.first { number(of: $0) == week }
                                }
                            }
                            .onEnded { _ in
                                selectedWeek = nil
                            }
                    )
            }
        }
        .accessibilityLabel(Text("Title race"))
    }

    /// The ink halo under the line of the leader.
    @ChartContentBuilder
    private var leaderHalo: some ChartContent {
        if mode == .all {
            ForEach(visibleSeries.filter { isLeader($0) }) { series in
                ForEach(windowIndices, id: \.self) { index in
                    if let number = number(of: index) {
                        LineMark(
                            x: .value("Matchweek", number),
                            y: .value("Points", cumulative(series, at: index)),
                            series: .value("Player", "halo-" + series.user.displayName)
                        )
                        .foregroundStyle(Color.ink)
                        .lineStyle(StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                    }
                }
            }
        }
    }

    /// The line of every player.
    @ChartContentBuilder
    private var lines: some ChartContent {
        ForEach(visibleSeries) { series in
            ForEach(windowIndices, id: \.self) { index in
                if let number = number(of: index) {
                    LineMark(
                        x: .value("Matchweek", number),
                        y: .value("Points", cumulative(series, at: index)),
                        series: .value("Player", series.user.displayName)
                    )
                    .foregroundStyle(color(for: series))
                    .lineStyle(StrokeStyle(lineWidth: lineWidth(for: series), lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    /// The name at the end of every line.
    @ChartContentBuilder
    private var endLabels: some ChartContent {
        ForEach(visibleSeries) { series in
            if let lastIndex = windowIndices.last,
               let number = number(of: lastIndex) {
                PointMark(
                    x: .value("Matchweek", number),
                    y: .value("Points", cumulative(series, at: lastIndex))
                )
                .foregroundStyle(color(for: series))
                .symbolSize(60)
                .annotation(position: .trailing, alignment: .leading) {
                    endLabel(series: series, points: cumulative(series, at: lastIndex))
                }
            }
        }
    }

    private func endLabel(series: RaceSeries, points: Int) -> some View {
        HStack(spacing: 3) {
            Text(series.user.avatarEmoji ?? "")
                .font(.system(size: 10))
            Text(series.user.displayName.uppercased())
                .font(.anton(11))
                .foregroundStyle(labelColor(for: series))
            if let rank = rankOf(series), rank <= 2 {
                Text("\(points)")
                    .font(.anton(11))
                    .foregroundStyle(labelColor(for: series))
            }
        }
        .offset(x: 4)
    }

    /// The dashed marker of the matchweek in which the title changed hands.
    ///
    /// The marker is only drawn when the change of hands is on the chart — a change
    /// that happened before the window would stretch the axis of the chart.
    @ChartContentBuilder
    private var leadChangeMark: some ChartContent {
        if let change = model.leadChangeWeek(),
           windowWeeks.contains(where: { $0.number == change }) {
            RuleMark(x: .value("Matchweek", change))
                .foregroundStyle(Color.paper)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .annotation(position: .top, alignment: .trailing, spacing: -14) {
                    HStack(spacing: 3) {
                        Text("Lead change")
                            .labelStyle(7.5)
                        Image(systemName: "arrow.down.right")
                            .font(.system(size: 7.5, weight: .bold))
                    }
                    .foregroundStyle(Color.paper)
                }
        }
    }

    /// The crosshair of the drag.
    @ChartContentBuilder
    private var crosshair: some ChartContent {
        if let selected = selectedWeek, let number = number(of: selected) {
            RuleMark(x: .value("Matchweek", number))
                .foregroundStyle(Color.paper.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1))
            if let mine = mySeries {
                PointMark(
                    x: .value("Matchweek", number),
                    y: .value("Points", points(mine, at: selected))
                )
                .foregroundStyle(Color.card)
                .symbolSize(80)
                .annotation(position: .top, alignment: .leading, spacing: 4) {
                    tooltip(number: number, points: points(mine, at: selected))
                }
            }
        }
    }

    private func tooltip(number: Int, points: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("MW\(number) · +\(points) FOR \(mySeries?.user.displayName.uppercased() ?? "")")
                .displayStyle(13)
            Text("BEST WEEK OF THE SEASON")
                .labelStyle(8)
                .foregroundStyle(Color.ink.opacity(0.6))
            Text("OVERTAKES LEE AT THE TOP")
                .labelStyle(8)
                .foregroundStyle(Color.ink.opacity(0.6))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(Color.paper)
        .foregroundStyle(Color.ink)
        .brutalBorder(Color.ink)
        .hardShadow(Color.card, offset: 3)
    }

    private var barChart: some View {
        Chart {
            ForEach(visibleSeries) { series in
                ForEach(windowIndices, id: \.self) { index in
                    if let number = number(of: index) {
                        BarMark(
                            x: .value("Matchweek", number),
                            y: .value("Points", points(series, at: index))
                        )
                        .foregroundStyle(color(for: series))
                        .position(by: .value("Player", series.user.displayName))
                    }
                }
            }
        }
        .chartForegroundStyleScale(
            domain: visibleSeries.map(\.user.displayName),
            range: visibleSeries.map { color(for: $0) }
        )
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Color.paper.opacity(0.1))
                AxisValueLabel {
                    if let points = value.as(Int.self) {
                        Text("\(points)")
                            .labelStyle(7.5)
                            .foregroundStyle(Color.paper.opacity(0.5))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: xAxisValues) { value in
                AxisValueLabel {
                    if let number = value.as(Int.self) {
                        Text("MW\(number)")
                            .labelStyle(7.5)
                            .foregroundStyle(Color.paper.opacity(0.5))
                    }
                }
            }
        }
        .frame(height: 250)
    }

    // MARK: - Bars and chips

    private var perWeekBars: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("YOUR POINTS PER MATCHWEEK")
                .labelStyle(8)
                .foregroundStyle(Color.paper.opacity(0.6))

            let values = windowIndices.compactMap { index -> Int? in
                guard let mine = mySeries else { return nil }
                return points(mine, at: index)
            }
            let best = values.max() ?? 0

            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    VStack(spacing: 3) {
                        if value == best, best > 0 {
                            Text("\(value)")
                                .font(.anton(11))
                                .foregroundStyle(Color.card)
                        }
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(value == best ? Color.card : Color.paper.opacity(0.22))
                            .frame(height: max(4, CGFloat(value) / CGFloat(max(best, 1)) * 56))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 70, alignment: .bottom)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.paper.opacity(0.25))
                    .frame(height: 1.5)
            }

            HStack {
                Text("MW\(windowWeeks.first?.number ?? 0)")
                Spacer()
                Text("MW\(windowWeeks.last?.number ?? 0)")
            }
            .labelStyle(7)
            .foregroundStyle(Color.paper.opacity(0.5))
        }
    }

    private var statChips: some View {
        HStack(spacing: 6) {
            chip(title: "BEST WEEK", value: "\(race?.me.bestWeek.points ?? 0)", color: .paper)
            chip(title: "AVG / WEEK", value: "\(race?.me.avgPerWeek ?? 0)", color: .paper)
            chip(title: "FORM", value: "🔥 \(race?.me.streak ?? 0)", color: .flame)
        }
    }

    private func chip(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .labelStyle(7)
                .foregroundStyle(Color.paper.opacity(0.6))
            Text(value)
                .displayStyle(17)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .brutalBorder(Color.paper)
    }

    // MARK: - Data

    private var mySeries: RaceSeries? {
        guard let race, let myUserID = model.myUserID else { return nil }
        return race.series.first { $0.user.id == myUserID }
    }

    private var visibleSeries: [RaceSeries] {
        guard let race else { return [] }
        switch mode {
        case .all:
            return race.series
        case .duel, .perWeek:
            var series: [RaceSeries] = []
            if let mine = mySeries { series.append(mine) }
            if let rival = model.rival() { series.append(rival) }
            return series
        }
    }

    private func isLeader(_ series: RaceSeries) -> Bool {
        guard let race else { return false }
        let best = race.series.map { $0.cumulative.last ?? 0 }.max() ?? 0
        return (series.cumulative.last ?? 0) == best
    }

    private func isMe(_ series: RaceSeries) -> Bool {
        series.user.id == model.myUserID
    }

    private func color(for series: RaceSeries) -> Color {
        if isLeader(series) { return .card }
        if isMe(series) { return .paper }
        // The rival — the player right above or below me — keeps the full line.
        if let rival = model.rival(), rival.user.id == series.user.id { return .paper }
        return .paper.opacity(0.27)
    }

    private func lineWidth(for series: RaceSeries) -> CGFloat {
        isLeader(series) ? 3 : 2
    }

    private func labelColor(for series: RaceSeries) -> Color {
        isLeader(series) ? .card : .paper.opacity(0.7)
    }

    private func rankOf(_ series: RaceSeries) -> Int? {
        guard let race else { return nil }
        let sorted = race.series.sorted { ($0.cumulative.last ?? 0) > ($1.cumulative.last ?? 0) }
        return sorted.firstIndex { $0.user.id == series.user.id }.map { $0 + 1 }
    }

    private var xAxisValues: [Int] {
        let numbers = windowWeeks.map(\.number)
        guard numbers.count > 1 else { return numbers }
        guard numbers.count > 3 else { return numbers }
        let indexes = [0, numbers.count / 4, numbers.count / 2, numbers.count - 1]
        return indexes.map { numbers[$0] }
    }
}

#Preview("Race") {
    NavigationStack {
        TitleRaceView(model: .preview())
            .environment(AppState.preview())
    }
}
