//
//  ProtocolFetchView.swift
//  no laughing matter
//
//  Created by Claude on 19.01.26.
//

import SwiftUI
import SwiftData

struct ProtocolFetchView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var fetcher = ProtocolFetcher.shared
    @State private var protocols: [ProtocolMetadata] = []
    @State private var errorMessage: String?
    @State private var saveSuccess = false
    @State private var xmlResult: ProtocolFetcher.XMLBatchResult?
    @State private var isDownloadingXML = false

    // Period selection
    private static let availablePeriods = Array(18...21)
    @State private var selectedPeriods: Set<Int> = [19, 20, 21]

    // Date range filtering
    @State private var useDateRange = false
    @State private var startDate = Calendar.current.date(from: DateComponents(year: 2017, month: 10, day: 24))!
    @State private var endDate = Date()

    private var sortedSelectedPeriods: [Int] {
        selectedPeriods.sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Phase 1: Protocol Fetcher")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Fetch plenary protocols from the Bundestag DIP API.")
                .foregroundStyle(.secondary)

            Divider()

            if fetcher.isFetching || isDownloadingXML {
                progressView
            } else if !protocols.isEmpty {
                resultsView
            } else {
                configurationView
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            Spacer()
        }
        .padding()
        .frame(minWidth: 500, minHeight: 400)
        .task {
            loadCachedMetadata()
        }
    }

    private func loadCachedMetadata() {
        if protocols.isEmpty {
            do {
                let descriptor = FetchDescriptor<ProtocolMetadata>()
                let cached = try modelContext.fetch(descriptor)
                if !cached.isEmpty {
                    protocols = cached
                }
            } catch {
                // No cached protocols yet
            }
        }
    }

    private var configurationView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Legislative period selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Legislative Periods")
                    .font(.headline)

                Text("Select which Wahlperioden to fetch protocols from.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(Self.availablePeriods, id: \.self) { period in
                        Toggle(isOn: Binding(
                            get: { selectedPeriods.contains(period) },
                            set: { isOn in
                                if isOn {
                                    selectedPeriods.insert(period)
                                } else {
                                    selectedPeriods.remove(period)
                                }
                            }
                        )) {
                            Text("WP \(period)")
                                .font(.callout)
                                .frame(maxWidth: .infinity)
                        }
                        .toggleStyle(.button)
                        .buttonStyle(.bordered)
                    }
                }

                HStack(spacing: 12) {
                    Button("Select All") {
                        selectedPeriods = Set(Self.availablePeriods)
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)

                    Button("Clear") {
                        selectedPeriods.removeAll()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }

            Divider()

            // Date range filter
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Filter by date range", isOn: $useDateRange)
                    .font(.headline)

                if useDateRange {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("From")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            DatePicker("", selection: $startDate, displayedComponents: .date)
                                .labelsHidden()
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("To")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            DatePicker("", selection: $endDate, displayedComponents: .date)
                                .labelsHidden()
                        }
                    }
                }
            }

            Divider()

            // Summary and fetch button
            if selectedPeriods.isEmpty {
                Text("Select at least one legislative period.")
                    .font(.callout)
                    .foregroundStyle(.orange)
            } else {
                Text("Will fetch protocols from WP \(sortedSelectedPeriods.map(String.init).joined(separator: ", "))\(useDateRange ? " within the selected date range" : "").")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button("Start Fetching") {
                Task {
                    await fetchProtocols()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedPeriods.isEmpty)
        }
    }

    private var progressView: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView()
                .controlSize(.small)

            Text(fetcher.progress.message)
                .font(.callout)
                .foregroundStyle(.secondary)

            if fetcher.progress.totalFound > 0 {
                Text("\(fetcher.progress.fetched) / \(fetcher.progress.totalFound) protocols")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if fetcher.progress.xmlTotal > 0 {
                let completed = fetcher.progress.xmlDownloaded + fetcher.progress.xmlSkipped + fetcher.progress.xmlFailed
                ProgressView(value: Double(completed), total: Double(fetcher.progress.xmlTotal))
                Text("Downloaded: \(fetcher.progress.xmlDownloaded) | Cached: \(fetcher.progress.xmlSkipped) | Failed: \(fetcher.progress.xmlFailed)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var resultsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("\(protocols.count) protocols", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)

                Spacer()

                Button("Save Metadata") {
                    saveMetadata()
                }
                .buttonStyle(.bordered)

                Button("Clear All & Fetch Again") {
                    clearXMLFiles()
                    clearDownstreamData()
                    protocols = []
                    saveSuccess = false
                    xmlResult = nil
                }
                .buttonStyle(.bordered)

                Button("Fetch Again") {
                    clearDownstreamData()
                    protocols = []
                    saveSuccess = false
                    xmlResult = nil
                }
                .buttonStyle(.bordered)
            }

            if saveSuccess {
                Text("Saved to SwiftData")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // XML Download Section
            VStack(alignment: .leading, spacing: 8) {
                Text("XML Files:")
                    .font(.headline)

                let protocolsWithXML = protocols.filter { $0.fundstelle.xml_url != nil }

                if let result = xmlResult {
                    HStack(spacing: 16) {
                        Label("\(result.downloaded) downloaded", systemImage: "arrow.down.circle.fill")
                            .foregroundStyle(.green)
                        Label("\(result.skipped) cached", systemImage: "checkmark.circle")
                            .foregroundStyle(.blue)
                        if result.failed.count > 0 {
                            Label("\(result.failed.count) failed", systemImage: "xmark.circle")
                                .foregroundStyle(.red)
                        }
                    }
                    .font(.callout)
                } else {
                    Text("\(protocolsWithXML.count) protocols have XML available")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Button("Download XML Files") {
                    Task {
                        await downloadXMLFiles()
                    }
                }
                .buttonStyle(.borderedProminent)
            }

            Divider()

            Text("Protocols by Period:")
                .font(.headline)

            ForEach(sortedSelectedPeriods, id: \.self) { period in
                let count = protocols.filter { $0.wahlperiode == period }.count
                HStack {
                    Text("Period \(period):")
                    Text("\(count) protocols")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }

            Divider()

            Text("Recent Protocols:")
                .font(.headline)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(protocols.prefix(20)) { protocol_ in
                        HStack {
                            Text(protocol_.dokumentnummer)
                                .font(.caption.monospaced())
                                .frame(width: 60, alignment: .leading)
                            Text(protocol_.datum)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 80, alignment: .leading)
                            Text(protocol_.titel)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .frame(maxHeight: 200)
        }
    }

    /// Deletes downloaded XML protocol files from disk.
    private func clearXMLFiles() {
        do {
            let xmlDir = try ProtocolFetcher.shared.getXMLDirectory()
            let files = try FileManager.default.contentsOfDirectory(at: xmlDir, includingPropertiesForKeys: nil)
            for file in files where file.pathExtension == "xml" {
                try FileManager.default.removeItem(at: file)
            }
        } catch {
            // Directory might not exist yet — that's fine
        }
    }

    /// Clears downstream SwiftData records: parsed HumorEvents and their classifications.
    private func clearDownstreamData() {
        do {
            try modelContext.delete(model: HumorEvent.self)
            try modelContext.save()
        } catch {
            errorMessage = "Failed to clear downstream data: \(error.localizedDescription)"
        }
    }

    private func fetchProtocols() async {
        errorMessage = nil
        do {
            let dateRange: ProtocolFetcher.DateRange? = useDateRange
                ? ProtocolFetcher.DateRange(start: startDate, end: endDate)
                : nil
            protocols = try await fetcher.fetchProtocols(
                forPeriods: sortedSelectedPeriods,
                dateRange: dateRange
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveMetadata() {
        do {
            // Delete existing metadata before inserting new
            try modelContext.delete(model: ProtocolMetadata.self)
            for proto in protocols {
                modelContext.insert(proto)
            }
            try modelContext.save()
            saveSuccess = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func downloadXMLFiles() async {
        errorMessage = nil
        isDownloadingXML = true
        xmlResult = nil

        let result = await fetcher.downloadAllXMLs(for: protocols)

        isDownloadingXML = false
        xmlResult = result

        if !result.failed.isEmpty {
            errorMessage = "\(result.failed.count) downloads failed"
        }
    }
}

#Preview {
    ProtocolFetchView()
}
