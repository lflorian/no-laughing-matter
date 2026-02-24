//
//  VisualizerView.swift
//  no laughing matter
//
//  Created by Claude on 24.02.26.
//

import Foundation
import SwiftUI
import Charts

// MARK: - View Model

@Observable
final class VisualizationViewModel {

    var events: [HumorEvent] = []
    var isLoading = false
    var errorMessage: String?
    var isClassified = false

    // MARK: Who Laughs

    var laughingFraktionCounts: [(party: String, count: Int)] {
        var counts: [String: Int] = [:]
        for event in events {
            for party in event.laughingParties {
                let p = normalizeParty(party)
                guard !p.isEmpty else { continue }
                counts[p, default: 0] += 1
            }
        }
        return counts.map { (party: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    var laughingIndividualCounts: [(name: String, party: String?, count: Int)] {
        var counts: [String: (party: String?, count: Int)] = [:]
        for event in events {
            for ind in event.laughingIndividuals {
                let name = ind.name.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { continue }
                let party = ind.party.map { normalizeParty($0) }
                if counts[name] == nil {
                    counts[name] = (party, 1)
                } else {
                    counts[name]!.count += 1
                }
            }
        }
        return counts.map { (name: $0.key, party: $0.value.party, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    // MARK: Who Triggers

    var speakerFraktionCounts: [(party: String, count: Int)] {
        var counts: [String: Int] = [:]
        for event in events {
            if let raw = event.speakerParty, !raw.isEmpty {
                counts[normalizeParty(raw), default: 0] += 1
            }
        }
        return counts.map { (party: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    var speakerIndividualCounts: [(name: String, party: String?, count: Int)] {
        var counts: [String: (party: String?, count: Int)] = [:]
        for event in events {
            let name = event.speakerName.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            let party = event.speakerParty.map { normalizeParty($0) }
            if counts[name] == nil {
                counts[name] = (party, 1)
            } else {
                counts[name]!.count += 1
            }
        }
        return counts.map { (name: $0.key, party: $0.value.party, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    // MARK: Cross-Party

    var crossPartyMatrix: [(speaker: String, laugher: String, count: Int)] {
        var matrix: [String: [String: Int]] = [:]
        for event in events {
            guard let raw = event.speakerParty, !raw.isEmpty else { continue }
            let sp = normalizeParty(raw)
            for laugher in event.laughingParties {
                let l = normalizeParty(laugher)
                guard !l.isEmpty else { continue }
                matrix[sp, default: [:]][l, default: 0] += 1
            }
        }
        var result: [(speaker: String, laugher: String, count: Int)] = []
        for (sp, laughers) in matrix {
            for (l, count) in laughers {
                result.append((speaker: sp, laugher: l, count: count))
            }
        }
        return result
    }

    var matrixParties: [String] {
        var totals: [String: Int] = [:]
        for entry in crossPartyMatrix {
            totals[entry.speaker, default: 0] += entry.count
            totals[entry.laugher, default: 0] += entry.count
        }
        return totals.sorted { $0.value > $1.value }
            .prefix(10)
            .map(\.key)
            .sorted()
    }

    // MARK: Intentions

    var intentionCounts: [(intention: HumorIntention, count: Int)] {
        var counts: [HumorIntention: Int] = [:]
        for event in events {
            if let intention = event.classification?.humorIntention {
                counts[intention, default: 0] += 1
            }
        }
        return counts.map { (intention: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    var intentionByFraktion: [(party: String, intention: HumorIntention, count: Int)] {
        var matrix: [String: [HumorIntention: Int]] = [:]
        for event in events {
            guard let intention = event.classification?.humorIntention else { continue }
            for party in event.laughingParties {
                let p = normalizeParty(party)
                guard !p.isEmpty else { continue }
                matrix[p, default: [:]][intention, default: 0] += 1
            }
        }
        // Top 8 parties by total classified events
        let topParties = matrix
            .map { (party: $0.key, total: $0.value.values.reduce(0, +)) }
            .sorted { $0.total > $1.total }
            .prefix(8)
            .map(\.party)

        var result: [(party: String, intention: HumorIntention, count: Int)] = []
        for party in topParties {
            for (intention, count) in matrix[party, default: [:]] {
                result.append((party: party, intention: intention, count: count))
            }
        }
        return result.sorted { $0.party < $1.party }
    }

    // MARK: Humor Types

    var humorTypeCounts: [(type: HumorType, count: Int)] {
        var counts: [HumorType: Int] = [:]
        for event in events { counts[event.humorType, default: 0] += 1 }
        return HumorType.allCases.compactMap { type in
            guard let count = counts[type], count > 0 else { return nil }
            return (type: type, count: count)
        }
    }

    // MARK: Temporal

    var temporalData: [(month: Date, count: Int)] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        var counts: [Date: Int] = [:]
        let calendar = Calendar.current

        for event in events {
            let date: Date?
            if event.datum.contains(".") {
                formatter.dateFormat = "dd.MM.yyyy"
                date = formatter.date(from: event.datum)
            } else {
                formatter.dateFormat = "yyyy-MM-dd"
                date = formatter.date(from: event.datum)
            }
            guard let d = date else { continue }
            let components = calendar.dateComponents([.year, .month], from: d)
            guard let monthDate = calendar.date(from: components) else { continue }
            counts[monthDate, default: 0] += 1
        }
        return counts.map { (month: $0.key, count: $0.value) }
            .sorted { $0.month < $1.month }
    }

    // MARK: Data source

    enum DataSource: Equatable {
        case parsed       // humor_events.json  (Phase 2)
        case classified   // classified_events.json (Phase 3)
    }

    var dataSource: DataSource = .parsed
    var parsedCount: Int   = 0
    var classifiedCount: Int = 0

    // MARK: Load

    /// Probes both storage files, then loads whichever source is selected.
    func load() {
        isLoading = true
        errorMessage = nil
        do {
            // Always probe counts so the picker can show them
            parsedCount     = (try? HumorEventStorage.shared.loadEvents())?.count ?? 0
            classifiedCount = (try? ClassificationStorage.shared.loadEvents())?.count ?? 0

            // Default to parsed if classified is a small subset (or doesn't exist)
            if classifiedCount == 0 {
                dataSource = .parsed
            }

            switch dataSource {
            case .classified:
                events = (try ClassificationStorage.shared.loadEvents()) ?? []
                isClassified = true
            case .parsed:
                events = (try HumorEventStorage.shared.loadEvents()) ?? []
                isClassified = false
            }
        } catch {
            errorMessage = error.localizedDescription
            events = []
        }
        isLoading = false
    }

    func switchSource(to source: DataSource) {
        dataSource = source
        load()
    }
}

// MARK: - Main View

struct VisualizerView: View {
    @State private var viewModel = VisualizationViewModel()
    @State private var selectedTab = 0

    private let tabs = ["Who Laughs", "Who Triggers", "Cross-Party", "Intentions", "Trends"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Phase 4: Visualizer")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(subtitleText)
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            // Data source picker — always visible so the user can switch datasets
            HStack(spacing: 12) {
                Text("Source:")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Picker("Data source", selection: Binding(
                    get: { viewModel.dataSource },
                    set: { viewModel.switchSource(to: $0) }
                )) {
                    Text(viewModel.parsedCount > 0
                         ? "All parsed events (\(viewModel.parsedCount))"
                         : "All parsed events")
                        .tag(VisualizationViewModel.DataSource.parsed)

                    Text(viewModel.classifiedCount > 0
                         ? "Classified only (\(viewModel.classifiedCount))"
                         : "Classified only")
                        .tag(VisualizationViewModel.DataSource.classified)
                }
                .pickerStyle(.segmented)
                .fixedSize()

                if viewModel.dataSource == .classified && viewModel.classifiedCount < viewModel.parsedCount {
                    Label("Classified set is a subset — switch to All for the full date range.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Divider()

            if viewModel.isLoading {
                ProgressView("Loading events…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.events.isEmpty {
                emptyStateView
            } else {
                Picker("", selection: $selectedTab) {
                    ForEach(tabs.indices, id: \.self) { i in
                        Text(tabs[i]).tag(i)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                ScrollView {
                    Group {
                        switch selectedTab {
                        case 0: WhoLaughsTab(vm: viewModel)
                        case 1: WhoTriggersTab(vm: viewModel)
                        case 2: CrossPartyTab(vm: viewModel)
                        case 3: IntentionsTab(vm: viewModel)
                        case 4: TrendsTab(vm: viewModel)
                        default: EmptyView()
                        }
                    }
                    .padding(.vertical, 8)
                }
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            Spacer()
        }
        .padding()
        .frame(minWidth: 720, minHeight: 600)
        .navigationTitle("Visualizer")
        .onAppear { viewModel.load() }
        .toolbar {
            ToolbarItem {
                Button("Reload", systemImage: "arrow.clockwise") {
                    viewModel.load()
                }
            }
        }
    }

    private var subtitleText: String {
        if viewModel.events.isEmpty {
            return "No data loaded yet"
        }
        let suffix = viewModel.dataSource == .classified ? " (classified)" : " (all parsed)"
        return "\(viewModel.events.count) humor events\(suffix)"
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No data to visualize")
                .font(.title3)
                .fontWeight(.medium)
            Text("Run Phases 1–3 to fetch protocols, extract humor events, and classify them.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button("Reload") { viewModel.load() }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Who Laughs Tab

struct WhoLaughsTab: View {
    let vm: VisualizationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ChartSection(title: "Top Laughing Fraktionen", subtitle: "How often each party is recorded as laughing") {
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

            ChartSection(title: "Top Laughing Individuals", subtitle: "Top 20 named individuals recorded laughing") {
                let data = Array(vm.laughingIndividualCounts.prefix(20))
                if data.isEmpty {
                    emptyLabel("No named individual data found. Protocols may only list parties, not individual names.")
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

// MARK: - Who Triggers Tab

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

// MARK: - Cross-Party Tab

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

// MARK: - Intentions Tab

struct IntentionsTab: View {
    let vm: VisualizationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
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
            }
        }
    }

    private var intentionColorScale: KeyValuePairs<String, Color> {
        [
            HumorIntention.irony.rawValue: intentionColor(.irony),
            HumorIntention.ridicule.rawValue: intentionColor(.ridicule),
            HumorIntention.distance.rawValue: intentionColor(.distance),
            HumorIntention.solidarity.rawValue: intentionColor(.solidarity),
            HumorIntention.strategic_disruption.rawValue: intentionColor(.strategic_disruption),
            HumorIntention.tension_relief.rawValue: intentionColor(.tension_relief),
            HumorIntention.self_affirmation.rawValue: intentionColor(.self_affirmation),
            HumorIntention.accidental.rawValue: intentionColor(.accidental),
            HumorIntention.unclear.rawValue: intentionColor(.unclear)
        ]
    }
}

// MARK: - Trends Tab

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
                    // Summary line: event count and date range
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

                    // Compute span so the x-axis stride adapts to the actual data range.
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

                            // Points ensure individual months are always visible
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
                            // Short range: one tick per month, show "Sep 2024"
                            AxisMarks(values: .stride(by: .month)) { _ in
                                AxisGridLine()
                                AxisTick()
                                AxisValueLabel(format: .dateTime.month(.abbreviated).year())
                            }
                        } else if spanMonths <= 48 {
                            // Medium range: quarterly ticks, show "Sep 2024"
                            AxisMarks(values: .stride(by: .month, count: 3)) { _ in
                                AxisGridLine()
                                AxisTick()
                                AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
                            }
                        } else {
                            // Long range: annual ticks
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

            ChartSection(title: "Humor Type Distribution", subtitle: "Breakdown across all events") {
                let data = vm.humorTypeCounts
                if data.isEmpty {
                    emptyLabel("No humor type data.")
                } else {
                    HStack(alignment: .center, spacing: 32) {
                        let total = data.reduce(0) { $0 + $1.count }

                        Chart(data, id: \.type) { item in
                            SectorMark(
                                angle: .value("Count", item.count),
                                innerRadius: .ratio(0.55),
                                angularInset: 2
                            )
                            .foregroundStyle(humorTypeColor(item.type))
                            .cornerRadius(4)
                        }
                        .frame(width: 200, height: 200)

                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(data, id: \.type) { item in
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(humorTypeColor(item.type))
                                        .frame(width: 11, height: 11)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.type.description)
                                            .font(.callout)
                                        Text("\(item.count) events · \(Int(Double(item.count) / Double(total) * 100))%")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

// MARK: - Shared Components

struct ChartSection<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            content()
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.06)))
    }
}

private func emptyLabel(_ message: String) -> some View {
    Label(message, systemImage: "exclamationmark.triangle")
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.vertical, 8)
}

// MARK: - Party Normalisation

/// Maps all raw party-name variants found in Bundestag protocols to a single canonical form.
/// This is needed because `laughingParties` are normalised by the parser but `speakerParty`
/// is stored verbatim from the XML <fraktion> tag.
private func normalizeParty(_ raw: String) -> String {
    let p = raw.trimmingCharacters(in: .whitespaces)
    let upper = p.uppercased()

    // CDU and CSU always form a joint Fraktion in the Bundestag
    if upper == "CDU" || upper == "CSU" || upper == "CDU/CSU" {
        return "CDU/CSU"
    }
    // Grüne — protocols use "BÜNDNIS 90/DIE GRÜNEN", "GRÜNEN", "BÜNDNISSES 90/DIE GRÜNEN", etc.
    if upper.contains("GRÜN") || upper.contains("BÜNDNIS") || upper.contains("BUNDNIS") {
        return "BÜNDNIS 90/DIE GRÜNEN"
    }
    // Die Linke / PDS
    if upper.contains("LINKE") || upper == "PDS" {
        return "Die Linke"
    }
    // AfD capitalisation variants
    if upper == "AFD" {
        return "AfD"
    }
    // SPD, FDP, BSW, SSW are stable — pass through trimmed
    return p
}

// MARK: - Color Helpers

private func partyColor(_ party: String) -> Color {
    switch normalizeParty(party) {
    case "CDU/CSU":                return Color(red: 0.18, green: 0.18, blue: 0.18)
    case "SPD":                    return Color(red: 0.84, green: 0.08, blue: 0.08)
    case "BÜNDNIS 90/DIE GRÜNEN": return Color(red: 0.25, green: 0.62, blue: 0.18)
    case "FDP":                    return Color(red: 0.87, green: 0.72, blue: 0.0)
    case "AfD":                    return Color(red: 0.0,  green: 0.44, blue: 0.70)
    case "Die Linke":              return Color(red: 0.58, green: 0.0,  blue: 0.28)
    case "BSW":                    return Color(red: 0.48, green: 0.0,  blue: 0.52)
    case "SSW":                    return Color(red: 0.0,  green: 0.48, blue: 0.52)
    default:                       return Color.gray
    }
}

private func intentionColor(_ intention: HumorIntention) -> Color {
    switch intention {
    case .irony:                return .purple
    case .ridicule:             return Color(red: 0.85, green: 0.1, blue: 0.1)
    case .distance:             return .orange
    case .solidarity:           return .green
    case .strategic_disruption: return Color(red: 0.6, green: 0.0, blue: 0.0)
    case .tension_relief:       return .blue
    case .self_affirmation:     return .teal
    case .accidental:           return .gray
    case .unclear:              return Color.gray.opacity(0.5)
    }
}

private func humorTypeColor(_ type: HumorType) -> Color {
    switch type {
    case .heiterkeit: return .blue
    case .lachen:     return .orange
    }
}

private func abbreviate(_ party: String) -> String {
    switch normalizeParty(party) {
    case "CDU/CSU":                return "CDU/CSU"
    case "SPD":                    return "SPD"
    case "BÜNDNIS 90/DIE GRÜNEN": return "Grüne"
    case "FDP":                    return "FDP"
    case "AfD":                    return "AfD"
    case "Die Linke":              return "Linke"
    case "BSW":                    return "BSW"
    case "SSW":                    return "SSW"
    case "fraktionslos":           return "frakti."
    default:
        let p = normalizeParty(party)
        return p.count > 9 ? String(p.prefix(8)) + "…" : p
    }
}

// MARK: - Preview

#Preview {
    VisualizerView()
}
