//
//  ChartHelpers.swift
//  no laughing matter
//
//  Created by Claude on 21.03.26.
//

import SwiftUI

func normalizeParty(_ raw: String) -> String {
    let p = raw.trimmingCharacters(in: .whitespaces)
    let upper = p.uppercased()

    if upper == "CDU" || upper == "CSU" || upper == "CDU/CSU" {
        return "CDU/CSU"
    }
    if upper.contains("GRÜN") || upper.contains("BÜNDNIS") || upper.contains("BUNDNIS") {
        return "BÜNDNIS 90/DIE GRÜNEN"
    }
    if upper.contains("LINKE") || upper == "PDS" {
        return "Die Linke"
    }
    if upper == "AFD" {
        return "AfD"
    }
    if upper == "FRAKTIONSLOS" {
        return "Fraktionslos"
    }
    return p
}

func partyColor(_ party: String) -> Color {
    switch normalizeParty(party) {
    case "CDU/CSU":                return Color(red: 0.18, green: 0.18, blue: 0.18)
    case "SPD":                    return Color(red: 0.84, green: 0.08, blue: 0.08)
    case "BÜNDNIS 90/DIE GRÜNEN": return Color(red: 0.25, green: 0.62, blue: 0.18)
    case "FDP":                    return Color(red: 0.87, green: 0.72, blue: 0.0)
    case "AfD":                    return Color(red: 0.0,  green: 0.44, blue: 0.70)
    case "Die Linke":              return Color(red: 0.58, green: 0.0,  blue: 0.28)
    case "BSW":                    return Color(red: 0.48, green: 0.0,  blue: 0.52)
    case "SSW":                    return Color(red: 0.0,  green: 0.48, blue: 0.52)
    default:                       return Color.gray
    }
}

func intentionColor(_ intention: HumorIntention) -> Color {
    switch intention {
    case .aggressive:    return .red
    case .social:        return .green
    case .defensive:     return .blue
    case .intellectual:  return .purple
    case .sexual:        return .pink
    case .unclear:       return Color.gray.opacity(0.5)
    }
}

func genderColor(_ gender: SpeakerDirectory.Gender) -> Color {
    switch gender {
    case .male:   return Color(red: 0.27, green: 0.51, blue: 0.71) // steel blue
    case .female: return Color(red: 0.80, green: 0.36, blue: 0.46) // rose
    }
}

func humorTypeColor(_ type: HumorType) -> Color {
    switch type {
    case .heiterkeit: return .blue
    case .lachen:     return .orange
    }
}

func abbreviate(_ party: String) -> String {
    switch normalizeParty(party) {
    case "CDU/CSU":                return "CDU/CSU"
    case "SPD":                    return "SPD"
    case "BÜNDNIS 90/DIE GRÜNEN": return "Grüne"
    case "FDP":                    return "FDP"
    case "AfD":                    return "AfD"
    case "Die Linke":              return "Linke"
    case "BSW":                    return "BSW"
    case "SSW":                    return "SSW"
    case "fraktionslos":           return "frakti."
    default:
        let p = normalizeParty(party)
        return p.count > 9 ? String(p.prefix(8)) + "…" : p
    }
}

func emptyLabel(_ message: String) -> some View {
    Label(message, systemImage: "exclamationmark.triangle")
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.vertical, 8)
}
