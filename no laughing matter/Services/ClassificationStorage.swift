//
//  ClassificationStorage.swift
//  no laughing matter
//
//  Created by Claude on 16.02.26.
//

import Foundation

final class ClassificationStorage {
    static let shared = ClassificationStorage()

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
        let fileURL = storageDir.appendingPathComponent("classified_events.json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(events)
        try data.write(to: fileURL)

        return fileURL
    }

    func loadEvents() throws -> [HumorEvent]? {
        let storageDir = try getStorageDirectory()
        let fileURL = storageDir.appendingPathComponent("classified_events.json")

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([HumorEvent].self, from: data)
    }
}
