//
//  SpeakerDirectory.swift
//  no laughing matter
//
//  Created by Claude on 14.03.26.
//

import Foundation

/// Provides gender lookup for Bundestag members using MDB_STAMMDATEN.XML
final class SpeakerDirectory {

    static let shared = SpeakerDirectory()

    enum Gender: String, Codable {
        case male = "männlich"
        case female = "weiblich"

        var displayName: String {
            switch self {
            case .male: return "Male"
            case .female: return "Female"
            }
        }
    }

    struct SpeakerRecord {
        let id: String
        let vorname: String
        let nachname: String
        let gender: Gender
        let wahlperioden: Set<Int>
    }

    /// ID -> SpeakerRecord
    private var speakersById: [String: SpeakerRecord] = [:]

    /// "vorname nachname" (lowercased) -> SpeakerRecord (fallback for name-based lookup)
    private var speakersByName: [String: SpeakerRecord] = [:]

    private(set) var isLoaded = false

    private init() {}

    /// Loads the MDB_STAMMDATEN.XML from the app bundle
    func loadIfNeeded() {
        guard !isLoaded else { return }
        guard let url = Bundle.main.url(forResource: "MDB_STAMMDATEN", withExtension: "XML") else {
            print("SpeakerDirectory: MDB_STAMMDATEN.XML not found in bundle")
            return
        }
        load(from: url)
    }

    /// Loads from a specific URL (useful for testing)
    func load(from url: URL) {
        guard let parser = XMLParser(contentsOf: url) else {
            print("SpeakerDirectory: Could not create parser for \(url)")
            return
        }

        let delegate = StammdatenParserDelegate()
        parser.delegate = delegate
        parser.parse()

        for record in delegate.records {
            speakersById[record.id] = record
            let nameKey = "\(record.vorname) \(record.nachname)".lowercased()
            speakersByName[nameKey] = record
        }

        isLoaded = true
        print("SpeakerDirectory: Loaded \(speakersById.count) speaker records")
    }

    /// Look up gender by speaker ID (primary)
    func gender(forId id: String) -> Gender? {
        loadIfNeeded()
        return speakersById[id]?.gender
    }

    /// Look up gender by full name (fallback)
    func gender(forName name: String) -> Gender? {
        loadIfNeeded()
        // Strip titles like "Dr." or "Prof." for matching
        let cleaned = name
            .replacingOccurrences(of: #"(Dr\.|Prof\.|h\.c\.)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        return speakersByName[cleaned]?.gender
    }

    /// Look up gender by ID first, then fall back to name
    func gender(forId id: String?, name: String?) -> Gender? {
        if let id = id, let g = gender(forId: id) {
            return g
        }
        if let name = name, let g = gender(forName: name) {
            return g
        }
        return nil
    }

    /// Returns the number of male and female MdBs for a given Wahlperiode
    func genderComposition(forWahlperiode wp: Int) -> (male: Int, female: Int) {
        loadIfNeeded()
        var male = 0
        var female = 0
        for record in speakersById.values {
            guard record.wahlperioden.contains(wp) else { continue }
            switch record.gender {
            case .male: male += 1
            case .female: female += 1
            }
        }
        return (male: male, female: female)
    }

    /// Returns all Wahlperioden that have at least one MdB record
    var availableWahlperioden: [Int] {
        loadIfNeeded()
        let wps = speakersById.values.flatMap(\.wahlperioden)
        return Array(Set(wps)).sorted()
    }
}

// MARK: - SAX Parser Delegate

private class StammdatenParserDelegate: NSObject, XMLParserDelegate {
    var records: [SpeakerDirectory.SpeakerRecord] = []

    // Current parsing state
    private var currentElement = ""
    private var insideMDB = false
    private var insideNamen = false
    private var insideFirstName = false // only use the first <NAME> block (current name)
    private var insideBiografie = false
    private var insideWahlperioden = false
    private var insideWahlperiode = false

    private var currentId = ""
    private var currentVorname = ""
    private var currentNachname = ""
    private var currentGeschlecht = ""
    private var currentWP = ""
    private var currentWahlperioden: Set<Int> = []
    private var nameAlreadyCaptured = false

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        currentElement = elementName

        switch elementName {
        case "MDB":
            insideMDB = true
            currentId = ""
            currentVorname = ""
            currentNachname = ""
            currentGeschlecht = ""
            currentWahlperioden = []
            nameAlreadyCaptured = false
        case "NAMEN":
            insideNamen = true
        case "NAME":
            if insideNamen && !nameAlreadyCaptured {
                insideFirstName = true
            }
        case "BIOGRAFISCHE_ANGABEN":
            insideBiografie = true
        case "WAHLPERIODEN":
            insideWahlperioden = true
        case "WAHLPERIODE":
            if insideWahlperioden {
                insideWahlperiode = true
                currentWP = ""
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard insideMDB else { return }

        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        switch currentElement {
        case "ID":
            if !insideNamen && !insideBiografie {
                currentId += trimmed
            }
        case "VORNAME":
            if insideFirstName {
                currentVorname += trimmed
            }
        case "NACHNAME":
            if insideFirstName {
                currentNachname += trimmed
            }
        case "GESCHLECHT":
            if insideBiografie {
                currentGeschlecht += trimmed
            }
        case "WP":
            if insideWahlperiode {
                currentWP += trimmed
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        switch elementName {
        case "MDB":
            if !currentId.isEmpty, let gender = SpeakerDirectory.Gender(rawValue: currentGeschlecht) {
                let record = SpeakerDirectory.SpeakerRecord(
                    id: currentId,
                    vorname: currentVorname,
                    nachname: currentNachname,
                    gender: gender,
                    wahlperioden: currentWahlperioden
                )
                records.append(record)
            }
            insideMDB = false
        case "NAME":
            if insideFirstName {
                insideFirstName = false
                nameAlreadyCaptured = true
            }
        case "NAMEN":
            insideNamen = false
        case "BIOGRAFISCHE_ANGABEN":
            insideBiografie = false
        case "WAHLPERIODE":
            if insideWahlperiode, let wp = Int(currentWP) {
                currentWahlperioden.insert(wp)
            }
            insideWahlperiode = false
        case "WAHLPERIODEN":
            insideWahlperioden = false
        default:
            break
        }

        currentElement = ""
    }
}
