//
//  IntentionsTab.swift
//  no laughing matter
//
//  Created by Claude on 21.03.26.
//

import SwiftUI
import Charts

struct IntentionsTab: View {
    let vm: VisualizationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Classified-subset banner
            let classified = vm.classifiedCount
            let total = vm.parsedCount
            if classified > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "brain")
                        .foregroundStyle(classified < total ? .orange : .secondary)
                    Text("Based on \(classified) of \(total) events with LLM classification")
                        .font(.callout)
                        .foregroundStyle(classified < total ? .orange : .secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill((classified < total ? Color.orange : Color.secondary).opacity(0.08))
                )
            }

            if vm.intentionCounts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "brain")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No classification data")
                        .font(.headline)
                    Text("Run Phase 3 (LLM Classifier) to get humor intention classifications.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
            } else {
                ChartSection(title: "Overall Humor Intention Distribution", subtitle: "Classified events only") {
                    Chart(vm.intentionCounts, id: \.intention) { item in
                        BarMark(
                            x: .value("Count", item.count),
                            y: .value("Intention", item.intention.rawValue)
                        )
                        .foregroundStyle(intentionColor(item.intention))
                        .annotation(position: .trailing) {
                            Text("\(item.count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartYAxis { AxisMarks(position: .leading) }
                    .frame(height: CGFloat(vm.intentionCounts.count) * 36 + 20)
                }

                ChartSection(title: "Intention by Fraktion", subtitle: "Top 8 laughing parties — stacked by classified intention") {
                    let data = vm.intentionByFraktion
                    if data.isEmpty {
                        emptyLabel("No per-party intention data.")
                    } else {
                        let indexed = Array(data.enumerated())
                        Chart(indexed, id: \.offset) { pair in
                            let item = pair.element
                            BarMark(
                                x: .value("Fraktion", item.party),
                                y: .value("Count", item.count)
                            )
                            .foregroundStyle(by: .value("Intention", item.intention.rawValue))
                        }
                        .chartForegroundStyleScale(intentionColorScale)
                        .chartLegend(position: .bottom, alignment: .leading)
                        .chartXAxis {
                            AxisMarks { _ in
                                AxisValueLabel()
                            }
                        }
                        .frame(height: 280)
                    }
                }

                // Per-Wahlperiode intention pie charts
                ChartSection(title: "Intention by Wahlperiode", subtitle: "Intention distribution per legislative period (classified events)") {
                    let byWP = vm.intentionByWahlperiode
                    if byWP.isEmpty {
                        emptyLabel("No per-Wahlperiode intention data.")
                    } else {
                        let wahlperioden = Array(Set(byWP.map(\.wahlperiode))).sorted()
                        let pieColumns = Array(repeating: GridItem(.flexible(), spacing: 24), count: min(wahlperioden.count, 6))
                        LazyVGrid(columns: pieColumns, alignment: .center, spacing: 16) {
                            ForEach(wahlperioden, id: \.self) { wp in
                                let wpData = byWP.filter { $0.wahlperiode == wp }
                                let total = wpData.reduce(0) { $0 + $1.count }
                                VStack(spacing: 6) {
                                    Chart(wpData, id: \.intention) { item in
                                        SectorMark(
                                            angle: .value("Count", item.count),
                                            innerRadius: .ratio(0.5),
                                            angularInset: 2
                                        )
                                        .foregroundStyle(intentionColor(item.intention))
                                        .cornerRadius(3)
                                    }
                                    .frame(width: 100, height: 100)

                                    Text("WP \(wp)")
                                        .font(.caption.bold())
                                    Text("\(total) events")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)

                        // Legend
                        let allIntentions = HumorIntention.allCases
                        let columns = Array(repeating: GridItem(.flexible(), alignment: .leading), count: 4)
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                            ForEach(allIntentions, id: \.self) { intention in
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(intentionColor(intention))
                                        .frame(width: 10, height: 10)
                                    Text(intention.rawValue)
                                        .font(.caption)
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
        }
    }

    private var intentionColorScale: KeyValuePairs<String, Color> {
        [
            HumorIntention.aggressive.rawValue: intentionColor(.aggressive),
            HumorIntention.social.rawValue: intentionColor(.social),
            HumorIntention.defensive.rawValue: intentionColor(.defensive),
            HumorIntention.intellectual.rawValue: intentionColor(.intellectual),
            HumorIntention.sexual.rawValue: intentionColor(.sexual),
            HumorIntention.unclear.rawValue: intentionColor(.unclear)
        ]
    }
}
