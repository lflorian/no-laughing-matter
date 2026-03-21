//
//  WhoTriggersTab.swift
//  no laughing matter
//
//  Created by Claude on 21.03.26.
//

import SwiftUI
import Charts

struct WhoTriggersTab: View {
    let vm: VisualizationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ChartSection(title: "Top Triggering Fraktionen", subtitle: "Which party's speakers cause the most laughter") {
                let data = Array(vm.speakerFraktionCounts.prefix(12))
                if data.isEmpty {
                    emptyLabel("No speaker party data found.")
                } else {
                    Chart(data, id: \.party) { item in
                        BarMark(
                            x: .value("Events", item.count),
                            y: .value("Fraktion", item.party)
                        )
                        .foregroundStyle(partyColor(item.party))
                        .annotation(position: .trailing) {
                            Text("\(item.count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartYAxis { AxisMarks(position: .leading) }
                    .frame(height: CGFloat(data.count) * 34 + 20)
                }
            }

            ChartSection(title: "Top Triggering Individuals", subtitle: "Top 20 speakers who cause the most humor events") {
                let data = Array(vm.speakerIndividualCounts.prefix(20))
                if data.isEmpty {
                    emptyLabel("No speaker data found.")
                } else {
                    Chart(data, id: \.name) { item in
                        BarMark(
                            x: .value("Events", item.count),
                            y: .value("Speaker", item.name)
                        )
                        .foregroundStyle(item.party.map { partyColor($0) } ?? Color.gray)
                        .annotation(position: .trailing) {
                            Text("\(item.count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartYAxis { AxisMarks(position: .leading) }
                    .frame(height: CGFloat(data.count) * 28 + 20)
                }
            }
        }
    }
}
