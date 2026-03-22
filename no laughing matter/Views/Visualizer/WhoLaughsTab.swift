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
                Toggle("Nach Sitzen normalisieren", isOn: $showNormalized)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Spacer()
            }

            ChartSection(
                title: "Reagierende Fraktionen",
                subtitle: showNormalized
                    ? "Humor-Marker pro Sitz (normalisiert nach durchschnittlicher Fraktionsgröße)"
                    : "Häufigkeit von Humor-Events einer Fraktion"
            ) {
                if showNormalized {
                    let data = Array(vm.laughingFraktionCountsNormalized.prefix(12))
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
                    let data = Array(vm.laughingFraktionCounts.prefix(12))
                    if data.isEmpty {
                        emptyLabel("Keine Fraktionsdaten gefunden. Protokolle enthalten möglicherweise keine Fraktionsangaben in Kommentar-Tags.")
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

            ChartSection(title: "Reagierende Einzelpersonen", subtitle: "MdB im Zusammenhang mit Lachen und Heiterkeit im Protokoll") {
                let data = Array(vm.laughingIndividualCounts.prefix(20))
                if data.isEmpty {
                    emptyLabel("Keine namentlich genannten Lacher gefunden. Die meisten Events sind nicht mit Einzelpersonen verknüpft.")
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
