//
//  ClassificationManager.swift
//  no laughing matter
//
//  Created by Claude on 16.02.26.
//

import Foundation
import Observation

@MainActor @Observable
final class ClassificationManager {

    // MARK: - State

    var isSubmitting = false
    var isDownloading = false
    var completed = 0
    var total = 0
    var succeeded = 0
    var errored = 0
    var errors: [(index: Int, message: String)] = []
    var classifiedEvents: [HumorEvent] = []
    var confidenceThreshold = 4

    // Batch tracking
    var batchId: String? {
        didSet { persistBatchId() }
    }
    var batchStatus: BatchStatus?
    var statusMessage: String?

    var hasAPIKey: Bool {
        APIKeyManager.load() != nil
    }

    /// Whether a batch is active (submitted but not yet downloaded)
    var hasPendingBatch: Bool {
        batchId != nil
    }

    /// Whether the batch has finished and results are ready
    var isReadyForDownload: Bool {
        batchStatus?.processingStatus == "ended" && batchStatus?.resultsUrl != nil
    }

    var highConfidenceEvents: [HumorEvent] {
        classifiedEvents.filter { ($0.classification?.confidenceRating ?? 0) >= confidenceThreshold }
    }

    var lowConfidenceEvents: [HumorEvent] {
        classifiedEvents.filter { ($0.classification?.confidenceRating ?? 0) < confidenceThreshold }
    }

    // MARK: - Init

    init() {
        // Restore batch ID from previous session
        if let saved = UserDefaults.standard.string(forKey: "pendingBatchId") {
            batchId = saved
        }
    }

    // MARK: - Step 1: Submit Batch

    func submitBatch(_ events: [HumorEvent]) async {
        isSubmitting = true
        total = events.count
        succeeded = 0
        errored = 0
        errors = []
        classifiedEvents = []
        statusMessage = "Building batch request..."

        let manager = IntelligenceManager.shared
        let client = manager.client

        // Build batch requests
        var batchRequests: [[String: Any]] = []
        for (index, event) in events.enumerated() {
            let prompt = manager.buildPrompt(for: event)
            let req = await client.buildBatchRequest(
                customId: "event-\(index)",
                system: manager.instructions,
                user: prompt
            )
            batchRequests.append(req)
        }

        statusMessage = "Submitting \(events.count) events as batch..."

        do {
            let status = try await client.createBatch(requests: batchRequests)
            batchId = status.id
            batchStatus = status
            statusMessage = "Batch submitted: \(status.id). Use 'Check Status' to monitor progress."
        } catch {
            statusMessage = "Failed to create batch: \(error.localizedDescription)"
        }

        isSubmitting = false
    }

    // MARK: - Step 2: Check Status (manual)

    func checkStatus() async {
        guard let id = batchId else {
            statusMessage = "No batch ID."
            return
        }

        statusMessage = "Checking batch status..."

        do {
            let status = try await IntelligenceManager.shared.client.retrieveBatch(id: id)
            batchStatus = status
            let counts = status.requestCounts
            completed = counts.succeeded + counts.errored + counts.canceled + counts.expired

            if status.processingStatus == "ended" {
                statusMessage = "Batch complete — \(counts.succeeded) succeeded, \(counts.errored) errored, \(counts.expired) expired. Ready to download."
            } else {
                statusMessage = "Processing: \(counts.succeeded) done, \(counts.processing) in progress, \(counts.errored) errored."
            }
        } catch {
            statusMessage = "Failed to check status: \(error.localizedDescription)"
        }
    }

    // MARK: - Step 3: Download Results

    func downloadResults(for events: [HumorEvent]) async {
        guard let resultsUrl = batchStatus?.resultsUrl else {
            statusMessage = "No results URL available."
            return
        }

        isDownloading = true
        statusMessage = "Downloading results..."
        classifiedEvents = []
        errors = []
        succeeded = 0
        errored = 0

        do {
            let results = try await IntelligenceManager.shared.client.fetchBatchResults(resultsURL: resultsUrl)

            for result in results {
                // Parse index from custom_id "event-42"
                guard let indexStr = result.customId.split(separator: "-").last,
                      let index = Int(indexStr),
                      index < events.count else {
                    print("⚠️ Unknown custom_id in batch result: \(result.customId)")
                    errors.append((index: -1, message: "Unknown custom_id: \(result.customId)"))
                    errored += 1
                    continue
                }

                let event = events[index]

                if result.result.type == "succeeded", let classification = result.classification() {
                    event.classification = classification
                    succeeded += 1
                } else {
                    let reason: String
                    switch result.result.type {
                    case "succeeded": reason = "Failed to parse classification from response"
                    case "errored": reason = "API error"
                    case "expired": reason = "Request expired (24h limit)"
                    case "canceled": reason = "Request was cancelled"
                    default: reason = result.result.type
                    }
                    print("⚠️ Batch result [\(index)] \(event.speakerName): \(reason)")
                    errors.append((index: index, message: "\(event.speakerName): \(reason)"))
                    errored += 1
                }

                classifiedEvents.append(event)
            }

            completed = results.count
            total = events.count
            statusMessage = "Downloaded — \(succeeded) classified, \(errored) errors."

            // Clear the pending batch since we've consumed the results
            batchId = nil
            batchStatus = nil
        } catch {
            statusMessage = "Failed to download results: \(error.localizedDescription)"
        }

        isDownloading = false
    }

    // MARK: - Cancel

    func cancelBatch() async {
        guard let id = batchId else { return }

        statusMessage = "Cancelling batch..."
        do {
            try await IntelligenceManager.shared.client.cancelBatch(id: id)
            statusMessage = "Cancel requested. Already-processed requests will still have results."
            // Don't clear batchId yet — user may still want to download partial results
            await checkStatus()
        } catch {
            statusMessage = "Failed to cancel: \(error.localizedDescription)"
        }
    }

    // MARK: - Lookup Batch by ID

    func lookupBatch(id: String) async {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusMessage = "Please enter a batch ID."
            return
        }
        batchId = trimmed
        await checkStatus()
    }

    // MARK: - Clear

    func clearBatch() {
        batchId = nil
        batchStatus = nil
        statusMessage = nil
        completed = 0
        total = 0
        succeeded = 0
        errored = 0
        errors = []
        classifiedEvents = []
    }

    // MARK: - Persistence

    private func persistBatchId() {
        if let batchId {
            UserDefaults.standard.set(batchId, forKey: "pendingBatchId")
        } else {
            UserDefaults.standard.removeObject(forKey: "pendingBatchId")
        }
    }
}
