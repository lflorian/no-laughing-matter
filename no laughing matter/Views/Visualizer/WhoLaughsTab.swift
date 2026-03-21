//
//  WhoLaughsTab.swift
//  no laughing matter
//
//  Created by Claude on 21.03.26.
//

import SwiftUI
import Charts

struct WhoLaughsTab: View {
    let vm: VisualizationViewModel
    @State private var showNormalized = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Toggle("Normalize by seats", isOn: $showNormalized)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Spacer()
            }

            ChartSection(
                title: "Top Laughing Fraktionen",
                subtitle: showNormalized
                    ? "Laugh events per seat (normalized by average faction size)"
                    : "How often each party is recorded as laughing"
            ) {
                if showNormalized {
                    let data = Array(vm.laughingFraktionCountsNormalized.prefix(12))
                    if data.isEmpty {
                        emptyLabel("No laughing-party data found or seat data unavailable.")
                    } else {
                        Chart(data, id: \.party) { item in
                            BarMark(
                                x: .value("Per Seat", item.rate),
                                y: .value("Fraktion", item.party)
                            )
                            .foregroundStyle(partyColor(item.party))
                            .annotation(position: .trailing) {
                                Text(item.rate, format: .number.precision(.fractionLength(1)))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .chartYAxis { AxisMarks(position: .leading) }
                        .frame(height: CGFloat(data.count) * 34 + 20)
                    }
                } else {
                    let data = Array(vm.laughingFraktionCounts.prefix(12))
                    if data.isEmpty {
                        emptyLabel("No laughing-party data found. Protocols may lack party annotations in Kommentar tags.")
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
            }

            ChartSection(title: "Top Laughing Individuals", subtitle: "Top 20 individually named people recorded as laughing") {
                let data = Array(vm.laughingIndividualCounts.prefix(20))
                if data.isEmpty {
                    emptyLabel("No individually named laughers found. Most events are not associated with individuals.")
                } else {
                    Chart(data, id: \.name) { item in
                        BarMark(
                            x: .value("Events", item.count),
                            y: .value("Person", item.name)
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
