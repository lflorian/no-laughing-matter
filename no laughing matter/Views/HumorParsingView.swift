//
//  HumorParsingView.swift
//  no laughing matter
//
//  Created by Claude on 20.01.26.
//

import SwiftUI
import SwiftData

struct HumorParsingView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var xmlFiles: [URL] = []
    @State private var humorEvents: [HumorEvent] = []
    @State private var isParsing = false
    @State private var parseProgress: (current: Int, total: Int) = (0, 0)
    @State private var currentFileName: String = ""
    @State private var errorMessage: String?
    @State private var saveSuccess = false
    @State private var parseTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Phase 2: Event Parser")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Parse XML protocols to extract humor markers (Heiterkeit, Lachen) with context.")
                .foregroundStyle(.secondary)

            Divider()

            if isParsing {
                progressView
            } else if !humorEvents.isEmpty {
                resultsView
            } else {
                startView
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            Spacer()
        }
        .padding()
        .frame(minWidth: 600, minHeight: 500)
        .onAppear {
            loadXMLFiles()
            loadCachedEvents()
        }
    }

    // MARK: - Views

    private var startView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if xmlFiles.isEmpty {
                Label("No XML files found. Please download protocols first.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            } else {
                Label("\(xmlFiles.count) XML files available for parsing", systemImage: "doc.text")

                Text("This will extract all humor events from the protocols using RegEx.")
                    .font(.callout)
                    .padding(.top, 8)

                Button("Start Parsing") {
                    parseAllProtocols()
                }
                .buttonStyle(.borderedProminent)
                .padding(.top)
                .disabled(xmlFiles.isEmpty)
            }
        }
    }

    private var progressView: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: Double(parseProgress.current), total: max(Double(parseProgress.total), 1))

            HStack {
                Text("Parsing protocol \(parseProgress.current) of \(parseProgress.total)")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Spacer()

                if parseProgress.total > 0 {
                    let pct = Int(Double(parseProgress.current) / Double(parseProgress.total) * 100)
                    Text("\(pct)%")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if !currentFileName.isEmpty {
                Text(currentFileName)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Text("\(humorEvents.count) humor events found so far")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Button("Cancel") {
                parseTask?.cancel()
                parseTask = nil
                isParsing = false
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
        }
    }

    private var resultsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("\(humorEvents.count) humor events extracted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)

                Spacer()

                Button("Save Results") {
                    saveResults()
                }
                .buttonStyle(.borderedProminent)

                Button("Parse Again") {
                    clearClassifications()
                    humorEvents = []
                    saveSuccess = false
                }
                .buttonStyle(.bordered)
            }

            if saveSuccess {
                Text("Saved to SwiftData")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Statistics
            statisticsView

            Divider()

            // Sample events
            Text("Sample Events:")
                .font(.headline)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(humorEvents.prefix(50)) { event in
                        HumorEventRow(event: event)
                    }
                }
            }
            .frame(maxHeight: 300)
        }
    }

    private var statisticsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Statistics:")
                .font(.headline)

            HStack(spacing: 24) {
                // By type
                VStack(alignment: .leading, spacing: 4) {
                    Text("By Type:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ForEach(HumorType.allCases, id: \.self) { type in
                        let count = humorEvents.filter { $0.humorType == type }.count
                        HStack {
                            Text(type.rawValue)
                                .font(.caption)
                            Spacer()
                            Text("\(count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 120)
                    }
                }

                Divider()

                // Top laughing parties
                VStack(alignment: .leading, spacing: 4) {
                    Text("Top Laughing Parties:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    let partyCounts = countLaughingParties()
                    ForEach(partyCounts.prefix(5), id: \.party) { item in
                        HStack {
                            Text(item.party)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text("\(item.count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 200)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func loadXMLFiles() {
        do {
            let xmlDir = try ProtocolFetcher.shared.getXMLDirectory()
            let contents = try FileManager.default.contentsOfDirectory(
                at: xmlDir,
                includingPropertiesForKeys: nil
            )
            xmlFiles = contents.filter { $0.pathExtension == "xml" }.sorted { $0.path < $1.path }
        } catch {
            // Directory might not exist yet
            xmlFiles = []
        }
    }

    private func loadCachedEvents() {
        if humorEvents.isEmpty {
            do {
                let descriptor = FetchDescriptor<HumorEvent>()
                let cached = try modelContext.fetch(descriptor)
                if !cached.isEmpty {
                    humorEvents = cached
                }
            } catch {
                // No cached events yet
            }
        }
    }

    /// Clears classifications from all stored HumorEvents
    private func clearClassifications() {
        do {
            let descriptor = FetchDescriptor<HumorEvent>()
            let events = try modelContext.fetch(descriptor)
            for event in events {
                event.classification = nil
            }
            try modelContext.save()
        } catch {
            errorMessage = "Failed to clear classifications: \(error.localizedDescription)"
        }
    }

    private func parseAllProtocols() {
        isParsing = true
        errorMessage = nil
        humorEvents = []
        parseProgress = (0, xmlFiles.count)
        currentFileName = ""

        let files = xmlFiles
        parseTask = Task.detached {
            do {
                try await HumorEventParser.shared.parseProtocolsAsync(at: files) { current, total, newEvents in
                    Task { @MainActor in
                        parseProgress = (current, total)
                        currentFileName = files[current - 1].lastPathComponent
                        humorEvents.append(contentsOf: newEvents)
                    }
                }
            } catch {
                let msg = error.localizedDescription
                await MainActor.run {
                    errorMessage = msg
                }
            }

            await MainActor.run {
                isParsing = false
                parseTask = nil
            }
        }
    }

    private func saveResults() {
        do {
            // Delete existing events before inserting new ones
            try modelContext.delete(model: HumorEvent.self)
            for event in humorEvents {
                modelContext.insert(event)
            }
            try modelContext.save()
            saveSuccess = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func countLaughingParties() -> [(party: String, count: Int)] {
        var counts: [String: Int] = [:]
        for event in humorEvents {
            for party in event.laughingParties {
                counts[party, default: 0] += 1
            }
        }
        return counts.map { (party: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }
}

// MARK: - Humor Event Row

struct HumorEventRow: View {
    let event: HumorEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(event.humorType.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(typeColor.opacity(0.2))
                    .foregroundStyle(typeColor)
                    .clipShape(Capsule())

                Text("WP\(event.wahlperiode)/\(event.sitzungsnummer)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                if !event.laughingParties.isEmpty {
                    Text(event.laughingParties.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }

            Text(event.precedingText)
                .font(.callout)
                .lineLimit(2)
                .foregroundStyle(.primary)

            Text("— \(event.speakerName)" + (event.speakerParty.map { " (\($0))" } ?? ""))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var typeColor: Color {
        switch event.humorType {
        case .heiterkeit: return .blue
        case .lachen: return .orange
        }
    }
}

#Preview {
    HumorParsingView()
}
