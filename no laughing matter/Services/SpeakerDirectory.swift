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
        let birthDate: Date?
        let wahlperioden: Set<Int>
    }

    /// ID -> SpeakerRecord
    private var speakersById: [String: SpeakerRecord] = [:]

    /// "vorname nachname" (lowercased) -> SpeakerRecord (fallback for name-based lookup)
    private var speakersByName: [String: SpeakerRecord] = [:]

    /// Wahlperiode number -> earliest MDBWP_VON date seen (used for age baseline calculation)
    private var wahlperiodeStartDates: [Int: Date] = [:]

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

        // Collect earliest WP start dates
        for (wp, date) in delegate.wahlperiodeStartDates {
            if let existing = wahlperiodeStartDates[wp] {
                if date < existing { wahlperiodeStartDates[wp] = date }
            } else {
                wahlperiodeStartDates[wp] = date
            }
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

    /// Age group labels used for bucketing (shared with VisualizerView)
    static let ageGroupOrder = ["Under 30", "30–39", "40–49", "50–59", "60–69", "70+"]

    static func ageGroupLabel(for age: Int) -> String {
        switch age {
        case ..<30: return "Under 30"
        case 30..<40: return "30–39"
        case 40..<50: return "40–49"
        case 50..<60: return "50–59"
        case 60..<70: return "60–69"
        default: return "70+"
        }
    }

    /// Returns MdB count per age group for a given Wahlperiode (age calculated at WP start date)
    func ageComposition(forWahlperiode wp: Int) -> [String: Int] {
        loadIfNeeded()
        guard let wpStartDate = wahlperiodeStartDates[wp] else { return [:] }
        let calendar = Calendar.current
        var counts: [String: Int] = [:]
        for record in speakersById.values {
            guard record.wahlperioden.contains(wp),
                  let birth = record.birthDate else { continue }
            let ageComponents = calendar.dateComponents([.year], from: birth, to: wpStartDate)
            guard let age = ageComponents.year, age > 0 && age < 120 else { continue }
            let group = Self.ageGroupLabel(for: age)
            counts[group, default: 0] += 1
        }
        return counts
    }

    /// Look up birth date by speaker ID (primary) then name (fallback)
    func birthDate(forId id: String?, name: String?) -> Date? {
        loadIfNeeded()
        if let id = id, let d = speakersById[id]?.birthDate {
            return d
        }
        if let name = name {
            let cleaned = name
                .replacingOccurrences(of: #"(Dr\.|Prof\.|h\.c\.)"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            if let d = speakersByName[cleaned]?.birthDate {
                return d
            }
        }
        return nil
    }

    /// Calculate age in years at a given date
    func age(forId id: String?, name: String?, onDate date: Date) -> Int? {
        guard let birth = birthDate(forId: id, name: name) else { return nil }
        let components = Calendar.current.dateComponents([.year], from: birth, to: date)
        return components.year
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
    var wahlperiodeStartDates: [Int: Date] = [:]

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
    private var currentGeburtsdatum = ""
    private var currentWP = ""
    private var currentMDBWPVon = ""
    private var currentWahlperioden: Set<Int> = []
    private var nameAlreadyCaptured = false

    private static let birthDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy"
        f.locale = Locale(identifier: "de_DE")
        return f
    }()

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
            currentGeburtsdatum = ""
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
                currentMDBWPVon = ""
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
        case "GEBURTSDATUM":
            if insideBiografie {
                currentGeburtsdatum += trimmed
            }
        case "WP":
            if insideWahlperiode {
                currentWP += trimmed
            }
        case "MDBWP_VON":
            if insideWahlperiode {
                currentMDBWPVon += trimmed
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
                let birthDate = Self.birthDateFormatter.date(from: currentGeburtsdatum)
                let record = SpeakerDirectory.SpeakerRecord(
                    id: currentId,
                    vorname: currentVorname,
                    nachname: currentNachname,
                    gender: gender,
                    birthDate: birthDate,
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
                if let date = Self.birthDateFormatter.date(from: currentMDBWPVon) {
                    if let existing = wahlperiodeStartDates[wp] {
                        if date < existing { wahlperiodeStartDates[wp] = date }
                    } else {
                        wahlperiodeStartDates[wp] = date
                    }
                }
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
