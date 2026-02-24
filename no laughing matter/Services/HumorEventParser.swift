//
//  HumorEventParser.swift
//  no laughing matter
//
//  Created by Claude on 20.01.26.
//

import Foundation

/// Service for parsing Bundestag XML protocols and extracting humor events
final class HumorEventParser {

    static let shared = HumorEventParser()

    private init() {}

    // MARK: - Main Parsing

    /// Parses a single XML protocol file and extracts all humor events
    func parseProtocol(at url: URL) throws -> [HumorEvent] {
        let data = try Data(contentsOf: url)
        guard let xmlString = String(data: data, encoding: .utf8) else {
            throw ParserError.invalidEncoding
        }

        let filename = url.lastPathComponent
        let metadata = try extractSessionMetadata(from: xmlString)

        return extractHumorEvents(
            from: xmlString,
            metadata: metadata,
            sourceFile: filename
        )
    }

    /// Parses multiple protocol files
    func parseProtocols(at urls: [URL], progress: ((Int, Int) -> Void)? = nil) throws -> [HumorEvent] {
        var allEvents: [HumorEvent] = []

        for (index, url) in urls.enumerated() {
            progress?(index + 1, urls.count)
            do {
                let events = try parseProtocol(at: url)
                allEvents.append(contentsOf: events)
            } catch {
                print("Warning: Failed to parse \(url.lastPathComponent): \(error)")
            }
        }

        return allEvents
    }

    // MARK: - Session Metadata Extraction

    private func extractSessionMetadata(from xml: String) throws -> SessionMetadata {
        // Extract from root element attributes: wahlperiode, sitzung-nr, sitzung-datum
        let wahlperiodePattern = #"wahlperiode="(\d+)""#
        let sitzungNrPattern = #"sitzung-nr="(\d+)""#
        let datumPattern = #"sitzung-datum="([^"]+)""#

        guard let wahlperiode = extractFirst(pattern: wahlperiodePattern, from: xml).flatMap({ Int($0) }),
              let sitzungsnummer = extractFirst(pattern: sitzungNrPattern, from: xml).flatMap({ Int($0) }) else {
            throw ParserError.missingMetadata
        }

        let datum = extractFirst(pattern: datumPattern, from: xml) ?? "unknown"

        return SessionMetadata(
            wahlperiode: wahlperiode,
            sitzungsnummer: sitzungsnummer,
            datum: datum
        )
    }

    // MARK: - Humor Event Extraction

    private func extractHumorEvents(
        from xml: String,
        metadata: SessionMetadata,
        sourceFile: String
    ) -> [HumorEvent] {
        var events: [HumorEvent] = []

        // Find all <kommentar> tags that contain humor markers
        let kommentarPattern = #"<kommentar>\(([^)]+)\)</kommentar>"#
        let regex = try? NSRegularExpression(pattern: kommentarPattern, options: [])
        let range = NSRange(xml.startIndex..., in: xml)

        regex?.enumerateMatches(in: xml, options: [], range: range) { match, _, _ in
            guard let match = match,
                  let contentRange = Range(match.range(at: 1), in: xml) else { return }

            let content = String(xml[contentRange])
            let fullComment = "(\(content))"

            // Check if this comment contains a humor marker
            guard let humorType = detectHumorType(in: content) else { return }

            // Extract who is laughing
            let laughingParties = extractLaughingParties(from: content)
            let laughingIndividuals = extractLaughingIndividuals(from: content)

            // Extract context (speaker and preceding text)
            let context = extractContext(from: xml, matchRange: match.range)

            let event = HumorEvent(
                wahlperiode: metadata.wahlperiode,
                sitzungsnummer: metadata.sitzungsnummer,
                datum: metadata.datum,
                speakerId: context.speakerId,
                speakerName: context.speakerName,
                speakerParty: context.speakerParty,
                speakerRole: context.speakerRole,
                humorType: humorType,
                rawComment: fullComment,
                laughingParties: laughingParties,
                laughingIndividuals: laughingIndividuals,
                precedingText: context.precedingText,
                followingText: context.followingText,
                agendaItem: context.agendaItem,
                sourceFile: sourceFile,
                pageNumber: context.pageNumber
            )

            events.append(event)
        }

        return events
    }

