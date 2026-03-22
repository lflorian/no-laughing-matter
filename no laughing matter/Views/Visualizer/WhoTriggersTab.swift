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
    @State private var showNormalized = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Toggle("Nach Sitzen normalisieren", isOn: $showNormalized)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Spacer()
            }

            ChartSection(
                title: "Auslösende Fraktionen",
                subtitle: showNormalized
                    ? "Humor-Events pro Sitz (normalisiert nach durchschnittlicher Fraktionsgröße)"
                    : "Fraktionszugehörigkeit der Sprecher, die am meisten Humor-Events bewirken"
            ) {
                if showNormalized {
                    let data = Array(vm.speakerFraktionCountsNormalized.prefix(8))
                    if data.isEmpty {
                        emptyLabel("Keine Fraktionsdaten gefunden oder Sitzdaten nicht verfügbar.")
                    } else {
                        Chart(data, id: \.party) { item in
                            BarMark(
                                x: .value("Pro Sitz", item.rate),
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
                    let data = Array(vm.speakerFraktionCounts.prefix(8))
                    if data.isEmpty {
                        emptyLabel("Keine Fraktionsdaten gefunden.")
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

            ChartSection(title: "Auslösende Einzelpersonen", subtitle: "MdB nach Frequenz der verursachten Humor-Marker") {
                let data = Array(vm.speakerIndividualCounts.prefix(20))
                if data.isEmpty {
                    emptyLabel("Keine Rednerdaten gefunden.")
                } else {
                    Chart(data, id: \.name) { item in
                        BarMark(
                            x: .value("Events", item.count),
                            y: .value("Redner:in", item.name)
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
