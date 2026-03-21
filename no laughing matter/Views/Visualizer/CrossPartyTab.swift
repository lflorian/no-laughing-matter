//
//  CrossPartyTab.swift
//  no laughing matter
//
//  Created by Claude on 21.03.26.
//

import SwiftUI
import Charts

struct CrossPartyTab: View {
    let vm: VisualizationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ChartSection(
                title: "Cross-Party Laughter Matrix",
                subtitle: "Row = speaker's Fraktion  ·  Column = laughing Fraktion  ·  Cell = event count"
            ) {
                let matrix = vm.crossPartyMatrix
                let parties = vm.matrixParties

                if matrix.isEmpty {
                    emptyLabel("No cross-party data. Speaker party info may be missing from the protocols.")
                } else {
                    let maxCount = matrix.map(\.count).max() ?? 1
                    let lookup = Dictionary(
                        uniqueKeysWithValues: matrix.map { ($0.speaker + "||" + $0.laugher, $0.count) }
                    )
                    let cellSize: CGFloat = 52

                    VStack(alignment: .leading, spacing: 3) {
                        // Column headers
                        HStack(alignment: .bottom, spacing: 3) {
                            Spacer().frame(width: 90)
                            ForEach(parties, id: \.self) { laugher in
                                Text(abbreviate(laugher))
                                    .font(.caption2.monospaced())
                                    .frame(width: cellSize)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        ForEach(parties, id: \.self) { speaker in
                            HStack(spacing: 3) {
                                Text(abbreviate(speaker))
                                    .font(.caption)
                                    .frame(width: 90, alignment: .trailing)
                                    .lineLimit(1)

                                ForEach(parties, id: \.self) { laugher in
                                    let count = lookup[speaker + "||" + laugher] ?? 0
                                    let intensity = count == 0 ? 0.0 : (0.12 + 0.88 * Double(count) / Double(maxCount))
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.accentColor.opacity(intensity))
                                        RoundedRectangle(cornerRadius: 4)
                                            .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 0.5)
                                        if count > 0 {
                                            Text("\(count)")
                                                .font(.caption2.monospacedDigit())
                                                .foregroundStyle(intensity > 0.45 ? .white : .primary)
                                        }
                                    }
                                    .frame(width: cellSize, height: 30)
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }

            Text("Darker cells = more events. Diagonal = same party laughing at their own speaker.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}
