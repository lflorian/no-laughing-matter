//
//  TrendsTab.swift
//  no laughing matter
//
//  Created by Claude on 21.03.26.
//

import SwiftUI
import Charts

struct TrendsTab: View {
    let vm: VisualizationViewModel

    private let afdEntry: Date = {
        var comps = DateComponents()
        comps.year = 2017; comps.month = 10; comps.day = 1
        return Calendar.current.date(from: comps)!
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ChartSection(title: "Humor Events Over Time", subtitle: "Monthly count · vertical line marks AfD entry into Bundestag (Oct 2017, WP 19)") {
                let data = vm.temporalData
                if data.isEmpty {
                    emptyLabel("No temporal data. Date fields may be missing or in an unrecognised format.")
                } else {
                    let totalEvents = data.reduce(0) { $0 + $1.count }
                    let dateRangeText: String = {
                        guard let first = data.first?.month, let last = data.last?.month else { return "" }
                        let fmt = DateFormatter()
                        fmt.dateFormat = "MMM yyyy"
                        if first == last { return fmt.string(from: first) }
                        return "\(fmt.string(from: first)) – \(fmt.string(from: last))"
                    }()
                    Text("\(totalEvents) events · \(dateRangeText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)

                    let showMarker = data.first.map { $0.month <= afdEntry } ?? false
                        && data.last.map { $0.month >= afdEntry } ?? false

                    let spanMonths: Int = {
                        guard let first = data.first?.month, let last = data.last?.month else { return 1 }
                        let comps = Calendar.current.dateComponents([.month], from: first, to: last)
                        return max(1, (comps.month ?? 0) + 1)
                    }()

                    Chart {
                        ForEach(data, id: \.month) { item in
                            AreaMark(
                                x: .value("Month", item.month, unit: .month),
                                y: .value("Events", item.count)
                            )
                            .interpolationMethod(.linear)
                            .foregroundStyle(Color.accentColor.opacity(0.15))

                            LineMark(
                                x: .value("Month", item.month, unit: .month),
                                y: .value("Events", item.count)
                            )
                            .interpolationMethod(.linear)
                            .foregroundStyle(Color.accentColor)
                            .lineStyle(StrokeStyle(lineWidth: 2))

                            PointMark(
                                x: .value("Month", item.month, unit: .month),
                                y: .value("Events", item.count)
                            )
                            .foregroundStyle(Color.accentColor)
                            .symbolSize(30)
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
        }
    }
}