    // MARK: - Humor Type Detection

    /// Detects the type of humor marker in a comment
    private func detectHumorType(in content: String) -> HumorType? {
        // Check for each humor type (order matters - check more specific first)
        if content.contains("Gelächter") {
            return .gelaechter
        }
        if content.contains("Heiterkeit") {
            return .heiterkeit
        }
        if content.contains("Lachen") {
            return .lachen
        }
        return nil
    }

    // MARK: - Party Extraction

    /// Known parties/factions in the Bundestag
    private let knownParties = [
        "CDU/CSU",
        "SPD",
        "AfD",
        "FDP",
        "DIE LINKE",
        "LINKEN",
        "BÜNDNIS 90/DIE GRÜNEN",
        "BÜNDNISSES 90/DIE GRÜNEN",
        "GRÜNEN",
        "BSW",
        "fraktionslos"
    ]

    /// Normalizes party names to consistent format
    private func normalizeParty(_ party: String) -> String {
        switch party {
        case "CDU/CSU":
            return "CDU"
        case "LINKEN", "DIE LINKE":
            return "DIE LINKE"
        case "GRÜNEN", "BÜNDNISSES 90/DIE GRÜNEN", "BÜNDNIS 90/DIE GRÜNEN":
            return "BÜNDNIS 90/DIE GRÜNEN"
        default:
            return party
        }
    }

    /// Extracts parties that are laughing from a comment
    private func extractLaughingParties(from content: String) -> [String] {
        var parties: Set<String> = []

        // Pattern: "Heiterkeit/Lachen bei der/dem/Abgeordneten der PARTY"
        // Also handles: "bei der CDU/CSU sowie bei Abgeordneten der SPD"

        // Split by common separators to handle multiple parties
        let segments = content.components(separatedBy: CharacterSet(charactersIn: "–—,"))

        for segment in segments {
            // Only extract parties from segments that contain a humor keyword
            guard segment.contains("Heiterkeit") ||
                  segment.contains("Lachen") ||
                  segment.contains("Gelächter") else { continue }

            for party in knownParties {
                if segment.contains(party) {
                    parties.insert(normalizeParty(party))
                }
            }
        }

        return Array(parties).sorted()
    }

    // MARK: - Individual Extraction

    /// Extracts specific individuals who are laughing
    private func extractLaughingIndividuals(from content: String) -> [LaughingIndividual] {
        var individuals: [LaughingIndividual] = []

        // Pattern 1: "Lachen des Abg. Name [Party]"
        let abgPattern = #"(?:Lachen|Heiterkeit)\s+des\s+Abg\.\s+([^[]+)\s*\[([^\]]+)\]"#

        if let regex = try? NSRegularExpression(pattern: abgPattern, options: []) {
            let range = NSRange(content.startIndex..., in: content)
            regex.enumerateMatches(in: content, options: [], range: range) { match, _, _ in
                guard let match = match,
                      let nameRange = Range(match.range(at: 1), in: content),
                      let partyRange = Range(match.range(at: 2), in: content) else { return }

                let name = String(content[nameRange]).trimmingCharacters(in: .whitespaces)
                let party = normalizeParty(String(content[partyRange]))
                individuals.append(LaughingIndividual(name: name, party: party))
            }
        }

        // Pattern 2: "Lachen der Abg. Name [Party]" (female form)
        let abgFemPattern = #"(?:Lachen|Heiterkeit)\s+der\s+Abg\.\s+([^[]+)\s*\[([^\]]+)\]"#

        if let regex = try? NSRegularExpression(pattern: abgFemPattern, options: []) {
            let range = NSRange(content.startIndex..., in: content)
            regex.enumerateMatches(in: content, options: [], range: range) { match, _, _ in
                guard let match = match,
                      let nameRange = Range(match.range(at: 1), in: content),
                      let partyRange = Range(match.range(at: 2), in: content) else { return }

                let name = String(content[nameRange]).trimmingCharacters(in: .whitespaces)
                let party = normalizeParty(String(content[partyRange]))
                individuals.append(LaughingIndividual(name: name, party: party))
            }
        }

        return individuals
    }

