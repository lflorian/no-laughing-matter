//
//  VisualizerView.swift
//  no laughing matter
//
//  Created by Claude on 24.02.26.
//

import Foundation
import SwiftUI
import SwiftData
import Charts
import AppKit
import UniformTypeIdentifiers

// MARK: - View Model

@Observable
final class VisualizationViewModel {

    var events: [HumorEvent] = []
    var isLoading = false
    var errorMessage: String?
    var parsedCount: Int = 0
    var classifiedCount: Int = 0

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

    // MARK: Humor Types

    var humorTypeCounts: [(type: HumorType, count: Int)] {
        var counts: [HumorType: Int] = [:]
        for event in events { counts[event.humorType, default: 0] += 1 }
        return HumorType.allCases.compactMap { type in
            guard let count = counts[type], count > 0 else { return nil }
            return (type: type, count: count)
        }
    }

    var humorTypeByWahlperiode: [(wahlperiode: Int, type: HumorType, count: Int)] {
        var matrix: [Int: [HumorType: Int]] = [:]
        for event in events {
            matrix[event.wahlperiode, default: [:]][event.humorType, default: 0] += 1
        }
        var result: [(wahlperiode: Int, type: HumorType, count: Int)] = []
        for (wp, types) in matrix.sorted(by: { $0.key < $1.key }) {
            for type in HumorType.allCases {
                if let count = types[type], count > 0 {
                    result.append((wahlperiode: wp, type: type, count: count))
                }
            }
        }
        return result
    }

