//
//  LaughEvent.swift
//  no laughing matter
//
//  Created by Florian Lammert on 14.09.25.
//

import Foundation

struct LaughEvent: Identifiable, Codable, Hashable {
    // Metadata
    var id = UUID()
    let fileName: String
    let session: String? // z.B. "21/01"
    let date: String? // "2025-01-15
    
    let speakerName: String?
    let speakerParty: String?
    
    let reactionType: ReactionType
    let reactionName: String? // Name of laughing person
    let reactionParties: Set<Party>
    
    let context: String // Textausschnitt
}

enum ReactionType: String, Codable {
    case heiterkeit
    case gelächter
    case lachen
    case beifall
    case heiterkeitUndBeifall
    case other
    
    var display: String {
        switch self {
        case .heiterkeit: return "Heiterkeit"
        case .gelächter: return "Gelächter"
        case .lachen: return "Lachen"
        case .beifall: return "Beifall"
        case .heiterkeitUndBeifall: return "Heiterkeit und Beifall"
        case .other: return "Andere"
        }
    }
}

enum Party: String, Codable {
    case cducsu
    case afd
    case spd
    case grüne
    case linke
    case ssw
    case parteilos
    case allgemein
    
    var display: String {
        switch self {
        case .cducsu: return "CDU/CSU"
        case .afd: return "AfD"
        case .spd: return "SPD"
        case .grüne: return "BÜNDNIS 90/DIE GRÜNEN"
        case .linke: return "Die Linke"
        case .ssw: return "SSW"
        case .parteilos: return "Parteilos"
        case .allgemein: return "Allgemein"
        }
    }
    
    func normalizeParty(_ raw: String) -> Set<Party>? {
        var parties = Set<Party>()
        let lower = raw.lowercased()
        
        if lower.contains("cdu") || lower.contains("csu") {
            parties.insert(.cducsu)
        }
        if lower.contains("afd") {
            parties.insert(.afd)
        }
        if lower.contains("spd") {
            parties.insert(.spd)
        }
        if lower.contains("grüne") || lower.contains("bündnis") {
            parties.insert(.grüne)
        }
        if lower.contains("linke") {
            parties.insert(.linke)
        }
        if lower.contains("ssw") {
            parties.insert(.ssw)
        }
        if lower.contains("parteilos") {
            parties.insert(.parteilos)
        }
        if lower.contains("allgemein") {
            parties.insert(.allgemein)
        }
        
        // Fallback
        if parties.isEmpty {
            return nil
        }
        
        return parties
    }
}
