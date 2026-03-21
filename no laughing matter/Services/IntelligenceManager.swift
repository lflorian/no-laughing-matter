//
//  IntelligenceManager.swift
//  no laughing matter
//
//  Created by Florian Lammert on 13.01.26.
//

import Foundation

final class IntelligenceManager {

    static let shared = IntelligenceManager()
    private init() {}

    let client = ClaudeAPIClient()
    
    /// Prompt version: 3.0 (2026-03-21)
    let instructions = """
        Du klassifizierst die Funktion von Humorereignissen in Protokollen des Deutschen Bundestags. Klassifiziere auf der Ebene der Funktion, nicht der rhetorischen Form. Berücksichtige, wer über wen lacht, die Fraktionsdynamiken und den politischen Kontext in der Bundesrepublik Deutschland.
        
        # Kategorien
        aggressive: Humor als Abwertung/Konfrontation. Spott, Häme oder Ridicule mit dem Ziel, den Gegner herabzusetzen, lächerlich zu machen oder die eigene Position auf dessen Kosten zu stärken.
            Beispiel: Eine Fraktion lacht eine Aussage eines politischen Wettstreiters aus.
        
        social: Humor als Gruppenmarkierung. Einerseits stärkt gemeinsames Lachen die Gruppenzugehörigkeit und Solidarität innerhalb einer Fraktion (Bonding), andererseits grenzt genau dieses Lachen Fremdgruppen ab (Bounding).
            Beispiel: Zustimmendes Lachen aus der Fraktion des Redners, Koalitionsfraktionen oder gleichgesinnten Fraktionen, das gleichzeitig eine gelungene Bemerkung markiert sowie Distanz zum Gegner markiert. Im Gegensatz zu 'aggressive' richtet sich der Humor nicht primär gegen jemanden, sondern stärkt das Wir-Gefühl. 
        
        defensive: Humor als Schutzmechanismus. Einerseits möglich als Galgenhumor, um in bedrohlichen oder peinlichen Situationen durch Humor Distanz zu gewinnen und Handlungsfähigkeit zu bewahren. Andererseits möglich als Selbstironie, bei welcher bewusstes Scherzen über eigene Schwächen, Fehler oder Misserfolge potenzieller Kritik die Angriffsfläche nehmen sowie Sympathie erzeugen soll.
            Beispiel: Ein Redner kommentiert einen eigenen Versprecher oder seine Zeitüberschreitung mit einem Scherz und nimmt politischen Wettstreitern so die Initiative, um sich über ihn zu belustigen.
        
        intellectual: Humor, der auf kognitiver Raffinesse beruht. Das Publikum muss eine kognitive Leistung erbringen, um die Pointe zu entschlüsseln, worin das Vergnügen liegt. Mögliche Formen sind Wortspiele, Doppeldeutigkeiten, ironische Verweise, überraschende logische Wendungen, geistreiche Analogien oder Ironie (der Sprecher sagt das Gegenteil von dem, was er meint). Im Gegensatz zu 'aggressive' liegt die Pointe primär im sprachlichen oder logischen Kunstgriff und nicht in der Herabsetzung einer Person.
            Beispiel: Ein Wortspiel auf Kosten eines Konkurrenten, welches eine kognitive Leistung zum Entschlüsseln erfordert, was den Kern der Komik ausmacht. 
        
        sexual: Humor, der Tabus rund um Sexualität, Körperlichkeit oder Intimität adressiert. Spannungen aus gesellschaftlichen Konventionen werden in einer sozial akzeptierten Form abgebaut.
            Beispiel: Ein Redner setzt eine Pointe über Körperlichkeit oder Sexualität, deren Komik ohne den Tabubruch nicht funktionieren würde. Hierzu gehören beispielsweise Anspielungen oder Doppeldeutigkeiten.
        
        unclear: Kontext für eine zuverlässige Klassifikation unzureichend. Besser unclear als eine unsichere Zuordnung.
        
        # Few-Shot-Beispiele
        ## Beispiel 1
        Redner: Steffen Kotré (AfD)
        Kontext: Kotré spricht über Small Modular Reactors (SMR) als Zukunftstechnologie.
        Kommentar: (Dr. Ralf Stegner [SPD]: 'SMR' steht für 'schlechtmöglichste Rede'! – Heiterkeit bei Abgeordneten der SPD und des BÜNDNISSES 90/DIE GRÜNEN)
        Klassifikation: primaryIntention: intellectual; secondaryIntention: aggressive; reasoning: Stegner macht ein Akronym-Wortspiel – er deutet die Abkürzung 'SMR' um. Der Kommentar erfordert Hintergrundwissen, um ihn als Witz zu verstehen. Sekundär ist der Witz aggressiv, weil er Kotrés Rede abwertet. 
        
        ## Beispiel 2 
        Redner: Kathrin Gebel (Die Linke)
        Kontext: Gebel spricht in einer Debatte über Feminismus und antwortet auf Reichardt (AfD)
        Redekontext: „die Klitoris hat 3.000 Nervenenden, und Sie sind trotzdem empfindlicher."
        Kommentar: (Heiterkeit und Beifall bei der Linken und dem BÜNDNIS 90/DIE GRÜNEN sowie bei Abgeordneten der SPD – Martin Reichardt [AfD]: Was?)
        Klassifikation: primaryIntention: sexual; secondaryIntention: aggressive; reasoning: Der Witz adressiert direkt ein körperliches Tabu-Thema (Genitalien) und nutzt es, um eine Pointe zu setzen (sexuelle Funktion). Sekundär ist der Witz aggressiv, weil er Reichardt direkt herabsetzt (er sei empfindlicher als ein Organ mit 3.000 Nervenenden). Ohne den Tabubruch würde der Witz nicht funktionieren, daher ist er primär sexual.
        """

    /// For the test view
    func analyzeEvent(_ eventDescription: String) async throws -> LLMClassification {
        let prompt = "Klassifiziere dieses Humorereignis:\n\(eventDescription)"
        return try await client.classify(systemPrompt: instructions, userPrompt: prompt)
    }

    // MARK: - Batch Classification

    /// Classify a single event
    func analyzeEvent(_ event: HumorEvent) async throws -> LLMClassification {
        let prompt = buildPrompt(for: event)
        return try await client.classify(systemPrompt: instructions, userPrompt: prompt)
    }

    func buildPrompt(for event: HumorEvent) -> String {
        // Compact prompt — categories are already in system instructions
        var p = "Redner: \(event.speakerName)"
        if let party = event.speakerParty { p += " (\(party))" }
        if let role = event.speakerRole { p += " [\(role)]" }
        p += "\nWP\(event.wahlperiode)/Sitzung \(event.sitzungsnummer), \(event.datum)"
        if let agenda = event.agendaItem { p += "\nTOP: \(agenda)" }
        p += "\n\nText: \(event.precedingText)"
        p += "\nKommentar: \(event.rawComment)"
        if let following = event.followingText { p += "\nDanach: \(following)" }
        if !event.laughingParties.isEmpty {
            p += "\nLachende: \(event.laughingParties.joined(separator: ", "))"
        }
        if !event.laughingIndividuals.isEmpty {
            let names = event.laughingIndividuals.map { ind in ind.party.map { "\(ind.name) [\($0)]" } ?? ind.name }
            p += "\nEinzelpersonen: \(names.joined(separator: ", "))"
        }
        return p
    }
}
