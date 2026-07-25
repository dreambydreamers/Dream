import Foundation

/// Every weight and threshold of the ranking pipeline, in one place.
///
/// The objective these numbers serve: SUCCESSFUL CONNECTIONS (help offers that
/// become conversations that become delivered support), not watch time. See
/// docs/RANKING_TUNING.md for how each knob behaves and the two invariants
/// that must never be tuned away:
///   1. Fairness slots are filled by exposure deficit BEFORE quality scoring.
///   2. Watch signals only shape the viewer's own affinity — nothing here can
///      lower a dream's reach because other viewers skipped it.
public struct RankingConfig: Sendable, Equatable {

    // MARK: Scoring weights (points added to a candidate's total)

    /// Points per matched help type (dream needs ∩ viewer offers). The
    /// heaviest weight by design: "can this viewer actually help" dominates.
    public var helpTypeMatchWeight: Double = 3.0
    /// Matched help types counted at most this many times.
    public var helpTypeMatchCap: Int = 2

    /// Points per dream help-tag that literally matches one of the viewer's
    /// free-text skills (normalized). Sharper than help-type match.
    public var skillOverlapWeight: Double = 1.5
    /// Matched skill tags counted at most this many times.
    public var skillOverlapCap: Int = 2

    /// Multiplied by the viewer's learned affinity [0, 1] for the dream's
    /// category. Affinity comes from the viewer's OWN engagement only.
    public var categoryAffinityWeight: Double = 1.0
    /// A category the viewer explicitly declared interest in scores at least
    /// this affinity even with no watch history.
    public var declaredInterestAffinity: Double = 0.8

    /// Flat points when viewer and dream normalize to the same location.
    public var geoMatchWeight: Double = 0.75

    /// Flat points when the dream's stage is one the viewer prefers.
    public var stagePreferenceWeight: Double = 0.5

    // MARK: Under-served boost (fairness inside scoring)

    /// Maximum extra points for a dream that is aging without offers.
    /// boost = maxBoost × min(ageDays/rampDays, 1) × max(0, 1 − offers/saturation)
    /// It only ever ADDS to under-served dreams — popular dreams keep their
    /// full base score (never suppressed).
    public var underServedMaxBoost: Double = 2.0
    /// Offers at which the boost has fully decayed to zero.
    public var underServedOfferSaturation: Double = 3.0
    /// Days over which the boost ramps from 0 to max while offers stay low.
    public var underServedAgeRampDays: Double = 14.0

    // MARK: Recency (mild, so fresh posts get a first look)

    /// Points at age zero, halving every `recencyHalfLifeHours`.
    public var recencyMaxBonus: Double = 0.5
    public var recencyHalfLifeHours: Double = 72.0

    // MARK: Fairness slots (exposure floor)

    /// Feed page length the fairness slots are laid out against.
    public var pageSize: Int = 10
    /// 0-based positions within each page reserved for under-exposed dreams.
    /// These are filled by exposure deficit, not score.
    public var fairnessSlotPositions: [Int] = [2, 7]
    /// Target: every dream reaches this many relevant viewers…
    public var exposureViewerFloor: Int = 25
    /// …within this many days of posting.
    public var exposureFloorWindowDays: Int = 7

    // MARK: Diversity re-rank

    /// At most this many dreams from the same creator…
    public var maxPerCreatorPerWindow: Int = 2
    /// …in any run of this many consecutive feed items.
    public var creatorWindowSize: Int = 10
    /// Longest allowed run of same-category items.
    public var maxConsecutiveSameCategory: Int = 2

    // MARK: Candidate hygiene / queue behavior

    /// A seen (non-dismissed) dream may reappear after this many days.
    public var seenTTLDays: Int = 14
    /// Refill the per-viewer queue when fewer than this many items remain.
    public var queueRefillThreshold: Int = 20
    /// Target queue length after a refill.
    public var queueTargetLength: Int = 60
    /// Candidate pool size requested from the server.
    public var candidateLimit: Int = 300

    public init() {}

    public static let `default` = RankingConfig()
}
