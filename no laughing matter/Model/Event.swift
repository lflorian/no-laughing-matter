//
//  HumorEvent.swift
//  no laughing matter
//
//  Created by Florian Lammert on 13.01.26.
//

import Foundation

/// Represents a humor event extracted from a Bundestag protocol
struct HumorEvent: Identifiable, Codable {
    let id: UUID

    // MARK: - Session Metadata
    let wahlperiode: Int           // Legislative period (e.g., 19, 20, 21)
    let sitzungsnummer: Int        // Session number
    let datum: String              // Date of session

    // MARK: - Speaker Information
    let speakerId: String?         // Redner ID from XML
    let speakerName: String        // Full name of speaker
    let speakerParty: String?      // Party/Fraktion of speaker
    let speakerRole: String?       // Role if any (e.g., "Bundesminister")

    // MARK: - Humor Details
    let humorType: HumorType       // Type of humor marker
    let rawComment: String         // Original <kommentar> content
    let laughingParties: [String]  // Parties that laughed
    let laughingIndividuals: [LaughingIndividual] // Specific individuals who laughed

    // MARK: - Context
    let precedingText: String      // Text spoken before the humor event
    let followingText: String?     // Text spoken after (if available)
    let agendaItem: String?        // Tagesordnungspunkt if available

    // MARK: - Source Location
    let sourceFile: String         // XML filename
    let pageNumber: String?        // Seitennummer if available

    // MARK: - Classification (Phase 2)
    var classification: LLMClassification?

    init(
        wahlperiode: Int,
        sitzungsnummer: Int,
        datum: String,
        speakerId: String? = nil,
        speakerName: String,
        speakerParty: String? = nil,
        speakerRole: String? = nil,
        humorType: HumorType,
        rawComment: String,
        laughingParties: [String] = [],
        laughingIndividuals: [LaughingIndividual] = [],
        precedingText: String,
        followingText: String? = nil,
        agendaItem: String? = nil,
        sourceFile: String,
        pageNumber: String? = nil,
        classification: LLMClassification? = nil
    ) {
        self.id = UUID()
        self.wahlperiode = wahlperiode
        self.sitzungsnummer = sitzungsnummer
        self.datum = datum
        self.speakerId = speakerId
        self.speakerName = speakerName
        self.speakerParty = speakerParty
        self.speakerRole = speakerRole
        self.humorType = humorType
        self.rawComment = rawComment
        self.laughingParties = laughingParties
        self.laughingIndividuals = laughingIndividuals
        self.precedingText = precedingText
        self.followingText = followingText
        self.agendaItem = agendaItem
        self.sourceFile = sourceFile
        self.pageNumber = pageNumber
        self.classification = classification
    }
}

// MARK: - Supporting Types

enum HumorType: String, Codable, CaseIterable {
    case heiterkeit = "Heiterkeit"      // General amusement/mirth
    case lachen = "Lachen"              // Laughing

    var description: String {
        switch self {
        case .heiterkeit: return "Heiterkeit (Amusement)"
        case .lachen: return "Lachen (Laughing)"
        }
    }
}

struct LaughingIndividual: Codable, Equatable {
    let name: String
    let party: String?
}

// MARK: - Legacy compatibility

typealias Event = HumorEvent