    // MARK: - Context Extraction

    private struct SpeechContext {
        var speakerId: String?
        var speakerName: String
        var speakerParty: String?
        var speakerRole: String?
        var precedingText: String
        var followingText: String?
        var agendaItem: String?
        var pageNumber: String?
    }

    /// Extracts the context (speaker, preceding text) for a humor event.
    /// Uses a limited lookback window to avoid copying the entire XML prefix.
    private func extractContext(from xml: String, matchRange: NSRange) -> SpeechContext {
        guard let swiftRange = Range(matchRange, in: xml) else {
            return SpeechContext(speakerId: nil, speakerName: "Unknown", speakerParty: nil, speakerRole: nil, precedingText: "", followingText: nil, agendaItem: nil, pageNumber: nil)
        }

        let matchStartIndex = swiftRange.lowerBound
        let matchEndIndex = swiftRange.upperBound
        let charsBeforeMatch = xml.distance(from: xml.startIndex, to: matchStartIndex)

        // Use a limited lookback window (10KB) for preceding text and page number
        let shortLookback = 10_000
        let shortStart = xml.index(matchStartIndex, offsetBy: -min(shortLookback, charsBeforeMatch), limitedBy: xml.startIndex) ?? xml.startIndex
        let shortPrefix = String(xml[shortStart..<matchStartIndex])

        // Use a larger lookback window (50KB) for speaker and agenda item
        // (these tags can be further back in the document)
        let longLookback = 50_000
        let longStart = xml.index(matchStartIndex, offsetBy: -min(longLookback, charsBeforeMatch), limitedBy: xml.startIndex) ?? xml.startIndex
        let longPrefix = String(xml[longStart..<matchStartIndex])

        // Find the most recent speaker (redner tag)
        let speakerInfo = extractMostRecentSpeaker(from: longPrefix)

        // Find preceding text (most recent <p> tag content)
        let precedingText = extractPrecedingText(from: shortPrefix)

        // Find page number
        let pageNumber = extractMostRecentPageNumber(from: shortPrefix)

        // Find agenda item (Tagesordnungspunkt)
        let agendaItem = extractCurrentAgendaItem(from: longPrefix)

        // Find following text
        let followingText = extractFollowingText(from: xml, afterIndex: matchEndIndex)

        return SpeechContext(
            speakerId: speakerInfo.id,
            speakerName: speakerInfo.name ?? "Unknown",
            speakerParty: speakerInfo.party,
            speakerRole: speakerInfo.role,
            precedingText: precedingText,
            followingText: followingText,
            agendaItem: agendaItem,
            pageNumber: pageNumber
        )
    }

    private struct SpeakerInfo {
        var id: String?
        var name: String?
        var party: String?
        var role: String?
    }

