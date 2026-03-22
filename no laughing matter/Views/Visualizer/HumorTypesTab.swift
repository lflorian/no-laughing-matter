//
//  HumorTypesTab.swift
//  no laughing matter
//
//  Created by Claude on 21.03.26.
//

import SwiftUI
import Charts

struct HumorTypesTab: View {
    let vm: VisualizationViewModel

    private let afdEntry: Date = {
        var comps = DateComponents()
        comps.year = 2017; comps.month = 10; comps.day = 1
        return Calendar.current.date(from: comps)!
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Per-Wahlperiode pie charts
            ChartSection(title: "Heiterkeit im halben Hause", subtitle: "Anteil von Heiterkeit und Lachen nach Wahlperiode") {
                let byWP = vm.humorTypeByWahlperiode
                if byWP.isEmpty {
                    emptyLabel("No humor type data.")
                } else {
                    let wahlperioden = Array(Set(byWP.map(\.wahlperiode))).sorted()
                    HStack(alignment: .top, spacing: 24) {
                        ForEach(wahlperioden, id: \.self) { wp in
                            let wpData = byWP.filter { $0.wahlperiode == wp }
                            let total = wpData.reduce(0) { $0 + $1.count }
                            VStack(spacing: 6) {
                                Chart(wpData, id: \.type) { item in
                                    SectorMark(
                                        angle: .value("Count", item.count),
                                        innerRadius: .ratio(0.5),
                                        angularInset: 2
                                    )
                                    .foregroundStyle(humorTypeColor(item.type))
                                    .cornerRadius(3)
                                }
                                .frame(width: 100, height: 100)

                                // Percentage breakdown
                                VStack(spacing: 2) {
                                    ForEach(wpData.sorted(by: { $0.count > $1.count }), id: \.type) { item in
                                        let pct = total > 0 ? Double(item.count) / Double(total) * 100 : 0
                                        HStack(spacing: 3) {
                                            Circle()
                                                .fill(humorTypeColor(item.type))
                                                .frame(width: 6, height: 6)
                                            Text("\(pct, specifier: "%.0f")%")
                                                .font(.system(size: 9))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }

                                Text("WP \(wp)")
                                    .font(.caption.bold())
                                Text("\(total) Events")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)

                    // Legend
                    HStack(spacing: 16) {
                        ForEach(HumorType.allCases, id: \.self) { type in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(humorTypeColor(type))
                                    .frame(width: 10, height: 10)
                                Text(type.description)
                                    .font(.caption)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }

            // Humor type distribution by party
            ChartSection(title: "Heiterkeit & Lachen nach Fraktion", subtitle: "Verteilung von Heiterkeit und Lachen pro reagierender Fraktion") {
                let data = vm.humorTypeByParty
                if data.isEmpty {
                    emptyLabel("No humor type by party data.")
                } else {
                    let partyCount = Set(data.map(\.party)).count

                    let totals = Dictionary(grouping: data, by: \.party)
                        .mapValues { $0.reduce(0) { $0 + $1.count } }

                    Chart(data, id: \.party) { item in
                        let total = totals[item.party] ?? 1
                        let pct = Double(item.count) / Double(total) * 100.0
                        BarMark(
                            x: .value("Anteil (%)", pct),
                            y: .value("Fraktion", abbreviate(item.party))
                        )
                        .foregroundStyle(by: .value("Typ", item.type.description))
                    }
                    .chartForegroundStyleScale([
                        HumorType.heiterkeit.description: humorTypeColor(.heiterkeit),
                        HumorType.lachen.description: humorTypeColor(.lachen)
                    ])
                    .chartXAxis {
                        AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let v = value.as(Double.self) {
                                    Text("\(Int(v))%")
                                }
                            }
                        }
                    }
                    .chartXScale(domain: 0...100)
                    .chartYAxis {
                        AxisMarks(position: .leading)
                    }
                    .frame(height: CGFloat(partyCount) * 34 + 20)
                }
            }

            // Temporal line chart by humor type
            ChartSection(title: "Humor-Marker im Laufe der Zeit", subtitle: "Anzahl monatlicher Events nach Typ – vertikale Linie markiert Eintritt der AfD") {
                let data = vm.humorTypeTemporalData
                if data.isEmpty {
                    emptyLabel("No temporal humor type data.")
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
                        ForEach(HumorType.allCases, id: \.self) { type in
                            let typeData = data.filter { $0.type == type && $0.count > 0 }
                            ForEach(typeData, id: \.month) { item in
                                LineMark(
                                    x: .value("Month", item.month, unit: .month),
                                    y: .value("Events", item.count)
                                )
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(by: .value("Type", type.description))
                                .lineStyle(StrokeStyle(lineWidth: 2))
                            }
                        }

                        if showMarker {
                            RuleMark(x: .value("AfD entry", afdEntry, unit: .month))
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                                .foregroundStyle(.orange)
                        }
                    }
                    .chartForegroundStyleScale([
                        HumorType.heiterkeit.description: humorTypeColor(.heiterkeit),
                        HumorType.lachen.description: humorTypeColor(.lachen)
                    ])
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
