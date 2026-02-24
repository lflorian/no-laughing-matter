//
//  HumorParsingView.swift
//  no laughing matter
//
//  Created by Claude on 20.01.26.
//

import SwiftUI

struct HumorParsingView: View {
    @State private var xmlFiles: [URL] = []
    @State private var humorEvents: [HumorEvent] = []
    @State private var isParsing = false
    @State private var parseProgress: (current: Int, total: Int) = (0, 0)
    @State private var errorMessage: String?
    @State private var savedLocation: URL?

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

                Text("This will extract all humor events from the protocols, including:")
                    .font(.callout)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 4) {
                    Label("Heiterkeit (amusement)", systemImage: "face.smiling")
                    Label("Lachen (laughing)", systemImage: "face.smiling.inverse")
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                Button("Start Parsing") {
                    Task {
                        await parseAllProtocols()
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding(.top)
                .disabled(xmlFiles.isEmpty)
            }
        }
    }

    private var progressView: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: Double(parseProgress.current), total: Double(parseProgress.total))

            Text("Parsing protocol \(parseProgress.current) of \(parseProgress.total)...")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("\(humorEvents.count) humor events found so far")
                .font(.caption)
                .foregroundStyle(.tertiary)
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
                    humorEvents = []
                    savedLocation = nil
                }
                .buttonStyle(.bordered)
            }

            if let savedLocation {
                Text("Saved to: \(savedLocation.path)")
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
            if let cached = try? HumorEventStorage.shared.loadEvents() {
                humorEvents = cached
            }
        }
    }

    private func parseAllProtocols() async {
        isParsing = true
        errorMessage = nil
        humorEvents = []
        parseProgress = (0, xmlFiles.count)

        do {
            let files = xmlFiles
            let results = try await Task.detached {
                try HumorEventParser.shared.parseProtocols(at: files) { current, total in
                    Task { @MainActor in
                        self.parseProgress = (current, total)
                    }
                }
            }.value
            humorEvents = results
        } catch {
            errorMessage = error.localizedDescription
        }

        isParsing = false
    }

    private func saveResults() {
        do {
            savedLocation = try HumorEventStorage.shared.saveEvents(humorEvents)
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

// MARK: - Storage

final class HumorEventStorage {
    static let shared = HumorEventStorage()

    private init() {}

    private func getStorageDirectory() throws -> URL {
        let fileManager = FileManager.default
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let storageDir = appSupport
            .appendingPathComponent("NoLaughingMatter")
            .appendingPathComponent("ParsedData")

        if !fileManager.fileExists(atPath: storageDir.path) {
            try fileManager.createDirectory(at: storageDir, withIntermediateDirectories: true)
        }

        return storageDir
    }

    func saveEvents(_ events: [HumorEvent]) throws -> URL {
        let storageDir = try getStorageDirectory()
        let fileURL = storageDir.appendingPathComponent("humor_events.json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(events)
        try data.write(to: fileURL)

        return fileURL
    }

    func loadEvents() throws -> [HumorEvent]? {
        let storageDir = try getStorageDirectory()
        let fileURL = storageDir.appendingPathComponent("humor_events.json")

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([HumorEvent].self, from: data)
    }
}

#Preview {
    HumorParsingView()
}
