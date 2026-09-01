import Foundation

/// Builds the per-item explanation string ("needs iOS development — you offer
/// iOS development") that the UI can surface later. Priority: the most
/// actionable match first (literal skill, then help type), then social/local
/// context, with an under-served note appended when it applies.
enum Reasons {

    static func build(
        for candidate: DreamCandidate,
        breakdown: ScoreBreakdown,
        viewer: ViewerProfile,
        isFairnessSlot: Bool
    ) -> String {
        var primary: String?

        if let tag = candidate.helpTags.first(where: { viewer.skills.contains(Normalize.token($0)) }) {
            let skill = tag.lowercased()
            primary = "Needs \(skill) — you offer \(skill)"
        } else if let matched = candidate.helpTypes
            .intersection(viewer.helpTypesOffered)
            .min(by: { $0.rawValue < $1.rawValue }) {
            primary = "Needs \(matched.displayName) — you can offer that"
        } else if candidate.isFollowedOwner || viewer.followedOwnerIds.contains(candidate.ownerId) {
            primary = "From a dreamer you follow"
        } else if breakdown.geoProximity > 0, let location = candidate.location, !location.isEmpty {
            primary = "Near you in \(location)"
        } else if breakdown.categoryAffinity > 0 {
            primary = "\(candidate.category.capitalized) — like dreams you've spent time with"
        } else if candidate.sources.contains(.fresh) {
            primary = "Just posted"
        }

        let underServedNote: String?
        if candidate.offersReceived == 0 && (isFairnessSlot || breakdown.underServedBoost > 0) {
            underServedNote = "still waiting for a first offer of help"
        } else if isFairnessSlot {
            underServedNote = "hasn't been seen by many people yet"
        } else {
            underServedNote = nil
        }

        switch (primary, underServedNote) {
        case let (.some(match), .some(note)):
            return "\(match) · \(note)"
        case let (.some(match), nil):
            return match
        case let (nil, .some(note)):
            return "New to you — \(note)"
        case (nil, nil):
            return "Suggested for you"
        }
    }
}
