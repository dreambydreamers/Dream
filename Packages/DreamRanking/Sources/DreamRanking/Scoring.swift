import Foundation

/// A candidate paired with its score. Internal working type of the pipeline.
struct Scored: Equatable {
    let candidate: DreamCandidate
    let breakdown: ScoreBreakdown
}

enum Scoring {

    /// Scores one candidate for one viewer. Pure: inputs are the candidate,
    /// the viewer, the config, and `now` — nothing else.
    ///
    /// Note what is NOT here: impressions, distinct viewers, watch counts.
    /// Exposure data influences fairness-slot selection (FairnessPass), never
    /// the quality score; watch behavior only appears as the VIEWER's own
    /// `categoryAffinity`.
    static func score(
        _ c: DreamCandidate,
        viewer: ViewerProfile,
        config: RankingConfig,
        now: Date
    ) -> ScoreBreakdown {
        // Help-type overlap — the heaviest term: can this viewer actually help?
        let matchedTypes = c.helpTypes.intersection(viewer.helpTypesOffered).count
        let helpTypeOverlap =
            Double(min(matchedTypes, config.helpTypeMatchCap)) * config.helpTypeMatchWeight

        // Literal skill-tag overlap (viewer free-text skills vs dream tags).
        let matchedSkills = c.helpTags.filter { viewer.skills.contains(Normalize.token($0)) }.count
        let skillOverlap =
            Double(min(matchedSkills, config.skillOverlapCap)) * config.skillOverlapWeight

        // Category affinity: learned from own engagement, floored by declared interest.
        var affinity = viewer.categoryAffinity[c.category] ?? 0
        if viewer.categoriesOfInterest.contains(c.category) {
            affinity = max(affinity, config.declaredInterestAffinity)
        }
        let categoryAffinity = min(max(affinity, 0), 1) * config.categoryAffinityWeight

        // Geo: exact normalized-location match (no geocoding yet — v1 tiering).
        let geoProximity: Double
        if let viewerLoc = viewer.location,
           let dreamLoc = c.location.map(Normalize.token),
           !dreamLoc.isEmpty, viewerLoc == dreamLoc {
            geoProximity = config.geoMatchWeight
        } else {
            geoProximity = 0
        }

        // Stage vs. supporter preference (empty preference = neutral).
        let stageMatch = viewer.preferredStages.contains(c.stage)
            ? config.stagePreferenceWeight : 0

        // Under-served boost: grows as the dream ages while offers stay low.
        // Additive only — a well-supported dream loses nothing.
        let ageDays = max(0, now.timeIntervalSince(c.createdAt) / 86_400)
        let ageRamp = min(ageDays / config.underServedAgeRampDays, 1)
        let offerDecay = max(0, 1 - Double(c.offersReceived) / config.underServedOfferSaturation)
        let underServedBoost = config.underServedMaxBoost * ageRamp * offerDecay

        // Mild recency so brand-new posts get a first look.
        let ageHours = max(0, now.timeIntervalSince(c.createdAt) / 3_600)
        let recency = config.recencyMaxBonus * pow(0.5, ageHours / config.recencyHalfLifeHours)

        return ScoreBreakdown(
            helpTypeOverlap: helpTypeOverlap,
            skillOverlap: skillOverlap,
            categoryAffinity: categoryAffinity,
            geoProximity: geoProximity,
            stageMatch: stageMatch,
            underServedBoost: underServedBoost,
            recency: recency
        )
    }

    /// Deterministic tie-break so equal-scored items order stably per (id, seed)
    /// without global randomness.
    static func tieBreak(_ id: UUID, seed: UInt64) -> UInt64 {
        let bytes = withUnsafeBytes(of: id.uuid) { raw in
            raw.load(as: UInt64.self) ^ raw.load(fromByteOffset: 8, as: UInt64.self)
        }
        var z = bytes &+ seed &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
