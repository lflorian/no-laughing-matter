//
//  ClassificationManager.swift
//  no laughing matter
//
//  Created by Claude on 16.02.26.
//

import Foundation
import FoundationModels
import Observation

@Observable
final class ClassificationManager {

    var isClassifying = false
    var isPaused = false
    var completed = 0
    var total = 0
    var errors: [(index: Int, message: String)] = []
    var classifiedEvents: [HumorEvent] = []
    var confidenceThreshold = 4

    // ETA tracking
    private(set) var startTime: Date?
    private(set) var averageSecondsPerEvent: Double?

    private var isCancelled = false
    private var pauseContinuation: CheckedContinuation<Void, Never>?

    var highConfidenceEvents: [HumorEvent] {
        classifiedEvents.filter { ($0.classification?.confidenceRating ?? 0) >= confidenceThreshold }
    }

    var lowConfidenceEvents: [HumorEvent] {
        classifiedEvents.filter { ($0.classification?.confidenceRating ?? 0) < confidenceThreshold }
    }

    var estimatedSecondsRemaining: Double? {
        guard let avg = averageSecondsPerEvent, completed > 0 else { return nil }
        return avg * Double(total - completed)
    }

    var formattedETA: String? {
        guard let seconds = estimatedSecondsRemaining else { return nil }
        if seconds < 60 { return "<1 min remaining" }
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m remaining"
        }
        return "\(minutes)m \(secs)s remaining"
    }

    func classifyEvents(_ events: [HumorEvent]) async {
        isClassifying = true
        isPaused = false
        isCancelled = false
        completed = 0
        total = events.count
        errors = []
        classifiedEvents = []
        startTime = Date()
        averageSecondsPerEvent = nil

        // Single session reused for all events — avoids per-call session creation overhead
        let session = IntelligenceManager.shared.createBatchSession()

        for (index, event) in events.enumerated() {
            if isCancelled { break }

            if isPaused {
                await withCheckedContinuation { continuation in
                    pauseContinuation = continuation
                }
                pauseContinuation = nil
                if isCancelled { break }
            }

            do {
                let classification = try await IntelligenceManager.shared.analyzeEvent(event, using: session)
                var classifiedEvent = event
                classifiedEvent.classification = classification
                classifiedEvents.append(classifiedEvent)
            } catch {
                errors.append((index: index, message: "\(event.speakerName): \(error.localizedDescription)"))
                classifiedEvents.append(event)
            }

            completed = index + 1
            updateAverageTime()
        }

        isClassifying = false
    }

    func pause() {
        isPaused = true
    }

    func resume() {
        isPaused = false
        pauseContinuation?.resume()
    }

    func cancel() {
        isCancelled = true
        isPaused = false
        pauseContinuation?.resume()
    }

    private func updateAverageTime() {
        guard let start = startTime, completed > 0 else { return }
        averageSecondsPerEvent = Date().timeIntervalSince(start) / Double(completed)
    }
}
