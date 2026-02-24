//
//  IntelligenceManager.swift
//  no laughing matter
//
//  Created by Florian Lammert on 13.01.26.
//

import Foundation
import FoundationModels

final class IntelligenceManager {

    static let shared = IntelligenceManager()
    private init() {}

    /// System instructions include category definitions so they're sent once per session, not per event
    let instructions = """
        You classify humor intentions in German Bundestag protocols. Categories:
        irony: Sarcastic/ironic agreement masking criticism
        ridicule: Mocking to undermine or delegitimize
        distance: Dismissing a position as unserious
        solidarity: Reinforcing in-group cohesion
        strategic_disruption: Interrupting or destabilizing a speaker
        tension_relief: Releasing emotional tension
        self_affirmation: Reinforcing own authority or success
        accidental: Unintended humor from mistakes or slips
        unclear: Insufficient information to classify
        Consider who laughed at whom, party dynamics, and political context. Be concise in reasoning.
        """

    private(set) lazy var session = LanguageModelSession(instructions: instructions)

    /// For the test view — uses the shared session
    func analyzeEvent(_ eventDescription: String) async throws -> LLMClassification {
        let prompt = "Classify this humor event:\n\(eventDescription)"
        let response = try await session.respond(
            to: prompt,
            generating: LLMClassification.self
        )
        return response.content
    }

    // MARK: - Batch Classification

    /// Creates a dedicated session for batch processing (reused across all events in the batch)
    func createBatchSession() -> LanguageModelSession {
        LanguageModelSession(instructions: instructions)
    }

    /// Classify a single event using a provided session
    nonisolated func analyzeEvent(_ event: HumorEvent, using session: LanguageModelSession) async throws -> LLMClassification {
        let prompt = buildPrompt(for: event)
        let response = try await session.respond(
            to: prompt,
            generating: LLMClassification.self
        )
        return response.content
    }

    nonisolated private func buildPrompt(for event: HumorEvent) -> String {
        // Compact prompt — categories are already in session instructions
        var p = "Speaker: \(event.speakerName)"
        if let party = event.speakerParty { p += " (\(party))" }
        if let role = event.speakerRole { p += " [\(role)]" }
        p += "\nWP\(event.wahlperiode)/Sitzung \(event.sitzungsnummer), \(event.datum)"
        if let agenda = event.agendaItem { p += "\nTOP: \(agenda)" }
        p += "\n\nText: \(event.precedingText)"
        p += "\nComment: \(event.rawComment)"
        if let following = event.followingText { p += "\nAfter: \(following)" }
        if !event.laughingParties.isEmpty {
            p += "\nLaughing: \(event.laughingParties.joined(separator: ", "))"
        }
        if !event.laughingIndividuals.isEmpty {
            let names = event.laughingIndividuals.map { ind in ind.party.map { "\(ind.name) [\($0)]" } ?? ind.name }
            p += "\nIndividuals: \(names.joined(separator: ", "))"
        }
        return p
    }
}
