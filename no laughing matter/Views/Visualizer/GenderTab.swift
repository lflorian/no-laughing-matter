//
//  GenderTab.swift
//  no laughing matter
//
//  Created by Claude on 21.03.26.
//

import SwiftUI
import Charts

struct GenderTab: View {
    let vm: VisualizationViewModel

    private let afdEntry: Date = {
        var comps = DateComponents()
        comps.year = 2017; comps.month = 10; comps.day = 1
        return Calendar.current.date(from: comps)!
    }()

    private var genderColorScale: KeyValuePairs<String, Color> {
        [
            SpeakerDirectory.Gender.male.displayName: genderColor(.male),
            SpeakerDirectory.Gender.female.displayName: genderColor(.female)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Coverage banner
            let known = vm.genderKnownCount
            let total = vm.parsedCount
            if known > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "person.2")
                        .foregroundStyle(known < total ? .orange : .secondary)
                    Text("Based on \(known) of \(total) events with known speaker gender")
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

            if vm.genderOverallCounts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.2")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No gender data")
                        .font(.headline)
                    Text("Speaker gender information is not yet available. Ensure the MDB_STAMMDATEN speaker directory is loaded.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
            } else {
                // 1. Per-Wahlperiode baseline vs observed comparison
                ChartSection(title: "Frauenanteil: Parlament vs. Humor-Marker", subtitle: "Baseline: % weibliche MdBs (Stammdaten) | Beobachtet: % Humorereignisse ausgelöst von Frauen") {
                    let comparison = vm.genderBaselineComparison
                    if comparison.isEmpty {
                        emptyLabel("Keine Geschlechtervergleichsdaten pro Wahlperiode verfügbar.")
                    } else {
                        let genderColumns = Array(repeating: GridItem(.flexible(), spacing: 24), count: min(comparison.count, 6))
                        LazyVGrid(columns: genderColumns, alignment: .center, spacing: 16) {
                            ForEach(comparison, id: \.wahlperiode) { item in
                                VStack(spacing: 6) {
                                    ZStack {
                                        // Outer ring: observed
                                        Chart {
                                            SectorMark(angle: .value("Female", item.observedFemalePercent), innerRadius: .ratio(0.55), angularInset: 1)
                                                .foregroundStyle(genderColor(.female))
                                                .cornerRadius(3)
                                            SectorMark(angle: .value("Male", 100 - item.observedFemalePercent), innerRadius: .ratio(0.55), angularInset: 1)
                                                .foregroundStyle(genderColor(.male).opacity(0.3))
                                                .cornerRadius(3)
                                        }
                                        .frame(width: 100, height: 100)
                                        // Inner ring: baseline
                                        Chart {
                                            SectorMark(angle: .value("Female", item.baselineFemalePercent), innerRadius: .ratio(0.45), outerRadius: .ratio(0.55), angularInset: 1)
                                                .foregroundStyle(Color.gray.opacity(0.5))
                                                .cornerRadius(2)
                                            SectorMark(angle: .value("Male", 100 - item.baselineFemalePercent), innerRadius: .ratio(0.45), outerRadius: .ratio(0.55), angularInset: 1)
                                                .foregroundStyle(Color.gray.opacity(0.15))
                                                .cornerRadius(2)
                                        }
                                        .frame(width: 100, height: 100)
                                    }

                                    Text("WP \(item.wahlperiode)")
                                        .font(.caption.bold())

                                    let delta = item.observedFemalePercent - item.baselineFemalePercent
                                    VStack(spacing: 2) {
                                        Text("Baseline: \(item.baselineFemalePercent, format: .number.precision(.fractionLength(1)))%")
                                            .foregroundStyle(.secondary)
                                        Text("Beobachtet: \(item.observedFemalePercent, format: .number.precision(.fractionLength(1)))%")
                                            .foregroundStyle(genderColor(.female))
                                        Text("\(delta >= 0 ? "+" : "")\(delta, format: .number.precision(.fractionLength(1)))pp")
                                            .foregroundStyle(delta >= 0 ? .green : .red)
                                            .fontWeight(.medium)
                                    }
                                    .font(.caption2)

                                    Text("\(item.totalEvents) Events")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .padding(.vertical, 4)

                        // Legend
                        HStack(spacing: 16) {
                            HStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 2).fill(Color.gray.opacity(0.5)).frame(width: 16, height: 8)
                                Text("Baseline (% weibliche MdBs)").font(.caption)
                            }
                            HStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 2).fill(genderColor(.female)).frame(width: 16, height: 8)
                                Text("Beobachtet (% weibliche Humorereignisse)").font(.caption)
                            }
                            HStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 2).fill(genderColor(.male).opacity(0.3)).frame(width: 16, height: 8)
                                Text("Männeranteil").font(.caption)
                            }
                        }
                        .padding(.top, 4)
                    }
                }

                // 2. Horizontal bar: Female Share by Party
                ChartSection(title: "Female Share by Party", subtitle: "Percentage of humor events triggered by female speakers per party (top 8)") {
                    let data = vm.genderProportionByParty
                    if data.isEmpty {
                        emptyLabel("No per-party gender data available.")
                    } else {
                        Chart(data, id: \.party) { item in
                            BarMark(
                                x: .value("Female %", item.femaleShare),
                                y: .value("Party", item.party)
                            )
                            .foregroundStyle(genderColor(.female))
                            .annotation(position: .trailing) {
                                Text(item.femaleShare, format: .number.precision(.fractionLength(1)))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                + Text("%")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .chartXAxis {
                            AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                                AxisGridLine()
                                AxisTick()
                                AxisValueLabel {
                                    if let v = value.as(Double.self) {
                                        Text("\(Int(v))%")
                                    }
                                }
                            }
                        }
                        .chartXScale(domain: 0...100)
                        .chartYAxis { AxisMarks(position: .leading) }
                        .frame(height: CGFloat(data.count) * 34 + 20)
                    }
                }

                // 3. Stacked vertical bar: Events by Party and Gender
                ChartSection(title: "Events by Party and Gender", subtitle: "Absolute humor event counts per party, stacked by gender (top 8)") {
                    let data = vm.genderByParty
                    if data.isEmpty {
                        emptyLabel("No per-party gender data available.")
                    } else {
                        let indexed = Array(data.enumerated())
                        Chart(indexed, id: \.offset) { pair in
                            let item = pair.element
                            BarMark(
                                x: .value("Party", item.party),
                                y: .value("Count", item.count)
                            )
                            .foregroundStyle(by: .value("Gender", item.gender.displayName))
                        }
                        .chartForegroundStyleScale(genderColorScale)
                        .chartLegend(position: .bottom, alignment: .leading)
                        .chartXAxis {
                            AxisMarks { _ in
                                AxisValueLabel()
                            }
                        }
                        .frame(height: 280)
                    }
                }

                // 4. Grouped horizontal bar: Humor Intention by Gender
                ChartSection(title: "Humor Intention by Gender", subtitle: "Do male and female speakers trigger different humor types? (classified events only)") {
                    let data = vm.genderByIntention
                    if data.isEmpty {
                        emptyLabel("No classified gender data. Run Phase 3 to classify humor events first.")
                    } else {
                        let indexed = Array(data.enumerated())
                        Chart(indexed, id: \.offset) { pair in
                            let item = pair.element
                            BarMark(
                                x: .value("Count", item.count),
                                y: .value("Intention", item.intention.rawValue)
                            )
                            .foregroundStyle(by: .value("Gender", item.gender.displayName))
                            .position(by: .value("Gender", item.gender.displayName))
                        }
                        .chartForegroundStyleScale(genderColorScale)
                        .chartLegend(position: .bottom, alignment: .leading)
                        .chartYAxis { AxisMarks(position: .leading) }
                        .frame(height: CGFloat(HumorIntention.allCases.count) * 50 + 20)
                    }
                }

                // 5. Dual line chart: Gender Trends Over Time
                ChartSection(title: "Gender Trends Over Time", subtitle: "Monthly humor event counts by speaker gender · vertical line marks AfD entry (Oct 2017)") {
                    let data = vm.genderTemporalData
                    if data.isEmpty {
                        emptyLabel("No temporal gender data available.")
                    } else {
                        let showMarker: Bool = {
                            let months = data.map(\.month)
                            guard let first = months.min(), let last = months.max() else { return false }
                            return first <= afdEntry && last >= afdEntry
                        }()

                        let spanMonths: Int = {
                            let months = data.map(\.month)
                            guard let first = months.min(), let last = months.max() else { return 1 }
                            let comps = Calendar.current.dateComponents([.month], from: first, to: last)
                            return max(1, (comps.month ?? 0) + 1)
                        }()

                        Chart {
                            ForEach([SpeakerDirectory.Gender.male, .female], id: \.self) { gender in
                                let genderData = data.filter { $0.gender == gender }
                                ForEach(genderData, id: \.month) { item in
                                    LineMark(
                                        x: .value("Month", item.month, unit: .month),
                                        y: .value("Events", item.count)
                                    )
                                    .interpolationMethod(.linear)
                                    .foregroundStyle(genderColor(gender))
                                    .lineStyle(StrokeStyle(lineWidth: 2))
                                }
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
                        .chartForegroundStyleScale(genderColorScale)
                        .chartLegend(position: .bottom, alignment: .leading)
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
            }
        }
    }
}
