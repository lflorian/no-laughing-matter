//
//  HumorEvent.swift
//  no laughing matter
//
//  Created by Florian Lammert on 13.01.26.
//

import Foundation
import SwiftData

/// Represents a humor event extracted from a Bundestag protocol
@Model
final class HumorEvent {
    // MARK: - Session Metadata
    var wahlperiode: Int           // Legislative period (e.g., 19, 20, 21)
    var sitzungsnummer: Int        // Session number
    var datum: String              // Date of session

    // MARK: - Speaker Information
    var speakerId: String?         // Redner ID from XML
    var speakerName: String        // Full name of speaker
    var speakerParty: String?      // Party/Fraktion of speaker
    var speakerRole: String?       // Role if any (e.g., "Bundesminister")
    var speakerGender: SpeakerDirectory.Gender? // Gender from MDB_STAMMDATEN
    var speakerAge: Int?                        // Age at time of session from MDB_STAMMDATEN

    // MARK: - Humor Details
    var humorType: HumorType       // Type of humor marker
    var rawComment: String         // Original <kommentar> content
    var laughingParties: [String]  // Parties that laughed
    var laughingIndividuals: [LaughingIndividual] // Specific individuals who laughed

    // MARK: - Context
    var precedingText: String      // Text spoken before the humor event
    var followingText: String?     // Text spoken after (if available)
    var agendaItem: String?        // Tagesordnungspunkt if available

    // MARK: - Source Location
    var sourceFile: String         // XML filename
    var pageNumber: String?        // Seitennummer if available

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
        speakerGender: SpeakerDirectory.Gender? = nil,
        speakerAge: Int? = nil,
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
        self.wahlperiode = wahlperiode
        self.sitzungsnummer = sitzungsnummer
        self.datum = datum
        self.speakerId = speakerId
        self.speakerName = speakerName
        self.speakerParty = speakerParty
        self.speakerRole = speakerRole
        self.speakerGender = speakerGender
        self.speakerAge = speakerAge
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
        case .heiterkeit: "Heiterkeit (Amusement)"
        case .lachen: "Lachen (Laughing)"
        }
    }
}

struct LaughingIndividual: Codable, Equatable {
    let name: String
    let party: String?
}
