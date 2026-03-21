//
//  AgeTab.swift
//  no laughing matter
//
//  Created by Claude on 21.03.26.
//

import SwiftUI
import Charts

struct AgeTab: View {
    let vm: VisualizationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            AgeCoverageBanner(vm: vm)

            if vm.ageDistribution.isEmpty {
                AgeEmptyState()
            } else {
                AgeBaselineSection(vm: vm)
                AgeByPartySection(vm: vm)
                AgeGroupByPartySection(vm: vm)
                AgeByIntentionSection(vm: vm)
                AgeTrendSection(vm: vm)
            }
        }
    }
}

// MARK: - Coverage Banner

private struct AgeCoverageBanner: View {
    let vm: VisualizationViewModel

    var body: some View {
        let known = vm.ageKnownCount
        let total = vm.parsedCount
        if known > 0 {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .foregroundStyle(known < total ? .orange : .secondary)
                Text("Based on \(known) of \(total) events with known speaker age")
                    .font(.callout)
                    .foregroundStyle(known < total ? .orange : .secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill((known < total ? Color.orange : Color.secondary).opacity(0.08))
            )
        }
    }
}

// MARK: - Empty State

private struct AgeEmptyState: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No age data")
                .font(.headline)
            Text("Speaker age information is not yet available. Ensure the MDB_STAMMDATEN speaker directory is loaded and protocols are re-parsed.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

// MARK: - Baseline Comparison

private struct AgeBaselineSection: View {
    let vm: VisualizationViewModel

    var body: some View {
        ChartSection(title: "Age Distribution: Parliament vs. Humor Events", subtitle: "Baseline = % of MdBs in age group (Stammdaten) · Observed = % of humor events by age group") {
            let comparison = vm.ageBaselineComparison
            if comparison.isEmpty {
                emptyLabel("No per-Wahlperiode age comparison data available.")
            } else {
                ForEach(Array(comparison.enumerated()), id: \.element.wahlperiode) { _, wpData in
                    AgeBaselineWPRow(wpData: wpData, isFirst: wpData.wahlperiode == comparison.first?.wahlperiode, isLast: wpData.wahlperiode == comparison.last?.wahlperiode)
                }
            }
        }
    }
}

private struct AgeBaselineWPRow: View {
    let wpData: (wahlperiode: Int, groups: [(group: String, baselinePercent: Double, observedPercent: Double)], totalMdB: Int, totalEvents: Int)
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("WP \(wpData.wahlperiode)")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(wpData.totalMdB) MdBs · \(wpData.totalEvents) events")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            let chartData: [(group: String, series: String, percent: Double)] = wpData.groups.flatMap { g in
                [
                    (group: g.group, series: "Parliament", percent: g.baselinePercent),
                    (group: g.group, series: "Humor Events", percent: g.observedPercent)
                ]
            }
            let indexed = Array(chartData.enumerated())

            Chart(indexed, id: \.offset) { pair in
                let item = pair.element
                BarMark(
                    x: .value("Age Group", item.group),
                    y: .value("Share %", item.percent)
                )
                .foregroundStyle(by: .value("Series", item.series))
                .position(by: .value("Series", item.series))
            }
            .chartForegroundStyleScale([
                "Parliament": Color.gray.opacity(0.5),
                "Humor Events": Color(red: 0.91, green: 0.55, blue: 0.34)
            ])
            .chartLegend(isFirst ? .visible : .hidden)
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let v = value.as(Double.self) { Text("\(Int(v))%") }
                    }
                }
            }
            .frame(height: 200)

            AgeDeltaIndicators(groups: wpData.groups)

            if !isLast {
                Divider()
            }
        }
    }
}

// MARK: - Average Age by Party

private struct AgeByPartySection: View {
    let vm: VisualizationViewModel

    var body: some View {
        ChartSection(title: "Average Speaker Age by Party", subtitle: "Mean age of humor-triggering speakers per party (top 8)") {
            let data = vm.ageByParty
            if data.isEmpty {
                emptyLabel("No per-party age data available.")
            } else {
                Chart(data, id: \.party) { item in
                    BarMark(
                        x: .value("Avg Age", item.averageAge),
                        y: .value("Party", item.party)
                    )
                    .foregroundStyle(partyColor(item.party))
                    .annotation(position: .trailing) {
                        Text(item.averageAge, format: .number.precision(.fractionLength(1)))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: CGFloat(data.count) * 34 + 20)
            }
        }
    }
}

// MARK: - Age Group by Party (stacked)

private struct AgeGroupByPartySection: View {
    let vm: VisualizationViewModel

    private var ageGroupColorScale: KeyValuePairs<String, Color> {
        [
            "Under 30": Color(red: 0.40, green: 0.76, blue: 0.65),
            "30–39": Color(red: 0.55, green: 0.63, blue: 0.80),
            "40–49": Color(red: 0.90, green: 0.77, blue: 0.46),
            "50–59": Color(red: 0.91, green: 0.55, blue: 0.34),
            "60–69": Color(red: 0.70, green: 0.42, blue: 0.64),
            "70+": Color(red: 0.50, green: 0.50, blue: 0.50)
        ]
    }

