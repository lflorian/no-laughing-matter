//
//  ProtocolFetcher.swift
//  no laughing matter
//
//  Created by Claude on 19.01.26.
//

import Foundation
import Combine
import SwiftData

/// Service for fetching Bundestag plenary protocols from the DIP API
final class ProtocolFetcher: ObservableObject {

    static let shared = ProtocolFetcher()

    private let baseURL = "https://search.dip.bundestag.de/api/v1"
    private let apiKey = "OSOegLs.PR2lwJ1dwCeje9vTj7FPOt3hvpYKtwKkhw"
    private let session = URLSession.shared

    @Published var isFetching = false
    @Published var progress: FetchProgress = FetchProgress()

    private init() {}

    struct FetchProgress {
        var totalFound: Int = 0
        var fetched: Int = 0
        var currentPeriod: Int = 0
        var message: String = ""

        // For XML downloads
        var xmlTotal: Int = 0
        var xmlDownloaded: Int = 0
        var xmlSkipped: Int = 0
        var xmlFailed: Int = 0
    }

    struct DateRange {
        let start: Date
        let end: Date

        private static let formatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return f
        }()

        var startString: String { Self.formatter.string(from: start) }
        var endString: String { Self.formatter.string(from: end) }
    }

    /// Fetches all protocols for the given legislative periods, optionally filtered by date range
    func fetchProtocols(forPeriods periods: [Int], dateRange: DateRange? = nil) async throws -> [ProtocolMetadata] {
        await MainActor.run {
            isFetching = true
            progress = FetchProgress()
        }

        defer {
            Task { @MainActor in
                isFetching = false
            }
        }

        var allProtocols: [ProtocolMetadata] = []

        for period in periods {
            await MainActor.run {
                progress.currentPeriod = period
                progress.message = "Fetching period \(period)..."
            }

            let protocols = try await fetchProtocolsForPeriod(period, dateRange: dateRange)
            allProtocols.append(contentsOf: protocols)
        }

        await MainActor.run {
            progress.message = "Done! Fetched \(allProtocols.count) protocols."
        }

        return allProtocols
    }

    /// Fetches protocols for a single legislative period, handling pagination
    private func fetchProtocolsForPeriod(_ period: Int, dateRange: DateRange? = nil) async throws -> [ProtocolMetadata] {
        var protocols: [ProtocolMetadata] = []
        var cursor: String? = nil

        repeat {
            let response = try await fetchPage(period: period, cursor: cursor, dateRange: dateRange)

            await MainActor.run {
                if progress.totalFound == 0 {
                    progress.totalFound = response.numFound
                }
                progress.fetched += response.documents.count
                progress.message = "Period \(period): \(protocols.count + response.documents.count) protocols..."
            }

            // Convert API documents to ProtocolMetadata model objects
            let newProtocols = response.documents.map { doc in
                ProtocolMetadata(
                    apiId: doc.id,
                    dokumentart: doc.dokumentart,
                    dokumentnummer: doc.dokumentnummer,
                    wahlperiode: doc.wahlperiode,
                    herausgeber: doc.herausgeber,
                    datum: doc.datum,
                    aktualisiert: doc.aktualisiert,
                    titel: doc.titel,
                    fundstelle: doc.fundstelle
                )
            }
            protocols.append(contentsOf: newProtocols)

            // Check if we've reached the end (cursor stops changing)
            if cursor == response.cursor {
                break
            }
            cursor = response.cursor

        } while cursor != nil

        return protocols
    }

    /// Fetches a single page of results
    private func fetchPage(period: Int, cursor: String?, dateRange: DateRange? = nil) async throws -> APIResponse {
        var components = URLComponents(string: "\(baseURL)/plenarprotokoll")!
        var queryItems = [
            URLQueryItem(name: "apikey", value: apiKey),
            URLQueryItem(name: "f.wahlperiode", value: String(period)),
            URLQueryItem(name: "f.zuordnung", value: "BT"),  // Only Bundestag, not Bundesrat
            URLQueryItem(name: "format", value: "json")
        ]

        if let dateRange {
            queryItems.append(URLQueryItem(name: "f.datum.start", value: dateRange.startString))
            queryItems.append(URLQueryItem(name: "f.datum.end", value: dateRange.endString))
        }

        if let cursor = cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            throw FetchError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw FetchError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode(APIResponse.self, from: data)
    }

    /// Downloads the XML content for a specific protocol
    func downloadXML(for protocol: ProtocolMetadata) async throws -> Data {
        guard let xmlURL = `protocol`.fundstelle.xml_url,
              let url = URL(string: xmlURL) else {
            throw FetchError.noXMLAvailable
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw FetchError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        return data
    }

    // MARK: - XML File Management

    /// Returns the directory for cached XML files
    func getXMLDirectory() throws -> URL {
        let cacheDir = try getCacheDirectory()
        let xmlDir = cacheDir.appendingPathComponent("xml")

        if !FileManager.default.fileExists(atPath: xmlDir.path) {
            try FileManager.default.createDirectory(at: xmlDir, withIntermediateDirectories: true)
        }

        return xmlDir
    }

    /// Returns the local file path for a protocol's XML
    func xmlFilePath(for protocol: ProtocolMetadata) throws -> URL {
        let xmlDir = try getXMLDirectory()
        let filename = "\(`protocol`.wahlperiode)_\(`protocol`.dokumentnummer.replacingOccurrences(of: "/", with: "_")).xml"
        return xmlDir.appendingPathComponent(filename)
    }

    /// Checks if XML is already cached locally
    func isXMLCached(for protocol: ProtocolMetadata) -> Bool {
        guard let path = try? xmlFilePath(for: `protocol`) else { return false }
        return FileManager.default.fileExists(atPath: path.path)
    }

    /// Downloads and caches XML for a single protocol, skipping if already cached
    func downloadAndCacheXML(for protocol: ProtocolMetadata) async throws -> XMLDownloadResult {
        // Skip if already cached
        if isXMLCached(for: `protocol`) {
            return .skipped
        }

        // Skip if no XML URL available
        guard `protocol`.fundstelle.xml_url != nil else {
            return .noXML
        }

        let data = try await downloadXML(for: `protocol`)
        let filePath = try xmlFilePath(for: `protocol`)
        try data.write(to: filePath)

        return .downloaded
    }

    /// Downloads all XML files for the given protocols
    func downloadAllXMLs(for protocols: [ProtocolMetadata]) async -> XMLBatchResult {
        await MainActor.run {
            isFetching = true
            progress.xmlTotal = protocols.count
            progress.xmlDownloaded = 0
            progress.xmlSkipped = 0
            progress.xmlFailed = 0
            progress.message = "Starting XML downloads..."
        }

        defer {
            Task { @MainActor in
                isFetching = false
            }
        }

        var results = XMLBatchResult()

        for (index, proto) in protocols.enumerated() {
            await MainActor.run {
                progress.message = "Downloading \(index + 1)/\(protocols.count): \(proto.dokumentnummer)..."
            }

            do {
                let result = try await downloadAndCacheXML(for: proto)
                switch result {
                case .downloaded:
                    results.downloaded += 1
                    await MainActor.run { progress.xmlDownloaded += 1 }
                case .skipped:
                    results.skipped += 1
                    await MainActor.run { progress.xmlSkipped += 1 }
                case .noXML:
                    results.noXML += 1
                    await MainActor.run { progress.xmlFailed += 1 }
                }
            } catch {
                results.failed.append((proto.dokumentnummer, error.localizedDescription))
                await MainActor.run { progress.xmlFailed += 1 }
            }
        }

        await MainActor.run {
            progress.message = "Done! Downloaded: \(results.downloaded), Skipped: \(results.skipped), Failed: \(results.failed.count)"
        }

        return results
    }

    enum XMLDownloadResult {
        case downloaded
        case skipped
        case noXML
    }

    struct XMLBatchResult {
        var downloaded: Int = 0
        var skipped: Int = 0
        var noXML: Int = 0
        var failed: [(String, String)] = []  // (dokumentnummer, error)
    }

    /// Returns the cache directory, creating it if necessary
    func getCacheDirectory() throws -> URL {
        let fileManager = FileManager.default
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let cacheDir = appSupport
            .appendingPathComponent("NoLaughingMatter")
            .appendingPathComponent("Protocols")

        if !fileManager.fileExists(atPath: cacheDir.path) {
            try fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }

        return cacheDir
    }
}

