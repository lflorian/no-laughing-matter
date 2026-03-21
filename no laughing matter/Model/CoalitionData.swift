//
//  CoalitionData.swift
//  no laughing matter
//
//  Created by Claude on 21.03.26.
//

import Foundation

enum PoliticalRole: String, CaseIterable {
    case government = "Government"
    case opposition = "Opposition"
    case other = "Other"
}

/// Static mapping of coalition compositions for Bundestag legislative periods (WP 14–21).
/// Party names use the normalized form from `normalizeParty()`.
struct CoalitionData {

    /// Governing parties per Wahlperiode (all others are opposition).
    static let governingParties: [Int: [String]] = [
        14: ["SPD", "BÜNDNIS 90/DIE GRÜNEN"],
        15: ["SPD", "BÜNDNIS 90/DIE GRÜNEN"],
        16: ["CDU/CSU", "SPD"],
        17: ["CDU/CSU", "FDP"],
        18: ["CDU/CSU", "SPD"],
        19: ["CDU/CSU", "SPD"],
        20: ["SPD", "BÜNDNIS 90/DIE GRÜNEN", "FDP"],
        21: ["CDU/CSU", "SPD"],
    ]

    /// Returns the political role of a party in a given Wahlperiode.
    static func role(for party: String, in wahlperiode: Int) -> PoliticalRole {
        guard let coalition = governingParties[wahlperiode] else { return .other }

        if party == "Fraktionslos" || party.isEmpty { return .other }

        if coalition.contains(party) {
            return .government
        } else {
            return .opposition
        }
    }

    /// Seat counts per party per Wahlperiode (at start of legislative period).
    /// Sources: bundestag.de Sitzverteilung archives.
    static let seatCounts: [Int: [String: Int]] = [
        14: ["SPD": 298, "CDU/CSU": 245, "BÜNDNIS 90/DIE GRÜNEN": 47, "FDP": 43, "PDS": 36],
        15: ["SPD": 251, "CDU/CSU": 248, "BÜNDNIS 90/DIE GRÜNEN": 55, "FDP": 47, "PDS": 2],
        16: ["CDU/CSU": 226, "SPD": 222, "FDP": 61, "DIE LINKE": 54, "BÜNDNIS 90/DIE GRÜNEN": 51],
        17: ["CDU/CSU": 239, "SPD": 146, "FDP": 93, "DIE LINKE": 76, "BÜNDNIS 90/DIE GRÜNEN": 68],
        18: ["CDU/CSU": 311, "SPD": 193, "DIE LINKE": 64, "BÜNDNIS 90/DIE GRÜNEN": 63],
        19: ["CDU/CSU": 246, "SPD": 153, "AfD": 94, "FDP": 80, "DIE LINKE": 69, "BÜNDNIS 90/DIE GRÜNEN": 67],
        20: ["SPD": 206, "CDU/CSU": 197, "BÜNDNIS 90/DIE GRÜNEN": 118, "FDP": 92, "AfD": 83, "DIE LINKE": 39, "BSW": 10],
        21: ["CDU/CSU": 208, "AfD": 152, "SPD": 120, "BÜNDNIS 90/DIE GRÜNEN": 85, "BSW": 40, "DIE LINKE": 28, "FDP": 0],
    ]

    /// Returns the average number of seats for a party across the given Wahlperioden.
    /// Falls back to 0 if the party is not found in any period.
    static func averageSeats(for party: String, in wahlperioden: Set<Int>) -> Double {
        let counts = wahlperioden.compactMap { seatCounts[$0]?[party] }
        guard !counts.isEmpty else { return 0 }
        return Double(counts.reduce(0, +)) / Double(counts.count)
    }

    /// Human-readable coalition label for a Wahlperiode.
    static func coalitionLabel(for wahlperiode: Int) -> String {
        guard let parties = governingParties[wahlperiode] else { return "Unknown" }
        return parties.joined(separator: " + ")
    }
}
