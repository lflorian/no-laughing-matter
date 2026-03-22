//
//  VisualizationViewModel.swift
//  no laughing matter
//
//  Created by Claude on 21.03.26.
//

import Foundation
import SwiftData

@MainActor
@Observable
final class VisualizationViewModel {

    var events: [HumorEvent] = []
    var isLoading = false
    var errorMessage: String?
    var parsedCount: Int = 0
    var classifiedCount: Int = 0

    // MARK: Who Laughs

    var laughingFraktionCounts: [(party: String, count: Int)] {
        var counts: [String: Int] = [:]
        for event in events {
            for party in event.laughingParties {
                let p = normalizeParty(party)
                guard !p.isEmpty else { continue }
                counts[p, default: 0] += 1
            }
        }
        return counts.map { (party: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    /// Laughing counts normalized by average faction seat count across loaded Wahlperioden.
    /// Result is "laugh events per seat", allowing comparison independent of faction size.
    var laughingFraktionCountsNormalized: [(party: String, rate: Double)] {
        let wahlperioden = Set(events.map(\.wahlperiode))
        return laughingFraktionCounts.compactMap { item in
            let seats = CoalitionData.averageSeats(for: item.party, in: wahlperioden)
            guard seats > 0 else { return nil }
            return (party: item.party, rate: Double(item.count) / seats)
        }
        .sorted { $0.rate > $1.rate }
    }

    // MARK: Who Laughs (Individuals)

    var laughingIndividualCounts: [(name: String, party: String?, count: Int)] {
        var counts: [String: (party: String?, count: Int)] = [:]
        for event in events {
            for individual in event.laughingIndividuals {
                let name = individual.name.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { continue }
                let party = individual.party.map { normalizeParty($0) }
                if counts[name] == nil {
                    counts[name] = (party, 1)
                } else {
                    counts[name]!.count += 1
                }
            }
        }
        return counts.map { (name: $0.key, party: $0.value.party, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    // MARK: Who Triggers

    var speakerFraktionCounts: [(party: String, count: Int)] {
        var counts: [String: Int] = [:]
        for event in events {
            if let raw = event.speakerParty, !raw.isEmpty {
                counts[normalizeParty(raw), default: 0] += 1
            }
        }
        return counts.map { (party: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    /// Triggering counts normalized by average faction seat count across loaded Wahlperioden.
    var speakerFraktionCountsNormalized: [(party: String, rate: Double)] {
        let wahlperioden = Set(events.map(\.wahlperiode))
        return speakerFraktionCounts.compactMap { item in
            let seats = CoalitionData.averageSeats(for: item.party, in: wahlperioden)
            guard seats > 0 else { return nil }
            return (party: item.party, rate: Double(item.count) / seats)
        }
        .sorted { $0.rate > $1.rate }
    }

    var speakerIndividualCounts: [(name: String, party: String?, count: Int)] {
        var counts: [String: (party: String?, count: Int)] = [:]
        for event in events {
            let name = event.speakerName.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            let party = event.speakerParty.map { normalizeParty($0) }
            if counts[name] == nil {
                counts[name] = (party, 1)
            } else {
                counts[name]!.count += 1
            }
        }
        return counts.map { (name: $0.key, party: $0.value.party, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    // MARK: Cross-Party

    var crossPartyMatrix: [(speaker: String, laugher: String, count: Int)] {
        var matrix: [String: [String: Int]] = [:]
        for event in events {
            guard let raw = event.speakerParty, !raw.isEmpty else { continue }
            let sp = normalizeParty(raw)
            for laugher in event.laughingParties {
                let l = normalizeParty(laugher)
                guard !l.isEmpty else { continue }
                matrix[sp, default: [:]][l, default: 0] += 1
            }
        }
        var result: [(speaker: String, laugher: String, count: Int)] = []
        for (sp, laughers) in matrix {
            for (l, count) in laughers {
                result.append((speaker: sp, laugher: l, count: count))
            }
        }
        return result
    }

    private static let knownParties: Set<String> = [
        "CDU/CSU", "SPD", "BÜNDNIS 90/DIE GRÜNEN", "FDP", "AfD", "Die Linke", "BSW", "SSW", "Fraktionslos"
    ]

    var matrixParties: [String] {
        var totals: [String: Int] = [:]
        for entry in crossPartyMatrix {
            totals[entry.speaker, default: 0] += entry.count
            totals[entry.laugher, default: 0] += entry.count
        }
        return totals
            .filter { Self.knownParties.contains($0.key) }
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map(\.key)
            .sorted()
    }

    // MARK: Humor Types

    var humorTypeCounts: [(type: HumorType, count: Int)] {
        var counts: [HumorType: Int] = [:]
        for event in events { counts[event.humorType, default: 0] += 1 }
        return HumorType.allCases.compactMap { type in
            guard let count = counts[type], count > 0 else { return nil }
            return (type: type, count: count)
        }
    }

    var humorTypeByWahlperiode: [(wahlperiode: Int, type: HumorType, count: Int)] {
        var matrix: [Int: [HumorType: Int]] = [:]
        for event in events {
            matrix[event.wahlperiode, default: [:]][event.humorType, default: 0] += 1
        }
        var result: [(wahlperiode: Int, type: HumorType, count: Int)] = []
        for (wp, types) in matrix.sorted(by: { $0.key < $1.key }) {
            for type in HumorType.allCases {
                if let count = types[type], count > 0 {
                    result.append((wahlperiode: wp, type: type, count: count))
                }
            }
        }
        return result
    }

    var humorTypeByParty: [(party: String, type: HumorType, count: Int)] {
        var counts: [String: [HumorType: Int]] = [:]
        for event in events {
            for party in event.laughingParties {
                let p = normalizeParty(party)
                guard !p.isEmpty else { continue }
                counts[p, default: [:]][event.humorType, default: 0] += 1
            }
        }
        let topParties = counts.map { (party: $0.key, total: $0.value.values.reduce(0, +)) }
            .sorted { $0.total > $1.total }
            .prefix(8).map(\.party)
        var result: [(party: String, type: HumorType, count: Int)] = []
        for party in topParties {
            for type in HumorType.allCases {
                if let count = counts[party]?[type], count > 0 {
                    result.append((party: party, type: type, count: count))
                }
            }
        }
        return result
    }

    var humorTypeTemporalData: [(month: Date, type: HumorType, count: Int)] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        var counts: [Date: [HumorType: Int]] = [:]
        let calendar = Calendar.current

        for event in events {
            let date: Date?
            if event.datum.contains(".") {
                formatter.dateFormat = "dd.MM.yyyy"
                date = formatter.date(from: event.datum)
            } else {
                formatter.dateFormat = "yyyy-MM-dd"
                date = formatter.date(from: event.datum)
            }
            guard let d = date else { continue }
            let components = calendar.dateComponents([.year, .month], from: d)
            guard let monthDate = calendar.date(from: components) else { continue }
            counts[monthDate, default: [:]][event.humorType, default: 0] += 1
        }

        var result: [(month: Date, type: HumorType, count: Int)] = []
        for (month, types) in counts.sorted(by: { $0.key < $1.key }) {
            for type in HumorType.allCases {
                result.append((month: month, type: type, count: types[type] ?? 0))
            }
        }
        return result
    }

    // MARK: Intentions

    var intentionCounts: [(intention: HumorIntention, count: Int)] {
        var counts: [HumorIntention: Int] = [:]
        for event in events {
            if let intention = event.classification?.primaryIntention {
                counts[intention, default: 0] += 1
            }
        }
        return counts.map { (intention: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    var intentionByFraktion: [(party: String, intention: HumorIntention, count: Int)] {
        var matrix: [String: [HumorIntention: Int]] = [:]
        for event in events {
            guard let intention = event.classification?.primaryIntention else { continue }
            for party in event.laughingParties {
                let p = normalizeParty(party)
                guard !p.isEmpty else { continue }
                matrix[p, default: [:]][intention, default: 0] += 1
            }
        }
        let topParties = matrix
            .map { (party: $0.key, total: $0.value.values.reduce(0, +)) }
            .sorted { $0.total > $1.total }
            .prefix(8)
            .map(\.party)

        var result: [(party: String, intention: HumorIntention, count: Int)] = []
        for party in topParties {
            for intention in HumorIntention.allCases {
                let count = matrix[party, default: [:]][intention, default: 0]
                if count > 0 {
                    result.append((party: party, intention: intention, count: count))
                }
            }
        }
        return result
    }

    var intentionByWahlperiode: [(wahlperiode: Int, intention: HumorIntention, count: Int)] {
        var matrix: [Int: [HumorIntention: Int]] = [:]
        for event in events {
            guard let intention = event.classification?.primaryIntention else { continue }
            matrix[event.wahlperiode, default: [:]][intention, default: 0] += 1
        }
        var result: [(wahlperiode: Int, intention: HumorIntention, count: Int)] = []
        for (wp, intentions) in matrix.sorted(by: { $0.key < $1.key }) {
            for intention in HumorIntention.allCases {
                if let count = intentions[intention], count > 0 {
                    result.append((wahlperiode: wp, intention: intention, count: count))
                }
            }
        }
        return result
    }

    // MARK: Gender

    var genderKnownCount: Int {
        events.filter { $0.speakerGender != nil }.count
    }

    var genderOverallCounts: [(gender: SpeakerDirectory.Gender, count: Int)] {
        var counts: [SpeakerDirectory.Gender: Int] = [:]
        for event in events {
            guard let g = event.speakerGender else { continue }
            counts[g, default: 0] += 1
        }
        return counts.map { (gender: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    /// Per-Wahlperiode: baseline female share (from MdB Stammdaten) vs observed female share (from humor events)
    var genderBaselineComparison: [(wahlperiode: Int, baselineFemalePercent: Double, observedFemalePercent: Double, totalMdB: Int, femaleMdB: Int, totalEvents: Int, femaleEvents: Int)] {
        // Group events by Wahlperiode
        var eventCounts: [Int: (male: Int, female: Int)] = [:]
        for event in events {
            guard let g = event.speakerGender else { continue }
            switch g {
            case .male: eventCounts[event.wahlperiode, default: (0, 0)].male += 1
            case .female: eventCounts[event.wahlperiode, default: (0, 0)].female += 1
            }
        }

        let dir = SpeakerDirectory.shared
        return eventCounts.keys.sorted().compactMap { wp in
            let composition = dir.genderComposition(forWahlperiode: wp)
            let totalMdB = composition.male + composition.female
            guard totalMdB > 0 else { return nil }
            let evts = eventCounts[wp]!
            let totalEvents = evts.male + evts.female
            guard totalEvents > 0 else { return nil }
            let baselinePct = Double(composition.female) / Double(totalMdB) * 100.0
            let observedPct = Double(evts.female) / Double(totalEvents) * 100.0
            return (wahlperiode: wp, baselineFemalePercent: baselinePct, observedFemalePercent: observedPct,
                    totalMdB: totalMdB, femaleMdB: composition.female,
                    totalEvents: totalEvents, femaleEvents: evts.female)
        }
    }

    var genderProportionByParty: [(party: String, femaleShare: Double, maleCount: Int, femaleCount: Int)] {
        var male: [String: Int] = [:]
        var female: [String: Int] = [:]
        for event in events {
            guard let g = event.speakerGender,
                  let raw = event.speakerParty, !raw.isEmpty else { continue }
            let p = normalizeParty(raw)
            switch g {
            case .male: male[p, default: 0] += 1
            case .female: female[p, default: 0] += 1
            }
        }
        let allParties = Set(male.keys).union(female.keys)
        return allParties.map { party in
            let m = male[party] ?? 0
            let f = female[party] ?? 0
            let share = (m + f) > 0 ? Double(f) / Double(m + f) * 100.0 : 0
            return (party: party, femaleShare: share, maleCount: m, femaleCount: f)
        }
        .sorted { ($0.maleCount + $0.femaleCount) > ($1.maleCount + $1.femaleCount) }
        .prefix(8).map { $0 }
    }

    var genderByParty: [(party: String, gender: SpeakerDirectory.Gender, count: Int)] {
        var counts: [String: [SpeakerDirectory.Gender: Int]] = [:]
        for event in events {
            guard let g = event.speakerGender,
                  let raw = event.speakerParty, !raw.isEmpty else { continue }
            let p = normalizeParty(raw)
            counts[p, default: [:]][g, default: 0] += 1
        }
        let topParties = counts.map { (party: $0.key, total: $0.value.values.reduce(0, +)) }
            .sorted { $0.total > $1.total }
            .prefix(8).map(\.party)
        var result: [(party: String, gender: SpeakerDirectory.Gender, count: Int)] = []
        for party in topParties {
            for gender in [SpeakerDirectory.Gender.male, .female] {
                if let count = counts[party]?[gender], count > 0 {
                    result.append((party: party, gender: gender, count: count))
                }
            }
        }
        return result
    }

    var genderByIntention: [(intention: HumorIntention, gender: SpeakerDirectory.Gender, count: Int)] {
        var counts: [HumorIntention: [SpeakerDirectory.Gender: Int]] = [:]
        for event in events {
            guard let g = event.speakerGender,
                  let intention = event.classification?.primaryIntention else { continue }
            counts[intention, default: [:]][g, default: 0] += 1
        }
        var result: [(intention: HumorIntention, gender: SpeakerDirectory.Gender, count: Int)] = []
        for intention in HumorIntention.allCases {
            for gender in [SpeakerDirectory.Gender.male, .female] {
                if let count = counts[intention]?[gender], count > 0 {
                    result.append((intention: intention, gender: gender, count: count))
                }
            }
        }
        return result
    }

    var genderTemporalData: [(month: Date, gender: SpeakerDirectory.Gender, count: Int)] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        var counts: [Date: [SpeakerDirectory.Gender: Int]] = [:]
        let calendar = Calendar.current

        for event in events {
            guard let g = event.speakerGender else { continue }
            let date: Date?
            if event.datum.contains(".") {
                formatter.dateFormat = "dd.MM.yyyy"
                date = formatter.date(from: event.datum)
            } else {
                formatter.dateFormat = "yyyy-MM-dd"
                date = formatter.date(from: event.datum)
            }
            guard let d = date else { continue }
            let components = calendar.dateComponents([.year, .month], from: d)
            guard let monthDate = calendar.date(from: components) else { continue }
            counts[monthDate, default: [:]][g, default: 0] += 1
        }
        var result: [(month: Date, gender: SpeakerDirectory.Gender, count: Int)] = []
        for (month, genderCounts) in counts.sorted(by: { $0.key < $1.key }) {
            for gender in [SpeakerDirectory.Gender.male, .female] {
                if let count = genderCounts[gender], count > 0 {
                    result.append((month: month, gender: gender, count: count))
                }
            }
        }
        return result
    }

    // MARK: Age

    var ageKnownCount: Int {
        events.filter { $0.speakerAge != nil }.count
    }

    /// Distribution of humor events by age group
    var ageDistribution: [(group: String, count: Int)] {
        var counts: [String: Int] = [:]
        for event in events {
            guard let age = event.speakerAge, age > 0 && age < 120 else { continue }
            let group = SpeakerDirectory.ageGroupLabel(for: age)
            counts[group, default: 0] += 1
        }
        return SpeakerDirectory.ageGroupOrder.compactMap { group in
            guard let count = counts[group], count > 0 else { return nil }
            return (group: group, count: count)
        }
    }

    /// Per-Wahlperiode: baseline age distribution (from Stammdaten) vs observed (from humor events)
    var ageBaselineComparison: [(wahlperiode: Int, groups: [(group: String, baselinePercent: Double, observedPercent: Double)], totalMdB: Int, totalEvents: Int)] {
        let dir = SpeakerDirectory.shared

        // Group observed events by Wahlperiode and age group
        var observed: [Int: [String: Int]] = [:]
        for event in events {
            guard let age = event.speakerAge, age > 0 && age < 120 else { continue }
            let group = SpeakerDirectory.ageGroupLabel(for: age)
            observed[event.wahlperiode, default: [:]][group, default: 0] += 1
        }

        return observed.keys.sorted().compactMap { wp in
            let baseline = dir.ageComposition(forWahlperiode: wp)
            let totalMdB = baseline.values.reduce(0, +)
            guard totalMdB > 0 else { return nil }
            let obs = observed[wp]!
            let totalEvents = obs.values.reduce(0, +)
            guard totalEvents > 0 else { return nil }

            let groups = SpeakerDirectory.ageGroupOrder.map { group in
                let bCount = baseline[group] ?? 0
                let oCount = obs[group] ?? 0
                let bPct = Double(bCount) / Double(totalMdB) * 100.0
                let oPct = Double(oCount) / Double(totalEvents) * 100.0
                return (group: group, baselinePercent: bPct, observedPercent: oPct)
            }

            return (wahlperiode: wp, groups: groups, totalMdB: totalMdB, totalEvents: totalEvents)
        }
    }

    /// Average age by party (top 8)
    var ageByParty: [(party: String, averageAge: Double, count: Int)] {
        var sums: [String: (total: Int, count: Int)] = [:]
        for event in events {
            guard let age = event.speakerAge, age > 0 && age < 120,
                  let raw = event.speakerParty, !raw.isEmpty else { continue }
            let p = normalizeParty(raw)
            sums[p, default: (0, 0)].total += age
            sums[p, default: (0, 0)].count += 1
        }
        return sums.map { (party: $0.key, averageAge: Double($0.value.total) / Double($0.value.count), count: $0.value.count) }
            .sorted { $0.count > $1.count }
            .prefix(8).map { $0 }
    }

    /// Age group distribution by party (top 8 parties)
    var ageGroupByParty: [(party: String, group: String, count: Int)] {
        var counts: [String: [String: Int]] = [:]
        for event in events {
            guard let age = event.speakerAge, age > 0 && age < 120,
                  let raw = event.speakerParty, !raw.isEmpty else { continue }
            let p = normalizeParty(raw)
            let group = SpeakerDirectory.ageGroupLabel(for: age)
            counts[p, default: [:]][group, default: 0] += 1
        }
        let topParties = counts.map { (party: $0.key, total: $0.value.values.reduce(0, +)) }
            .sorted { $0.total > $1.total }
            .prefix(8).map(\.party)
        var result: [(party: String, group: String, count: Int)] = []
        for party in topParties {
            for group in SpeakerDirectory.ageGroupOrder {
                if let count = counts[party]?[group], count > 0 {
                    result.append((party: party, group: group, count: count))
                }
            }
        }
        return result
    }

    /// Age group by humor intention (classified events only)
    var ageByIntention: [(intention: HumorIntention, group: String, count: Int)] {
        var counts: [HumorIntention: [String: Int]] = [:]
        for event in events {
            guard let age = event.speakerAge, age > 0 && age < 120,
                  let intention = event.classification?.primaryIntention else { continue }
            let group = SpeakerDirectory.ageGroupLabel(for: age)
            counts[intention, default: [:]][group, default: 0] += 1
        }
        var result: [(intention: HumorIntention, group: String, count: Int)] = []
        for intention in HumorIntention.allCases {
            for group in SpeakerDirectory.ageGroupOrder {
                if let count = counts[intention]?[group], count > 0 {
                    result.append((intention: intention, group: group, count: count))
                }
            }
        }
        return result
    }

    /// Average speaker age over time (monthly)
    var ageTemporalData: [(month: Date, averageAge: Double)] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        var sums: [Date: (total: Int, count: Int)] = [:]
        let calendar = Calendar.current

        for event in events {
            guard let age = event.speakerAge, age > 0 && age < 120 else { continue }
            let date: Date?
            if event.datum.contains(".") {
                formatter.dateFormat = "dd.MM.yyyy"
                date = formatter.date(from: event.datum)
            } else {
                formatter.dateFormat = "yyyy-MM-dd"
                date = formatter.date(from: event.datum)
            }
            guard let d = date else { continue }
            let components = calendar.dateComponents([.year, .month], from: d)
            guard let monthDate = calendar.date(from: components) else { continue }
            sums[monthDate, default: (0, 0)].total += age
            sums[monthDate, default: (0, 0)].count += 1
        }
        return sums.map { (month: $0.key, averageAge: Double($0.value.total) / Double($0.value.count)) }
            .sorted { $0.month < $1.month }
    }

    // MARK: Temporal

    var temporalData: [(month: Date, count: Int)] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        var counts: [Date: Int] = [:]
        let calendar = Calendar.current

        for event in events {
            let date: Date?
            if event.datum.contains(".") {
                formatter.dateFormat = "dd.MM.yyyy"
                date = formatter.date(from: event.datum)
            } else {
                formatter.dateFormat = "yyyy-MM-dd"
                date = formatter.date(from: event.datum)
            }
            guard let d = date else { continue }
            let components = calendar.dateComponents([.year, .month], from: d)
            guard let monthDate = calendar.date(from: components) else { continue }
            counts[monthDate, default: 0] += 1
        }
        return counts.map { (month: $0.key, count: $0.value) }
            .sorted { $0.month < $1.month }
    }

    // MARK: Government vs. Opposition

    /// Humor frequency grouped by political role per Wahlperiode
    var govOppFrequency: [(wahlperiode: Int, role: PoliticalRole, count: Int)] {
        var counts: [Int: [PoliticalRole: Int]] = [:]
        for event in events {
            guard let raw = event.speakerParty, !raw.isEmpty else { continue }
            let party = normalizeParty(raw)
            let role = CoalitionData.role(for: party, in: event.wahlperiode)
            guard role != .other else { continue }
            counts[event.wahlperiode, default: [:]][role, default: 0] += 1
        }
        var result: [(wahlperiode: Int, role: PoliticalRole, count: Int)] = []
        for (wp, roles) in counts.sorted(by: { $0.key < $1.key }) {
            for role in [PoliticalRole.government, .opposition] {
                if let count = roles[role], count > 0 {
                    result.append((wahlperiode: wp, role: role, count: count))
                }
            }
        }
        return result
    }

    /// Intention distribution by political role per Wahlperiode (classified events only)
    var govOppIntention: [(wahlperiode: Int, role: PoliticalRole, intention: HumorIntention, count: Int)] {
        var counts: [Int: [PoliticalRole: [HumorIntention: Int]]] = [:]
        for event in events {
            guard let intention = event.classification?.primaryIntention,
                  let raw = event.speakerParty, !raw.isEmpty else { continue }
            let party = normalizeParty(raw)
            let role = CoalitionData.role(for: party, in: event.wahlperiode)
            guard role != .other else { continue }
            counts[event.wahlperiode, default: [:]][role, default: [:]][intention, default: 0] += 1
        }
        var result: [(wahlperiode: Int, role: PoliticalRole, intention: HumorIntention, count: Int)] = []
        for (wp, roles) in counts.sorted(by: { $0.key < $1.key }) {
            for role in [PoliticalRole.government, .opposition] {
                for intention in HumorIntention.allCases {
                    if let count = roles[role]?[intention], count > 0 {
                        result.append((wahlperiode: wp, role: role, intention: intention, count: count))
                    }
                }
            }
        }
        return result
    }

    /// Humor type (Heiterkeit vs. Lachen) by political role per Wahlperiode
    var govOppHumorType: [(wahlperiode: Int, role: PoliticalRole, type: HumorType, count: Int)] {
        var counts: [Int: [PoliticalRole: [HumorType: Int]]] = [:]
        for event in events {
            guard let raw = event.speakerParty, !raw.isEmpty else { continue }
            let party = normalizeParty(raw)
            let role = CoalitionData.role(for: party, in: event.wahlperiode)
            guard role != .other else { continue }
            counts[event.wahlperiode, default: [:]][role, default: [:]][event.humorType, default: 0] += 1
        }
        var result: [(wahlperiode: Int, role: PoliticalRole, type: HumorType, count: Int)] = []
        for (wp, roles) in counts.sorted(by: { $0.key < $1.key }) {
            for role in [PoliticalRole.government, .opposition] {
                for type in HumorType.allCases {
                    if let count = roles[role]?[type], count > 0 {
                        result.append((wahlperiode: wp, role: role, type: type, count: count))
                    }
                }
            }
        }
        return result
    }

    // MARK: Load

    func load(context: ModelContext) {
        isLoading = true
        errorMessage = nil
        do {
            let allDescriptor = FetchDescriptor<HumorEvent>()
            let allEvents = try context.fetch(allDescriptor)
            parsedCount = allEvents.count
            classifiedCount = allEvents.filter { $0.classification != nil }.count
            events = allEvents
        } catch {
            errorMessage = error.localizedDescription
            events = []
        }
        isLoading = false
    }
}