// MARK: - API Response Models (used only for JSON decoding from API)

struct APIResponse: Codable {
    let numFound: Int
    let cursor: String
    let documents: [APIDocument]
}

struct APIDocument: Codable {
    let id: String
    let dokumentart: String
    let dokumentnummer: String
    let wahlperiode: Int
    let herausgeber: String
    let datum: String
    let aktualisiert: String
    let titel: String
    let fundstelle: Fundstelle
}

// MARK: - SwiftData Model

@Model
final class ProtocolMetadata {
    var apiId: String
    var dokumentart: String
    var dokumentnummer: String
    var wahlperiode: Int
    var herausgeber: String
    var datum: String
    var aktualisiert: String
    var titel: String
    var fundstelle: Fundstelle

    var sessionNumber: Int? {
        // Document number format is typically "WP/SESSION" e.g. "20/42"
        let parts = dokumentnummer.split(separator: "/")
        if parts.count == 2, let session = Int(parts[1]) {
            return session
        }
        return nil
    }

    init(
        apiId: String,
        dokumentart: String,
        dokumentnummer: String,
        wahlperiode: Int,
        herausgeber: String,
        datum: String,
        aktualisiert: String,
        titel: String,
        fundstelle: Fundstelle
    ) {
        self.apiId = apiId
        self.dokumentart = dokumentart
        self.dokumentnummer = dokumentnummer
        self.wahlperiode = wahlperiode
        self.herausgeber = herausgeber
        self.datum = datum
        self.aktualisiert = aktualisiert
        self.titel = titel
        self.fundstelle = fundstelle
    }
}

struct Fundstelle: Codable {
    let pdf_url: String?
    let xml_url: String?
    let dokumentnummer: String?
    let datum: String?
    let seite: String?
}

// MARK: - Errors

enum FetchError: LocalizedError {
    case invalidURL
    case httpError(Int)
    case noXMLAvailable
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL constructed"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .noXMLAvailable:
            return "No XML URL available for this protocol"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        }
    }
}
