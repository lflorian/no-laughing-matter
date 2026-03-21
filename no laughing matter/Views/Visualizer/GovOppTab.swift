//
//  GovOppTab.swift
//  no laughing matter
//
//  Created by Claude on 21.03.26.
//

import SwiftUI
import Charts

struct GovOppTab: View {
    let vm: VisualizationViewModel

    private let govColor: Color = .blue
    private let oppColor: Color = .orange

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Chart 1: Humor Frequency by Role per WP
            ChartSection(title: "Humor Frequency: Government vs. Opposition",
                         subtitle: "Number of humor events triggered by speakers from governing vs. opposition parties") {
                let data = vm.govOppFrequency
                if data.isEmpty {
                    emptyLabel("No data with party information available.")
                } else {
                    let wahlperioden = Array(Set(data.map(\.wahlperiode))).sorted()
                    Chart {
                        ForEach(Array(data.enumerated()), id: \.offset) { _, item in
                            BarMark(
                                x: .value("WP", "WP \(item.wahlperiode)"),
                                y: .value("Events", item.count)
                            )
                            .foregroundStyle(item.role == .government ? govColor : oppColor)
                            .position(by: .value("Role", item.role.rawValue))
                        }
                    }
                    .chartForegroundStyleScale([
                        PoliticalRole.government.rawValue: govColor,
                        PoliticalRole.opposition.rawValue: oppColor,
                    ])
                    .chartLegend(position: .bottom)
                    .frame(height: 280)

                    // Coalition info below chart
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Coalitions")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: min(wahlperioden.count, 4)), alignment: .leading, spacing: 4) {
                            ForEach(wahlperioden, id: \.self) { wp in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("WP \(wp)").font(.caption.bold())
                                    Text(CoalitionData.coalitionLabel(for: wp))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            }

            // Chart 2: Intention Distribution – paired donuts per WP
            ChartSection(title: "Humor Intention: Government vs. Opposition",
                         subtitle: "Ziv classification distribution per legislative period (classified events only)") {
                let data = vm.govOppIntention
                if data.isEmpty {
                    emptyLabel("No classified events with party information available.")
                } else {
                    let wahlperioden = Array(Set(data.map(\.wahlperiode))).sorted()
                    let columns = Array(repeating: GridItem(.flexible(), spacing: 24), count: min(wahlperioden.count, 4))
                    LazyVGrid(columns: columns, alignment: .center, spacing: 20) {
                        ForEach(wahlperioden, id: \.self) { wp in
                            VStack(spacing: 6) {
                                Text("WP \(wp)").font(.caption.bold())
                                HStack(spacing: 12) {
                                    // Government donut
                                    let govData = data.filter { $0.wahlperiode == wp && $0.role == .government }
                                    VStack(spacing: 2) {
                                        if govData.isEmpty {
                                            Text("—").frame(width: 80, height: 80).foregroundStyle(.secondary)
                                        } else {
                                            Chart(govData, id: \.intention) { item in
                                                SectorMark(
                                                    angle: .value("Count", item.count),
                                                    innerRadius: .ratio(0.5),
                                                    angularInset: 2
                                                )
                                                .foregroundStyle(intentionColor(item.intention))
                                                .cornerRadius(3)
                                            }
                                            .frame(width: 80, height: 80)
                                        }
                                        Text("Gov.")
                                            .font(.caption2)
                                            .foregroundStyle(govColor)
                                    }

                                    // Opposition donut
                                    let oppData = data.filter { $0.wahlperiode == wp && $0.role == .opposition }
                                    VStack(spacing: 2) {
                                        if oppData.isEmpty {
                                            Text("—").frame(width: 80, height: 80).foregroundStyle(.secondary)
                                        } else {
                                            Chart(oppData, id: \.intention) { item in
                                                SectorMark(
                                                    angle: .value("Count", item.count),
                                                    innerRadius: .ratio(0.5),
                                                    angularInset: 2
                                                )
                                                .foregroundStyle(intentionColor(item.intention))
                                                .cornerRadius(3)
                                            }
                                            .frame(width: 80, height: 80)
                                        }
                                        Text("Opp.")
                                            .font(.caption2)
                                            .foregroundStyle(oppColor)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)

                    // Intention legend
                    HStack(spacing: 12) {
                        ForEach(HumorIntention.allCases, id: \.self) { intention in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(intentionColor(intention))
                                    .frame(width: 10, height: 10)
                                Text(intention.rawValue.capitalized)
                                    .font(.caption)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }

            // Chart 3: Humor Type (Heiterkeit vs. Lachen) by Role per WP
            ChartSection(title: "Humor Type: Government vs. Opposition",
                         subtitle: "Heiterkeit (mild amusement) vs. Lachen (laughter) by political role") {
                let data = vm.govOppHumorType
                if data.isEmpty {
                    emptyLabel("No data with party information available.")
                } else {
                    Chart {
                        ForEach(Array(data.enumerated()), id: \.offset) { _, item in
                            BarMark(
                                x: .value("WP", "WP \(item.wahlperiode)"),
                                y: .value("Events", item.count)
                            )
                            .foregroundStyle(humorTypeColor(item.type))
                            .position(by: .value("Role", item.role.rawValue))
                        }
                    }
                    .chartForegroundStyleScale([
                        HumorType.heiterkeit.description: humorTypeColor(.heiterkeit),
                        HumorType.lachen.description: humorTypeColor(.lachen),
                    ])
                    .chartLegend(position: .bottom)
                    .frame(height: 280)

                    // Sub-legend for role grouping
                    HStack(spacing: 16) {
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2).fill(govColor).frame(width: 12, height: 12)
                            Text("Left bar = Government").font(.caption)
                        }
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2).fill(oppColor).frame(width: 12, height: 12)
                            Text("Right bar = Opposition").font(.caption)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
}