    var humorTypeTemporalData: [(month: Date, type: HumorType, count: Int)] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        var counts: [Date: [HumorType: Int]] = [:]
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
            counts[monthDate, default: [:]][event.humorType, default: 0] += 1
        }

        var result: [(month: Date, type: HumorType, count: Int)] = []
        for (month, types) in counts.sorted(by: { $0.key < $1.key }) {
            for type in HumorType.allCases {
                result.append((month: month, type: type, count: types[type] ?? 0))
            }
        }
        return result
    }

    // MARK: Intentions

    var intentionCounts: [(intention: HumorIntention, count: Int)] {
        var counts: [HumorIntention: Int] = [:]
        for event in events {
            if let intention = event.classification?.primaryIntention {
                counts[intention, default: 0] += 1
            }
        }
        return counts.map { (intention: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    var intentionByFraktion: [(party: String, intention: HumorIntention, count: Int)] {
        var matrix: [String: [HumorIntention: Int]] = [:]
        for event in events {
            guard let intention = event.classification?.primaryIntention else { continue }
            for party in event.laughingParties {
                let p = normalizeParty(party)
                guard !p.isEmpty else { continue }
                matrix[p, default: [:]][intention, default: 0] += 1
            }
        }
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

    var intentionByWahlperiode: [(wahlperiode: Int, intention: HumorIntention, count: Int)] {
        var matrix: [Int: [HumorIntention: Int]] = [:]
        for event in events {
            guard let intention = event.classification?.primaryIntention else { continue }
            matrix[event.wahlperiode, default: [:]][intention, default: 0] += 1
        }
        var result: [(wahlperiode: Int, intention: HumorIntention, count: Int)] = []
        for (wp, intentions) in matrix.sorted(by: { $0.key < $1.key }) {
            for intention in HumorIntention.allCases {
                if let count = intentions[intention], count > 0 {
                    result.append((wahlperiode: wp, intention: intention, count: count))
                }
            }
        }
        return result
    }

    // MARK: Gender

    var genderKnownCount: Int {
        events.filter { $0.speakerGender != nil }.count
    }

    var genderOverallCounts: [(gender: SpeakerDirectory.Gender, count: Int)] {
        var counts: [SpeakerDirectory.Gender: Int] = [:]
        for event in events {
            guard let g = event.speakerGender else { continue }
            counts[g, default: 0] += 1
        }
        return counts.map { (gender: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    /// Per-Wahlperiode: baseline female share (from MdB Stammdaten) vs observed female share (from humor events)
    var genderBaselineComparison: [(wahlperiode: Int, baselineFemalePercent: Double, observedFemalePercent: Double, totalMdB: Int, femaleMdB: Int, totalEvents: Int, femaleEvents: Int)] {
        // Group events by Wahlperiode
        var eventCounts: [Int: (male: Int, female: Int)] = [:]
        for event in events {
            guard let g = event.speakerGender else { continue }
            switch g {
            case .male: eventCounts[event.wahlperiode, default: (0, 0)].male += 1
            case .female: eventCounts[event.wahlperiode, default: (0, 0)].female += 1
            }
        }

        let dir = SpeakerDirectory.shared
        return eventCounts.keys.sorted().compactMap { wp in
            let composition = dir.genderComposition(forWahlperiode: wp)
            let totalMdB = composition.male + composition.female
            guard totalMdB > 0 else { return nil }
            let evts = eventCounts[wp]!
            let totalEvents = evts.male + evts.female
            guard totalEvents > 0 else { return nil }
            let baselinePct = Double(composition.female) / Double(totalMdB) * 100.0
            let observedPct = Double(evts.female) / Double(totalEvents) * 100.0
            return (wahlperiode: wp, baselineFemalePercent: baselinePct, observedFemalePercent: observedPct,
                    totalMdB: totalMdB, femaleMdB: composition.female,
                    totalEvents: totalEvents, femaleEvents: evts.female)
        }
    }

    var genderProportionByParty: [(party: String, femaleShare: Double, maleCount: Int, femaleCount: Int)] {
        var male: [String: Int] = [:]
        var female: [String: Int] = [:]
        for event in events {
            guard let g = event.speakerGender,
                  let raw = event.speakerParty, !raw.isEmpty else { continue }
            let p = normalizeParty(raw)
            switch g {
            case .male: male[p, default: 0] += 1
            case .female: female[p, default: 0] += 1
            }
        }
        let allParties = Set(male.keys).union(female.keys)
        return allParties.map { party in
            let m = male[party] ?? 0
            let f = female[party] ?? 0
            let share = (m + f) > 0 ? Double(f) / Double(m + f) * 100.0 : 0
            return (party: party, femaleShare: share, maleCount: m, femaleCount: f)
        }
        .sorted { ($0.maleCount + $0.femaleCount) > ($1.maleCount + $1.femaleCount) }
        .prefix(8).map { $0 }
    }

    var genderByParty: [(party: String, gender: SpeakerDirectory.Gender, count: Int)] {
        var counts: [String: [SpeakerDirectory.Gender: Int]] = [:]
        for event in events {
            guard let g = event.speakerGender,
                  let raw = event.speakerParty, !raw.isEmpty else { continue }
            let p = normalizeParty(raw)
            counts[p, default: [:]][g, default: 0] += 1
        }
        let topParties = counts.map { (party: $0.key, total: $0.value.values.reduce(0, +)) }
            .sorted { $0.total > $1.total }
            .prefix(8).map(\.party)
        var result: [(party: String, gender: SpeakerDirectory.Gender, count: Int)] = []
        for party in topParties {
            for gender in [SpeakerDirectory.Gender.male, .female] {
                if let count = counts[party]?[gender], count > 0 {
                    result.append((party: party, gender: gender, count: count))
                }
            }
        }
        return result
    }

    var genderByIntention: [(intention: HumorIntention, gender: SpeakerDirectory.Gender, count: Int)] {
        var counts: [HumorIntention: [SpeakerDirectory.Gender: Int]] = [:]
        for event in events {
            guard let g = event.speakerGender,
                  let intention = event.classification?.primaryIntention else { continue }
            counts[intention, default: [:]][g, default: 0] += 1
        }
        var result: [(intention: HumorIntention, gender: SpeakerDirectory.Gender, count: Int)] = []
        for intention in HumorIntention.allCases {
            for gender in [SpeakerDirectory.Gender.male, .female] {
                if let count = counts[intention]?[gender], count > 0 {
                    result.append((intention: intention, gender: gender, count: count))
                }
            }
        }
        return result
    }

    var genderTemporalData: [(month: Date, gender: SpeakerDirectory.Gender, count: Int)] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        var counts: [Date: [SpeakerDirectory.Gender: Int]] = [:]
        let calendar = Calendar.current

        for event in events {
            guard let g = event.speakerGender else { continue }
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
            counts[monthDate, default: [:]][g, default: 0] += 1
        }
        var result: [(month: Date, gender: SpeakerDirectory.Gender, count: Int)] = []
        for (month, genderCounts) in counts.sorted(by: { $0.key < $1.key }) {
            for gender in [SpeakerDirectory.Gender.male, .female] {
                if let count = genderCounts[gender], count > 0 {
                    result.append((month: month, gender: gender, count: count))
                }
            }
        }
        return result
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

    // MARK: Load

    func load(context: ModelContext) {
        isLoading = true
        errorMessage = nil
        do {
            let allDescriptor = FetchDescriptor<HumorEvent>()
            let allEvents = try context.fetch(allDescriptor)
            parsedCount = allEvents.count
            classifiedCount = allEvents.filter { $0.classification != nil }.count
            events = allEvents
        } catch {
            errorMessage = error.localizedDescription
            events = []
        }
        isLoading = false
    }
}

// MARK: - Main View

struct VisualizerView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = VisualizationViewModel()
    @State private var selectedTab = 0

    private let tabs = ["Who Laughs", "Who Triggers", "Cross-Party", "Humor Types", "Intentions", "Trends", "Gender"]

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
                        case 3: HumorTypesTab(vm: viewModel)
                        case 4: IntentionsTab(vm: viewModel)
                        case 5: TrendsTab(vm: viewModel)
                        case 6: GenderTab(vm: viewModel)
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
        .onAppear { viewModel.load(context: modelContext) }
        .toolbar {
            ToolbarItem {
                Button("Reload", systemImage: "arrow.clockwise") {
                    viewModel.load(context: modelContext)
                }
            }
        }
    }

    private var subtitleText: String {
        if viewModel.events.isEmpty {
            return "No data loaded yet"
        }
        return "\(viewModel.events.count) humor events"
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
            Button("Reload") { viewModel.load(context: modelContext) }
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

// MARK: - Humor Types Tab

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
            ChartSection(title: "Heiterkeit vs. Lachen by Wahlperiode", subtitle: "Proportion of humor types per legislative period") {
                let byWP = vm.humorTypeByWahlperiode
                if byWP.isEmpty {
                    emptyLabel("No humor type data.")
                } else {
                    let wahlperioden = Array(Set(byWP.map(\.wahlperiode))).sorted()
                    let columns = Array(repeating: GridItem(.flexible(), spacing: 24), count: min(wahlperioden.count, 6))
                    LazyVGrid(columns: columns, alignment: .center, spacing: 16) {
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

            // Temporal line chart by humor type
            ChartSection(title: "Humor Type Over Time", subtitle: "Monthly count by type · vertical line marks AfD entry (Oct 2017)") {
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
                                .interpolationMethod(.linear)
                                .foregroundStyle(humorTypeColor(type))
                                .lineStyle(StrokeStyle(lineWidth: 2))
                            }
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

                    // Legend
                    HStack(spacing: 16) {
                        ForEach(HumorType.allCases, id: \.self) { type in
                            HStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(humorTypeColor(type))
                                    .frame(width: 16, height: 3)
                                Text(type.description)
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

// MARK: - Intentions Tab

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

// MARK: - Gender Tab

struct GenderTab: View {
    let vm: VisualizationViewModel

    private let afdEntry: Date = {
        var comps = DateComponents()
        comps.year = 2017; comps.month = 10; comps.day = 1
        return Calendar.current.date(from: comps)!
    }()

    private var genderColorScale: KeyValuePairs<String, Color> {
        [
            SpeakerDirectory.Gender.male.displayName: genderColor(.male),
            SpeakerDirectory.Gender.female.displayName: genderColor(.female)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Coverage banner
            let known = vm.genderKnownCount
            let total = vm.parsedCount
            if known > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "person.2")
                        .foregroundStyle(known < total ? .orange : .secondary)
                    Text("Based on \(known) of \(total) events with known speaker gender")
                        .font(.callout)
                        .foregroundStyle(known < total ? .orange : .secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill((known < total ? Color.orange : Color.secondary).opacity(0.08))
                )
            }

            if vm.genderOverallCounts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.2")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No gender data")
                        .font(.headline)
                    Text("Speaker gender information is not yet available. Ensure the MDB_STAMMDATEN speaker directory is loaded.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
            } else {
                // 1. Per-Wahlperiode baseline vs observed comparison
                ChartSection(title: "Female Share: Parliament vs. Humor Events", subtitle: "Baseline = % female MdBs (Stammdaten) · Observed = % humor events triggered by women") {
                    let comparison = vm.genderBaselineComparison
                    if comparison.isEmpty {
                        emptyLabel("No per-Wahlperiode gender comparison data available.")
                    } else {
                        let genderColumns = Array(repeating: GridItem(.flexible(), spacing: 24), count: min(comparison.count, 6))
                        LazyVGrid(columns: genderColumns, alignment: .center, spacing: 16) {
                            ForEach(comparison, id: \.wahlperiode) { item in
                                VStack(spacing: 6) {
                                    ZStack {
                                        // Outer ring: observed
                                        Chart {
                                            SectorMark(angle: .value("Female", item.observedFemalePercent), innerRadius: .ratio(0.55), angularInset: 1)
                                                .foregroundStyle(genderColor(.female))
                                                .cornerRadius(3)
                                            SectorMark(angle: .value("Male", 100 - item.observedFemalePercent), innerRadius: .ratio(0.55), angularInset: 1)
                                                .foregroundStyle(genderColor(.male).opacity(0.3))
                                                .cornerRadius(3)
                                        }
                                        .frame(width: 100, height: 100)
                                        // Inner ring: baseline
                                        Chart {
                                            SectorMark(angle: .value("Female", item.baselineFemalePercent), innerRadius: .ratio(0.45), outerRadius: .ratio(0.55), angularInset: 1)
                                                .foregroundStyle(Color.gray.opacity(0.5))
                                                .cornerRadius(2)
                                            SectorMark(angle: .value("Male", 100 - item.baselineFemalePercent), innerRadius: .ratio(0.45), outerRadius: .ratio(0.55), angularInset: 1)
                                                .foregroundStyle(Color.gray.opacity(0.15))
                                                .cornerRadius(2)
                                        }
                                        .frame(width: 100, height: 100)
                                    }

                                    Text("WP \(item.wahlperiode)")
                                        .font(.caption.bold())

                                    let delta = item.observedFemalePercent - item.baselineFemalePercent
                                    VStack(spacing: 2) {
                                        Text("Baseline: \(String(format: "%.1f", item.baselineFemalePercent))%")
                                            .foregroundStyle(.secondary)
                                        Text("Observed: \(String(format: "%.1f", item.observedFemalePercent))%")
                                            .foregroundStyle(genderColor(.female))
                                        Text("\(delta >= 0 ? "+" : "")\(String(format: "%.1f", delta))pp")
                                            .foregroundStyle(delta >= 0 ? .green : .red)
                                            .fontWeight(.medium)
                                    }
                                    .font(.caption2)

                                    Text("\(item.totalEvents) events")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .padding(.vertical, 4)

                        // Legend
                        HStack(spacing: 16) {
                            HStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 2).fill(Color.gray.opacity(0.5)).frame(width: 16, height: 8)
                                Text("Baseline (% female MdBs)").font(.caption)
                            }
                            HStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 2).fill(genderColor(.female)).frame(width: 16, height: 8)
                                Text("Observed (% female humor events)").font(.caption)
                            }
                            HStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 2).fill(genderColor(.male).opacity(0.3)).frame(width: 16, height: 8)
                                Text("Male share").font(.caption)
                            }
                        }
                        .padding(.top, 4)
                    }
                }

                // 2. Horizontal bar: Female Share by Party
                ChartSection(title: "Female Share by Party", subtitle: "Percentage of humor events triggered by female speakers per party (top 8)") {
                    let data = vm.genderProportionByParty
                    if data.isEmpty {
                        emptyLabel("No per-party gender data available.")
                    } else {
                        Chart(data, id: \.party) { item in
                            BarMark(
                                x: .value("Female %", item.femaleShare),
                                y: .value("Party", item.party)
                            )
                            .foregroundStyle(genderColor(.female))
                            .annotation(position: .trailing) {
                                Text(String(format: "%.1f%%", item.femaleShare))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .chartXAxis {
                            AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                                AxisGridLine()
                                AxisTick()
                                AxisValueLabel {
                                    if let v = value.as(Double.self) {
                                        Text("\(Int(v))%")
                                    }
                                }
                            }
                        }
                        .chartXScale(domain: 0...100)
                        .chartYAxis { AxisMarks(position: .leading) }
                        .frame(height: CGFloat(data.count) * 34 + 20)
                    }
                }

                // 3. Stacked vertical bar: Events by Party and Gender
                ChartSection(title: "Events by Party and Gender", subtitle: "Absolute humor event counts per party, stacked by gender (top 8)") {
                    let data = vm.genderByParty
                    if data.isEmpty {
                        emptyLabel("No per-party gender data available.")
                    } else {
                        let indexed = Array(data.enumerated())
                        Chart(indexed, id: \.offset) { pair in
                            let item = pair.element
                            BarMark(
                                x: .value("Party", item.party),
                                y: .value("Count", item.count)
                            )
                            .foregroundStyle(by: .value("Gender", item.gender.displayName))
                        }
                        .chartForegroundStyleScale(genderColorScale)
                        .chartLegend(position: .bottom, alignment: .leading)
                        .chartXAxis {
                            AxisMarks { _ in
                                AxisValueLabel()
                            }
                        }
                        .frame(height: 280)
                    }
                }

                // 4. Grouped horizontal bar: Humor Intention by Gender
                ChartSection(title: "Humor Intention by Gender", subtitle: "Do male and female speakers trigger different humor types? (classified events only)") {
                    let data = vm.genderByIntention
                    if data.isEmpty {
                        emptyLabel("No classified gender data. Run Phase 3 to classify humor events first.")
                    } else {
                        let indexed = Array(data.enumerated())
                        Chart(indexed, id: \.offset) { pair in
                            let item = pair.element
                            BarMark(
                                x: .value("Count", item.count),
                                y: .value("Intention", item.intention.rawValue)
                            )
                            .foregroundStyle(by: .value("Gender", item.gender.displayName))
                            .position(by: .value("Gender", item.gender.displayName))
                        }
                        .chartForegroundStyleScale(genderColorScale)
                        .chartLegend(position: .bottom, alignment: .leading)
                        .chartYAxis { AxisMarks(position: .leading) }
                        .frame(height: CGFloat(HumorIntention.allCases.count) * 50 + 20)
                    }
                }

                // 5. Dual line chart: Gender Trends Over Time
                ChartSection(title: "Gender Trends Over Time", subtitle: "Monthly humor event counts by speaker gender · vertical line marks AfD entry (Oct 2017)") {
                    let data = vm.genderTemporalData
                    if data.isEmpty {
                        emptyLabel("No temporal gender data available.")
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
                            ForEach([SpeakerDirectory.Gender.male, .female], id: \.self) { gender in
                                let genderData = data.filter { $0.gender == gender }
                                ForEach(genderData, id: \.month) { item in
                                    LineMark(
                                        x: .value("Month", item.month, unit: .month),
                                        y: .value("Events", item.count)
                                    )
                                    .interpolationMethod(.linear)
                                    .foregroundStyle(genderColor(gender))
                                    .lineStyle(StrokeStyle(lineWidth: 2))
                                }
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
                        .chartForegroundStyleScale(genderColorScale)
                        .chartLegend(position: .bottom, alignment: .leading)
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
}

// MARK: - Shared Components

struct ChartSection<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    exportAsImage()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Export chart as PNG")
            }
            content()
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.06)))
    }

    @MainActor
    private func exportAsImage() {
        let exportView = VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            content()
        }
        .padding()
        .background(Color.white)
        .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: exportView)
        renderer.scale = 8.0

        guard let image = renderer.nsImage else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = title
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
            + ".png"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return }

        try? pngData.write(to: url)
    }
}

private func emptyLabel(_ message: String) -> some View {
    Label(message, systemImage: "exclamationmark.triangle")
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.vertical, 8)
}

// MARK: - Party Normalisation

private func normalizeParty(_ raw: String) -> String {
    let p = raw.trimmingCharacters(in: .whitespaces)
    let upper = p.uppercased()

    if upper == "CDU" || upper == "CSU" || upper == "CDU/CSU" {
        return "CDU/CSU"
    }
    if upper.contains("GRÜN") || upper.contains("BÜNDNIS") || upper.contains("BUNDNIS") {
        return "BÜNDNIS 90/DIE GRÜNEN"
    }
    if upper.contains("LINKE") || upper == "PDS" {
        return "Die Linke"
    }
    if upper == "AFD" {
        return "AfD"
    }
    if upper == "FRAKTIONSLOS" {
        return "Fraktionslos"
    }
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
    case .aggressive:    return .red
    case .social:        return .green
    case .defensive:     return .blue
    case .intellectual:  return .purple
    case .sexual:        return .pink
    case .unclear:       return Color.gray.opacity(0.5)
    }
}

private func genderColor(_ gender: SpeakerDirectory.Gender) -> Color {
    switch gender {
    case .male:   return Color(red: 0.27, green: 0.51, blue: 0.71) // steel blue
    case .female: return Color(red: 0.80, green: 0.36, blue: 0.46) // rose
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