    /// Extracts the most recent speaker from the XML prefix
    private func extractMostRecentSpeaker(from prefix: String) -> SpeakerInfo {
        // Find the last <redner> tag with full details
        // Pattern: <redner id="..."><name>...</name></redner>
        let rednerPattern = #"<redner\s+id="([^"]+)"[^>]*>\s*<name>(.*?)</name>\s*</redner>"#

        var lastMatch: SpeakerInfo?

        if let regex = try? NSRegularExpression(pattern: rednerPattern, options: [.dotMatchesLineSeparators]) {
            let range = NSRange(prefix.startIndex..., in: prefix)
            regex.enumerateMatches(in: prefix, options: [], range: range) { match, _, _ in
                guard let match = match,
                      let idRange = Range(match.range(at: 1), in: prefix),
                      let nameBlockRange = Range(match.range(at: 2), in: prefix) else { return }

                let id = String(prefix[idRange])
                let nameBlock = String(prefix[nameBlockRange])

                // Parse name components
                let vorname = extractFirst(pattern: #"<vorname>([^<]+)</vorname>"#, from: nameBlock) ?? ""
                let nachname = extractFirst(pattern: #"<nachname>([^<]+)</nachname>"#, from: nameBlock) ?? ""
                let titel = extractFirst(pattern: #"<titel>([^<]+)</titel>"#, from: nameBlock)
                let fraktion = extractFirst(pattern: #"<fraktion>([^<]+)</fraktion>"#, from: nameBlock)
                let rolle = extractFirst(pattern: #"<rolle_lang>([^<]+)</rolle_lang>"#, from: nameBlock)

                var fullName = ""
                if let titel = titel {
                    fullName += titel + " "
                }
                fullName += vorname + " " + nachname

                lastMatch = SpeakerInfo(
                    id: id,
                    name: fullName.trimmingCharacters(in: .whitespaces),
                    party: fraktion,
                    role: rolle
                )
            }
        }

        // Also check for <name>Präsident/Präsidentin...</name> format for chamber presidents
        if lastMatch == nil {
            let namePattern = #"<name>([^<]+)</name>"#
            if let regex = try? NSRegularExpression(pattern: namePattern, options: []) {
                let range = NSRange(prefix.startIndex..., in: prefix)
                var lastName: String?
                regex.enumerateMatches(in: prefix, options: [], range: range) { match, _, _ in
                    guard let match = match,
                          let nameRange = Range(match.range(at: 1), in: prefix) else { return }
                    lastName = String(prefix[nameRange])
                }
                if let name = lastName {
                    lastMatch = SpeakerInfo(id: nil, name: name, party: nil, role: nil)
                }
            }
        }

        return lastMatch ?? SpeakerInfo(id: nil, name: nil, party: nil, role: nil)
    }

    /// Extracts the 2–3 most recent paragraphs before the humor marker
    private func extractPrecedingText(from prefix: String) -> String {
        // Find all <p ...>content</p> tags and collect their cleaned text
        let pPattern = #"<p\s+[^>]*>(.*?)</p>"#
        var paragraphs: [String] = []

        if let regex = try? NSRegularExpression(pattern: pPattern, options: [.dotMatchesLineSeparators]) {
            let range = NSRange(prefix.startIndex..., in: prefix)
            regex.enumerateMatches(in: prefix, options: [], range: range) { match, _, _ in
                guard let match = match,
                      let textRange = Range(match.range(at: 1), in: prefix) else { return }
                let rawText = String(prefix[textRange])
                // Strip any remaining XML tags
                let cleanText = rawText.replacingOccurrences(
                    of: #"<[^>]+>"#,
                    with: "",
                    options: .regularExpression
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleanText.isEmpty {
                    paragraphs.append(cleanText)
                }
            }
        }

        // Take the last 3 paragraphs and join them
        let lastParagraphs = paragraphs.suffix(3)
        return lastParagraphs.joined(separator: " ")
    }

    /// Extracts the most recent page number
    private func extractMostRecentPageNumber(from prefix: String) -> String? {
        let pattern = #"<seite>(\d+)</seite>"#
        var lastPage: String?

        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(prefix.startIndex..., in: prefix)
            regex.enumerateMatches(in: prefix, options: [], range: range) { match, _, _ in
                guard let match = match,
                      let pageRange = Range(match.range(at: 1), in: prefix) else { return }
                lastPage = String(prefix[pageRange])
            }
        }

        // Fallback: inline page markers like <a id="S9" name="S9" typ="druckseitennummer"/>
        if lastPage == nil {
            let inlinePattern = #"<a\s+id="S(\d+)"[^>]*/?\s*>"#
            if let regex = try? NSRegularExpression(pattern: inlinePattern, options: []) {
                let range = NSRange(prefix.startIndex..., in: prefix)
                regex.enumerateMatches(in: prefix, options: [], range: range) { match, _, _ in
                    guard let match = match,
                          let pageRange = Range(match.range(at: 1), in: prefix) else { return }
                    lastPage = String(prefix[pageRange])
                }
            }
        }

        return lastPage
    }

    /// Extracts the current agenda item (Tagesordnungspunkt) from the session body.
    /// Searches for `<tagesordnungspunkt top-id="...">` tags (not the TOC).
    private func extractCurrentAgendaItem(from prefix: String) -> String? {
        let topPattern = #"<tagesordnungspunkt\s+top-id="([^"]+)"[^>]*>"#
        var lastTopId: String?
        var lastMatchEnd: Int = 0

        guard let regex = try? NSRegularExpression(pattern: topPattern, options: []) else { return nil }
        let range = NSRange(prefix.startIndex..., in: prefix)

        regex.enumerateMatches(in: prefix, options: [], range: range) { match, _, _ in
            guard let match = match,
                  let idRange = Range(match.range(at: 1), in: prefix) else { return }
            lastTopId = String(prefix[idRange])
            lastMatchEnd = match.range.location + match.range.length
        }

        guard let topId = lastTopId else { return nil }

        let label = "Tagesordnungspunkt \(topId)"

        // Look forward (up to 5KB) for a topic description in <p klasse="T_NaS">
        let forwardLimit = min(lastMatchEnd + 5_000, prefix.count)
        if forwardLimit > lastMatchEnd,
           let forwardStartIndex = Range(NSRange(location: lastMatchEnd, length: forwardLimit - lastMatchEnd), in: prefix) {
            let forwardSlice = String(prefix[forwardStartIndex])
            let topicPattern = #"<p\s+klasse="T_NaS"[^>]*>([^<]+)</p>"#
            if let topicText = extractFirst(pattern: topicPattern, from: forwardSlice) {
                let cleaned = topicText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    return "\(label): \(cleaned)"
                }
            }
        }

        return label
    }

    /// Extracts the first paragraph of text following the humor marker
    private func extractFollowingText(from xml: String, afterIndex: String.Index) -> String? {
        let charsAfterMatch = xml.distance(from: afterIndex, to: xml.endIndex)
        let forwardLimit = min(2_000, charsAfterMatch)
        guard forwardLimit > 0 else { return nil }

        let forwardEnd = xml.index(afterIndex, offsetBy: forwardLimit)
        let forwardSlice = String(xml[afterIndex..<forwardEnd])

        let pPattern = #"<p\s+[^>]*>(.*?)</p>"#
        guard let regex = try? NSRegularExpression(pattern: pPattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: forwardSlice, options: [], range: NSRange(forwardSlice.startIndex..., in: forwardSlice)),
              let textRange = Range(match.range(at: 1), in: forwardSlice) else {
            return nil
        }

        let rawText = String(forwardSlice[textRange])
        let cleanText = rawText.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        return cleanText.isEmpty ? nil : cleanText
    }

    // MARK: - Helpers

    private func extractFirst(pattern: String, from text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }
}

// MARK: - Supporting Types

private struct SessionMetadata {
    let wahlperiode: Int
    let sitzungsnummer: Int
    let datum: String
}

// MARK: - Errors

enum ParserError: LocalizedError {
    case invalidEncoding
    case missingMetadata
    case fileNotFound

    var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return "Could not read file with UTF-8 encoding"
        case .missingMetadata:
            return "Required session metadata not found in XML"
        case .fileNotFound:
            return "Protocol file not found"
        }
    }
}
