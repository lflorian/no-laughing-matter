//
//  ClassificationView.swift
//  no laughing matter
//
//  Created by Claude on 16.02.26.
//

import SwiftUI

struct ClassificationView: View {
    @State private var manager = ClassificationManager()
    @State private var parsedEvents: [HumorEvent] = []
    @State private var errorMessage: String?
    @State private var savedLocation: URL?
    @State private var classificationTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Phase 2: LLM Classification")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Classify humor intentions using on-device language model analysis.")
                .foregroundStyle(.secondary)

            Divider()

            if manager.isClassifying {
                progressView
            } else if !manager.classifiedEvents.isEmpty {
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
            loadParsedEvents()
        }
        .navigationTitle("LLM Classifier")
    }

    // MARK: - Start View

    private var startView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if parsedEvents.isEmpty {
                Label("No parsed events found. Please run the Event Parser first.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            } else {
                Label("\(parsedEvents.count) humor events available for classification", systemImage: "doc.text")

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

                Button("Start Classification") {
                    startClassification()
                }
                .buttonStyle(.borderedProminent)
                .padding(.top)
            }

            Button("Reload Parsed Events") {
                loadParsedEvents()
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Progress View

    private var progressView: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: Double(manager.completed), total: Double(manager.total))

            HStack {
                Text("Classifying event \(manager.completed) of \(manager.total)...")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Spacer()

                if let eta = manager.formattedETA {
                    Text(eta)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                if !manager.errors.isEmpty {
                    Text("\(manager.errors.count) errors")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            if let avg = manager.averageSecondsPerEvent {
                Text(String(format: "%.1fs/event", avg))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 12) {
                if manager.isPaused {
                    Button("Resume") {
                        manager.resume()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Pause") {
                        manager.pause()
                    }
                    .buttonStyle(.bordered)
                }

                Button("Cancel") {
                    manager.cancel()
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.red)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Results View

    private var resultsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("\(manager.classifiedEvents.count) events classified", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)

                Spacer()

                Button("Save Results") {
                    saveResults()
                }
                .buttonStyle(.borderedProminent)

                Button("Classify Again") {
                    manager.classifiedEvents = []
                    manager.errors = []
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
            classificationStatisticsView

            Divider()

            // Results list
            Text("Classified Events:")
                .font(.headline)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(manager.classifiedEvents) { event in
                        ClassifiedEventRow(event: event, confidenceThreshold: manager.confidenceThreshold)
                    }
                }
            }
            .frame(maxHeight: 400)
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
                        let count = manager.classifiedEvents.filter {
                            $0.classification?.humorIntention == intention
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
                        Text("\(manager.highConfidenceEvents.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.green)
                    }
                    .frame(width: 120)

                    HStack {
                        Text("Low (<\(manager.confidenceThreshold))")
                            .font(.caption)
                        Spacer()
                        Text("\(manager.lowConfidenceEvents.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.orange)
                    }
                    .frame(width: 120)

                    HStack {
                        Text("Unclassified")
                            .font(.caption)
                        Spacer()
                        Text("\(manager.classifiedEvents.filter { $0.classification == nil }.count)")
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
                        Text("\(manager.classifiedEvents.count)")
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

    private func loadParsedEvents() {
        do {
            if let events = try HumorEventStorage.shared.loadEvents() {
                parsedEvents = events
            }
        } catch {
            errorMessage = "Failed to load parsed events: \(error.localizedDescription)"
        }
    }

    private func startClassification() {
        errorMessage = nil
        savedLocation = nil
        classificationTask = Task {
            await manager.classifyEvents(parsedEvents)
        }
    }

    private func saveResults() {
        do {
            savedLocation = try ClassificationStorage.shared.saveEvents(manager.classifiedEvents)
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
                // Humor type badge
                Text(event.humorType.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(humorTypeColor.opacity(0.2))
                    .foregroundStyle(humorTypeColor)
                    .clipShape(Capsule())

                // Intention badge
                if let classification = event.classification {
                    Text(classification.humorIntention.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(intentionColor(classification.humorIntention).opacity(0.2))
                        .foregroundStyle(intentionColor(classification.humorIntention))
                        .clipShape(Capsule())

                    // Confidence indicator
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

                    Text("Reasoning: \(classification.reasoning)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

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
        case .irony: return .purple
        case .ridicule: return .red
        case .distance: return .orange
        case .solidarity: return .green
        case .strategic_disruption: return .red
        case .tension_relief: return .blue
        case .self_affirmation: return .teal
        case .accidental: return .gray
        case .unclear: return .secondary
        }
    }
}

#Preview {
    ClassificationView()
}
