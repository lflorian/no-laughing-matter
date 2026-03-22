//
//  ClassificationView.swift
//  no laughing matter
//
//  Created by Claude on 16.02.26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ClassificationView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var manager = ClassificationManager()
    @Query private var parsedEvents: [HumorEvent]
    @State private var errorMessage: String?
    @State private var saveSuccess = false
    @State private var csvDocument: CSVDocument?
    @State private var showingStatistics = false
    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Phase 3: LLM Classification")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Classify humor intentions using Claude Batch API")
                .foregroundStyle(.secondary)

            if !manager.hasAPIKey {
                Label("No API key configured. Go to Settings (\u{2318},) to add your Claude API key.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            Divider()

            startView

            if manager.hasPendingBatch || manager.isSubmitting {
                batchControlView
            }

            if !manager.classifiedEvents.isEmpty && !manager.isDownloading {
                freshResultsBanner
            }

            if classifiedCount > 0 || !manager.classifiedEvents.isEmpty {
                classifiedEventsListView
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            if classifiedCount == 0 && manager.classifiedEvents.isEmpty {
                Spacer()
            }
        }
        .padding()
        .frame(minWidth: 600, minHeight: 500)
        .navigationTitle("LLM Classifier")
        .fileExporter(
            isPresented: Binding(
                get: { csvDocument != nil },
                set: { if !$0 { csvDocument = nil } }
            ),
            document: csvDocument ?? CSVDocument(csv: ""),
            contentType: .commaSeparatedText,
            defaultFilename: "classifications_\(formattedTimestamp).csv"
        ) { result in
            if case .failure(let error) = result {
                errorMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    private var formattedTimestamp: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmm"
        return f.string(from: Date())
    }

    // MARK: - Start View

    private var unclassifiedEvents: [HumorEvent] {
        parsedEvents.filter { $0.classification == nil }
    }

    private var classifiedCount: Int {
        parsedEvents.count - unclassifiedEvents.count
    }

    private var startView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if parsedEvents.isEmpty {
                Label("No parsed events found. Please run the Event Parser first.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            } else {
                Label("\(parsedEvents.count) humor events loaded", systemImage: "doc.text")

                if classifiedCount > 0 {
                    Label("\(classifiedCount) already classified, \(unclassifiedEvents.count) remaining", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Confidence threshold:")
                            .font(.callout)
                        Text("\(manager.confidenceThreshold)")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(manager.confidenceThreshold) },
                            set: { manager.confidenceThreshold = Int($0) }
                        ),
                        in: 1...10,
                        step: 1
                    )
                    .frame(width: 200)
                    Text("Events rated below this threshold will be flagged as low confidence.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 8)

                HStack(spacing: 12) {
                    Button("Submit Batch (\(unclassifiedEvents.count) Events)") {
                        Task {
                            await manager.submitBatch(unclassifiedEvents)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!manager.hasAPIKey || unclassifiedEvents.isEmpty || manager.isSubmitting || manager.hasPendingBatch)

                    if classifiedCount > 0 {
                        Button("Clear All Classifications") {
                            clearAllClassifications()
                        }
                        .buttonStyle(.bordered)
                        .foregroundStyle(.red)
                    }
                }
                .padding(.top)
            }
        }
    }

    // MARK: - Batch Control View

    private var batchControlView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            // Batch ID
            if let batchId = manager.batchId {
                HStack {
                    Label("Batch", systemImage: "tray.full")
                        .font(.headline)
                    Text(batchId)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            // Status display
            if let status = manager.batchStatus {
                let counts = status.requestCounts
                HStack(spacing: 16) {
                    Label("\(counts.succeeded) succeeded", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                    if counts.errored > 0 {
                        Label("\(counts.errored) errored", systemImage: "xmark.circle")
                            .foregroundStyle(.red)
                    }
                    if counts.expired > 0 {
                        Label("\(counts.expired) expired", systemImage: "clock.badge.exclamationmark")
                            .foregroundStyle(.orange)
                    }
                    if counts.processing > 0 {
                        Label("\(counts.processing) processing", systemImage: "clock")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.callout)

                if status.processingStatus == "ended" {
                    ProgressView(value: 1.0)
                        .tint(.green)
                } else {
                    let done = Double(counts.succeeded + counts.errored + counts.canceled + counts.expired)
                    let all = done + Double(counts.processing)
                    ProgressView(value: all > 0 ? done / all : 0)
                }
            }

            if manager.isSubmitting {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Submitting batch...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if let msg = manager.statusMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Action buttons
            HStack(spacing: 12) {
                Button {
                    Task { await manager.checkStatus() }
                } label: {
                    Label("Check Status", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(manager.batchId == nil || manager.isSubmitting)

                if manager.isReadyForDownload {
                    Button {
                        Task { await manager.downloadResults(for: Array(unclassifiedEvents)) }
                    } label: {
                        Label("Download Results", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(manager.isDownloading)
                }

                if manager.batchStatus?.processingStatus != "ended" && !manager.isSubmitting {
                    Button {
                        Task { await manager.cancelBatch() }
                    } label: {
                        Label("Cancel Batch", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
                }

                Spacer()

                Button("Dismiss") {
                    manager.clearBatch()
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.secondary)
            }
            .padding(.top, 4)

            Text("Batches typically complete within 1 hour. You can close the app and check back later.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Fresh Results Banner (after downloading)

    private var freshResultsBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack {
                Label("\(manager.succeeded) classified", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)

                if manager.errored > 0 {
                    Text("(\(manager.errored) errors)")
                        .font(.callout)
                        .foregroundStyle(.red)
                }

                Spacer()

                Button("Save Results") {
                    saveResults()
                }
                .buttonStyle(.borderedProminent)

                Button("Dismiss") {
                    manager.classifiedEvents = []
                    manager.errors = []
                    saveSuccess = false
                }
                .buttonStyle(.bordered)
            }

            if saveSuccess {
                Text("Saved to SwiftData")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Classified Events List (from SwiftData)

    private var allClassifiedEvents: [HumorEvent] {
        parsedEvents.filter { $0.classification != nil }
    }

    private var filteredClassifiedEvents: [HumorEvent] {
        guard !searchText.isEmpty else { return allClassifiedEvents }
        return allClassifiedEvents.filter { event in
            event.speakerName.localizedStandardContains(searchText)
            || (event.speakerParty?.localizedStandardContains(searchText) ?? false)
            || event.rawComment.localizedStandardContains(searchText)
            || event.precedingText.localizedStandardContains(searchText)
            || (event.classification?.primaryIntention.rawValue.localizedStandardContains(searchText) ?? false)
            || (event.classification?.secondaryIntention?.rawValue.localizedStandardContains(searchText) ?? false)
            || event.laughingParties.joined(separator: " ").localizedStandardContains(searchText)
        }
    }

    private var classifiedEventsListView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            HStack {
                Text("Classified Events (\(allClassifiedEvents.count))")
                    .font(.headline)

                Spacer()

                Button {
                    showingStatistics.toggle()
                } label: {
                    Label("Statistics", systemImage: "chart.pie")
                }
                .buttonStyle(.bordered)
                .popover(isPresented: $showingStatistics) {
                    classificationStatisticsView
                        .padding()
                        .frame(minWidth: 400)
                }

                Button("Export CSV") {
                    csvDocument = CSVDocument(csv: buildCSVExport())
                }
                .buttonStyle(.bordered)
            }

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search by speaker, party, intention, comment...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            if !searchText.isEmpty {
                Text("\(filteredClassifiedEvents.count) results")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(filteredClassifiedEvents) { event in
                        ClassifiedEventRow(event: event, confidenceThreshold: manager.confidenceThreshold)
                    }
                }
            }
        }
    }

    // MARK: - Statistics

    private var classificationStatisticsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Classification Statistics:")
                .font(.headline)

            HStack(spacing: 24) {
                // By intention
                VStack(alignment: .leading, spacing: 4) {
                    Text("By Intention:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ForEach(HumorIntention.allCases, id: \.self) { intention in
                        let count = allClassifiedEvents.filter {
                            $0.classification?.primaryIntention == intention
                        }.count
                        if count > 0 {
                            HStack {
                                Text(intention.rawValue)
                                    .font(.caption)
                                Spacer()
                                Text("\(count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 160)
                        }
                    }
                }

                Divider()

                // Confidence split
                VStack(alignment: .leading, spacing: 4) {
                    Text("Confidence:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text("High (\u{2265}\(manager.confidenceThreshold))")
                            .font(.caption)
                        Spacer()
                        Text("\(allClassifiedEvents.filter { ($0.classification?.confidenceRating ?? 0) >= manager.confidenceThreshold }.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.green)
                    }
                    .frame(width: 120)

                    HStack {
                        Text("Low (<\(manager.confidenceThreshold))")
                            .font(.caption)
                        Spacer()
                        Text("\(allClassifiedEvents.filter { ($0.classification?.confidenceRating ?? 0) < manager.confidenceThreshold }.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.orange)
                    }
                    .frame(width: 120)

                    HStack {
                        Text("Unclassified")
                            .font(.caption)
                        Spacer()
                        Text("\(unclassifiedEvents.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.red)
                    }
                    .frame(width: 120)
                }

                Divider()

                // Errors
                VStack(alignment: .leading, spacing: 4) {
                    Text("Processing:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text("Total")
                            .font(.caption)
                        Spacer()
                        Text("\(allClassifiedEvents.count)")
                            .font(.caption.monospacedDigit())
                    }
                    .frame(width: 100)

                    HStack {
                        Text("Errors")
                            .font(.caption)
                        Spacer()
                        Text("\(manager.errors.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(manager.errors.isEmpty ? Color.secondary : Color.red)
                    }
                    .frame(width: 100)
                }
            }
        }
    }

    // MARK: - Actions

    private func clearAllClassifications() {
        for event in parsedEvents {
            event.classification = nil
        }
        do {
            try modelContext.save()
            manager.classifiedEvents = []
            manager.errors = []
            saveSuccess = false
        } catch {
            errorMessage = "Failed to clear classifications: \(error.localizedDescription)"
        }
    }

    private func buildCSVExport() -> String {
        let events = allClassifiedEvents
        var csv = "wahlperiode,sitzungsnummer,datum,speaker_name,speaker_party,speaker_role,humor_type,raw_comment,laughing_parties,primary_intention,secondary_intention,confidence,reasoning\n"

        for event in events {
            let fields: [String] = [
                "\(event.wahlperiode)",
                "\(event.sitzungsnummer)",
                csvEscape(event.datum),
                csvEscape(event.speakerName),
                csvEscape(event.speakerParty ?? ""),
                csvEscape(event.speakerRole ?? ""),
                csvEscape(event.humorType.rawValue),
                csvEscape(event.rawComment),
                csvEscape(event.laughingParties.joined(separator: "; ")),
                csvEscape(event.classification?.primaryIntention.rawValue ?? "unclassified"),
                csvEscape(event.classification?.secondaryIntention?.rawValue ?? ""),
                "\(event.classification?.confidenceRating ?? 0)",
                csvEscape(event.classification?.reasoning ?? "")
            ]
            csv += fields.joined(separator: ",") + "\n"
        }
        return csv
    }

    private func csvEscape(_ value: String) -> String {
        let needsQuoting = value.contains(",") || value.contains("\"") || value.contains("\n")
        if needsQuoting {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    private func saveResults() {
        do {
            try modelContext.save()
            saveSuccess = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Classified Event Row

struct ClassifiedEventRow: View {
    let event: HumorEvent
    let confidenceThreshold: Int
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(event.humorType.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(humorTypeColor.opacity(0.2))
                    .foregroundStyle(humorTypeColor)
                    .clipShape(Capsule())

                if let classification = event.classification {
                    Text(classification.primaryIntention.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(intentionColor(classification.primaryIntention).opacity(0.2))
                        .foregroundStyle(intentionColor(classification.primaryIntention))
                        .clipShape(Capsule())

                    if let secondary = classification.secondaryIntention {
                        Text(secondary.rawValue)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(intentionColor(secondary).opacity(0.1))
                            .foregroundStyle(intentionColor(secondary))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().strokeBorder(intentionColor(secondary).opacity(0.3), lineWidth: 1)
                            )
                    }

                    confidenceIndicator(classification.confidenceRating)
                } else {
                    Text("unclassified")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.gray.opacity(0.2))
                        .foregroundStyle(.gray)
                        .clipShape(Capsule())
                }

                Text("WP\(event.wahlperiode)/\(event.sitzungsnummer)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text(event.precedingText)
                .font(.callout)
                .lineLimit(isExpanded ? nil : 2)
                .foregroundStyle(.primary)

            Text("— \(event.speakerName)" + (event.speakerParty.map { " (\($0))" } ?? ""))
                .font(.caption)
                .foregroundStyle(.tertiary)

            if isExpanded, let classification = event.classification {
                VStack(alignment: .leading, spacing: 4) {
                    Divider()

                    Text(classification.reasoning ?? "Reasoning unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()

                    Text("Raw comment: \(event.rawComment)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    if !event.laughingParties.isEmpty {
                        Text("Laughing parties: \(event.laughingParties.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }

    private func confidenceIndicator(_ rating: Int) -> some View {
        HStack(spacing: 2) {
            Image(systemName: rating >= confidenceThreshold ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.caption2)
            Text("\(rating)/10")
                .font(.caption.monospacedDigit())
        }
        .foregroundStyle(rating >= confidenceThreshold ? .green : .orange)
    }

    private var humorTypeColor: Color {
        switch event.humorType {
        case .heiterkeit: return .blue
        case .lachen: return .orange
        }
    }

    private func intentionColor(_ intention: HumorIntention) -> Color {
        switch intention {
        case .aggressive:    return .red
        case .social:        return .green
        case .defensive:     return .blue
        case .intellectual:  return .purple
        case .sexual:        return .pink
        case .unclear:       return .secondary
        }
    }
}

#Preview {
    ClassificationView()
}
