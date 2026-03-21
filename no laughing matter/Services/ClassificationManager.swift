//
//  ClassificationManager.swift
//  no laughing matter
//
//  Created by Claude on 16.02.26.
//

import Foundation
import Observation

/// Actor-based semaphore for limiting concurrency
private actor ConcurrencySemaphore {
    private let limit: Int
    private var current = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = limit
    }

    func wait() async {
        if current < limit {
            current += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        } else {
            current -= 1
        }
    }
}

@Observable
final class ClassificationManager {

    var isClassifying = false
    var isPaused = false
    var completed = 0
    var total = 0
    var errors: [(index: Int, message: String)] = []
    var classifiedEvents: [HumorEvent] = []
    var confidenceThreshold = 4
    var maxConcurrency = 16

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
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m remaining"
        }
        let secs = Int(seconds) % 60
        return "\(minutes)m \(secs)s remaining"
    }

    var hasAPIKey: Bool {
        APIKeyManager.load() != nil
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

        let semaphore = ConcurrencySemaphore(limit: maxConcurrency)
        let manager = IntelligenceManager.shared

        await withTaskGroup(of: (Int, HumorEvent, LLMClassification?, String?).self) { group in
            for (index, event) in events.enumerated() {
                // Wait for a semaphore slot — this is where backpressure happens
                await semaphore.wait()

                if isCancelled {
                    await semaphore.signal()
                    break
                }

                // Check pause between dispatching tasks
                if isPaused {
                    await withCheckedContinuation { continuation in
                        pauseContinuation = continuation
                    }
                    pauseContinuation = nil
                    if isCancelled {
                        await semaphore.signal()
                        break
                    }
                }

                group.addTask {
                    defer { Task { await semaphore.signal() } }

                    // Check cancellation before making the API call
                    guard !Task.isCancelled else {
                        return (index, event, nil, "Cancelled")
                    }

                    do {
                        let classification = try await manager.analyzeEvent(event)
                        return (index, event, classification, nil)
                    } catch {
                        print("❌ Classification error [\(index)] \(event.speakerName): \(error)")
                        return (index, event, nil, "\(event.speakerName): \(error.localizedDescription)")
                    }
                }
            }

            // Process results as they complete
            for await (index, event, classification, errorMessage) in group {
                if isCancelled { break }

                if let classification {
                    event.classification = classification
                }
                classifiedEvents.append(event)

                if let errorMessage, errorMessage != "Cancelled" {
                    errors.append((index: index, message: errorMessage))
                }

                completed += 1
                updateAverageTime()
            }

            if isCancelled {
                group.cancelAll()
            }
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
