//
//  LLMClassification.swift
//  no laughing matter
//
//  Created by Florian Lammert on 13.01.26.
//

import Foundation

struct LLMClassification: Codable {
    let primaryIntention: HumorIntention
    let secondaryIntention: HumorIntention?
    let confidenceRating: Int
    let reasoning: String?
}

/// Humor function classification based on Avner Ziv's (1984) five-functions model,
/// extended with an unclear fallback for insufficient context.
enum HumorIntention: String, Codable, CaseIterable {
    case aggressive
    case social
    case defensive
    case intellectual
    case sexual
    case unclear
}
