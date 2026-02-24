//
//  LLMClassification.swift
//  no laughing matter
//
//  Created by Florian Lammert on 13.01.26.
//

import Foundation
import FoundationModels

@Generable
struct LLMClassification: Codable {
    @Guide(description: "Brief reasoning: key signals and political context behind the classification")
    let reasoning: String
    @Guide(description: "The primary intention of the people laughing")
    let humorIntention: HumorIntention
    @Guide(description: "Confidence 1-10", .range(1...10))
    let confidenceRating: Int
}

@Generable
enum HumorIntention: String, Codable, CaseIterable {
    case irony
    case ridicule
    case distance
    case solidarity
    case strategic_disruption
    case tension_relief
    case self_affirmation
    case accidental
    case unclear
}