    var body: some View {
        ChartSection(title: "Age Group Distribution by Party", subtitle: "Age composition of humor-triggering speakers per party (top 8)") {
            let data = vm.ageGroupByParty
            if data.isEmpty {
                emptyLabel("No per-party age data available.")
            } else {
                let indexed = Array(data.enumerated())
                Chart(indexed, id: \.offset) { pair in
                    let item = pair.element
                    BarMark(
                        x: .value("Party", item.party),
                        y: .value("Count", item.count)
                    )
                    .foregroundStyle(by: .value("Age Group", item.group))
                }
                .chartForegroundStyleScale(ageGroupColorScale)
                .chartLegend(position: .bottom, alignment: .leading)
                .chartXAxis {
                    AxisMarks { _ in AxisValueLabel() }
                }
                .frame(height: 280)
            }
        }
    }
}

// MARK: - Age Group by Humor Intention

private struct AgeByIntentionSection: View {
    let vm: VisualizationViewModel

    private var ageGroupColorScale: KeyValuePairs<String, Color> {
        [
            "Under 30": Color(red: 0.40, green: 0.76, blue: 0.65),
            "30–39": Color(red: 0.55, green: 0.63, blue: 0.80),
            "40–49": Color(red: 0.90, green: 0.77, blue: 0.46),
            "50–59": Color(red: 0.91, green: 0.55, blue: 0.34),
            "60–69": Color(red: 0.70, green: 0.42, blue: 0.64),
            "70+": Color(red: 0.50, green: 0.50, blue: 0.50)
        ]
    }

    var body: some View {
        ChartSection(title: "Humor Intention by Age Group", subtitle: "Do different age groups trigger different humor types? (classified events only)") {
            let data = vm.ageByIntention
            if data.isEmpty {
                emptyLabel("No classified age data. Run Phase 3 to classify humor events first.")
            } else {
                let indexed = Array(data.enumerated())
                Chart(indexed, id: \.offset) { pair in
                    let item = pair.element
                    BarMark(
                        x: .value("Count", item.count),
                        y: .value("Intention", item.intention.rawValue)
                    )
                    .foregroundStyle(by: .value("Age Group", item.group))
                    .position(by: .value("Age Group", item.group))
                }
                .chartForegroundStyleScale(ageGroupColorScale)
                .chartLegend(position: .bottom, alignment: .leading)
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: CGFloat(HumorIntention.allCases.count) * 60 + 20)
            }
        }
    }
}

// MARK: - Average Age Trend Over Time

private struct AgeTrendSection: View {
    let vm: VisualizationViewModel

    private let afdEntry: Date = {
        var comps = DateComponents()
        comps.year = 2017; comps.month = 10; comps.day = 1
        return Calendar.current.date(from: comps)!
    }()

    var body: some View {
        ChartSection(title: "Average Speaker Age Over Time", subtitle: "Monthly mean age of humor-triggering speakers · vertical line marks AfD entry (Oct 2017)") {
            let data = vm.ageTemporalData
            if data.isEmpty {
                emptyLabel("No temporal age data available.")
            } else {
                AgeTrendChart(data: data, afdEntry: afdEntry)
            }
        }
    }
}

private struct AgeTrendChart: View {
    let data: [(month: Date, averageAge: Double)]
    let afdEntry: Date

    private var showMarker: Bool {
        let months = data.map(\.month)
        guard let first = months.min(), let last = months.max() else { return false }
        return first <= afdEntry && last >= afdEntry
    }

    private var spanMonths: Int {
        let months = data.map(\.month)
        guard let first = months.min(), let last = months.max() else { return 1 }
        let comps = Calendar.current.dateComponents([.month], from: first, to: last)
        return max(1, (comps.month ?? 0) + 1)
    }

    var body: some View {
        Chart {
            ForEach(data, id: \.month) { item in
                LineMark(
                    x: .value("Month", item.month, unit: .month),
                    y: .value("Avg Age", item.averageAge)
                )
                .interpolationMethod(.linear)
                .foregroundStyle(Color(red: 0.91, green: 0.55, blue: 0.34))
                .lineStyle(StrokeStyle(lineWidth: 2))
            }

            if showMarker {
                RuleMark(x: .value("AfD entry", afdEntry, unit: .month))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                    .foregroundStyle(.orange)
                    .annotation(position: .top, alignment: .leading, spacing: 4) {
                        Text("AfD entry\nOct 2017")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.leading)
                    }
            }
        }
        .chartXAxis {
            if spanMonths <= 18 {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).year())
                }
            } else if spanMonths <= 48 {
                AxisMarks(values: .stride(by: .month, count: 3)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
                }
            } else {
                AxisMarks(values: .stride(by: .year)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.year())
                }
            }
        }
        .frame(height: 260)
    }
}

// MARK: - Age Delta Indicators

private struct AgeDeltaIndicators: View {
    let groups: [(group: String, baselinePercent: Double, observedPercent: Double)]

    var body: some View {
        let deltas = groups
            .filter { $0.baselinePercent > 0 || $0.observedPercent > 0 }
            .map { AgeDelta(group: $0.group, delta: $0.observedPercent - $0.baselinePercent) }
        HStack(spacing: 12) {
            ForEach(deltas) { item in
                AgeDeltaCell(item: item)
            }
        }
    }
}

struct AgeDelta: Identifiable {
    let group: String
    let delta: Double
    var id: String { group }
}

private struct AgeDeltaCell: View {
    let item: AgeDelta

    var body: some View {
        VStack(spacing: 1) {
            Text(item.group).font(.caption2).foregroundStyle(.secondary)
            Text("\(item.delta >= 0 ? "+" : "")\(item.delta, format: .number.precision(.fractionLength(1)))pp")
                .font(.caption2.bold())
                .foregroundStyle(abs(item.delta) < 2 ? Color.secondary : (item.delta > 0 ? Color.orange : Color.blue))
        }
    }
}
