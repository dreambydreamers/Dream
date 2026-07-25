# Ranking: what each weight does and how to tune it

The recommendation feed optimizes for **successful connections** — help offers
that become conversations that become delivered support — not watch time. Every
knob below should be tuned against that metric (see
`supabase/queries/fairness_report.sql`), never against session length.

All weights live in one struct: `Packages/DreamRanking/Sources/DreamRanking/RankingConfig.swift`.
The pipeline: candidate generation (SQL, `get_feed_candidates`) → **fairness
pass** → scoring → diversity assembly → reasons (`DreamRanker.rank`, pure Swift).

## Two invariants you must NOT tune away

1. **Fairness slots come before scoring.** Positions 2 and 7 of every page are
   filled by *exposure deficit* (fewest distinct viewers first), not by score.
   Removing them re-creates the rich-get-richer feed this system exists to avoid.
2. **Watch signals are viewer-local.** Skips/completions adjust only the
   watching viewer's `categoryAffinity`. There is deliberately no field on
   `DreamCandidate` carrying aggregate watch behavior — do not add one. A fast
   skip means "wrong viewer", not "worse dream".

## Scoring weights

Score = sum of the components below. With defaults, a strong capability match
(≈6.0) always dominates stacked secondary signals (≈3.25 max).

| Knob | Default | What it does | Raising it |
|---|---|---|---|
| `helpTypeMatchWeight` (cap `helpTypeMatchCap`=2) | 3.0/match | Points per help type the dream needs that the viewer offers. The heaviest signal by design. | Feed becomes more strictly "dreams you can help", at the cost of discovery breadth. |
| `skillOverlapWeight` (cap `skillOverlapCap`=2) | 1.5/match | Literal free-text skill ↔ help-tag match ("iOS development"). Sharper than help-type. | Rewards precise profiles; useless until users fill in skills. |
| `categoryAffinityWeight` | 1.0 × affinity | Learned interest from the viewer's own engagement, 0–1 per category. | Feed follows watch behavior more — keep below the capability weights or it drifts toward a taste feed. |
| `declaredInterestAffinity` | 0.8 | Affinity floor for categories the user explicitly picked. | Trust stated interests over behavior. |
| `geoMatchWeight` | 0.75 | Same normalized location string. (v1: exact match only, no geocoding.) | Matters for `space`/local help; raise when location data improves. |
| `stagePreferenceWeight` | 0.5 | Dream stage ∈ supporter's preferred stages. | Useful once the edit UI captures preferences. |
| `recencyMaxBonus` / `recencyHalfLifeHours` | 0.5 / 72h | Mild freshness bonus, halving every 3 days. | Feed skews newer; keep mild — the `fresh` candidate source already guarantees new posts enter. |

## Under-served boost (fairness inside scoring)

`boost = underServedMaxBoost × min(age/rampDays, 1) × max(0, 1 − offers/offerSaturation)`

* `underServedMaxBoost` (2.0) — extra points for a dream aging without offers.
  At default it outweighs everything except a help-type match, which is the
  intent: *relevant* starving dreams surface first. Purely additive: popular
  dreams lose nothing.
* `underServedOfferSaturation` (3.0) — offers at which the boost hits zero.
  Raise if dreams need more than ~3 offers before one converts.
* `underServedAgeRampDays` (14) — days to reach full boost. Lower = the system
  panics sooner about unnoticed dreams.

## Fairness floor

* `exposureViewerFloor` (25) / `exposureFloorWindowDays` (7) — target: every
  dream reaches 25 *relevant* viewers in its first week. Used by the SQL
  `underexposed` source (deficit-ordered) and the fairness pass.
* `fairnessSlotPositions` ([2, 7]) / `pageSize` (10) — 2 of every 10 feed
  positions are reserved. More slots = faster floor coverage, less score-driven
  feed. Verify changes with `SevenDaySimulationTests`.

## Diversity

* `maxPerCreatorPerWindow` (2) / `creatorWindowSize` (10) — max 2 dreams per
  creator in any 10 consecutive items.
* `maxConsecutiveSameCategory` (2) — no 3 same-category items in a row.
* Production quality (`hasVideo`, polish) is **not an input** anywhere —
  enforced by `DiversityTests.testHasVideoDoesNotAffectPlacement`.

## Queue / hygiene

* `seenTTLDays` (14) — a seen dream may reappear after this long; dismissed
  ("not relevant") dreams never do.
* `candidateLimit` (300), `queueTargetLength` (60), `queueRefillThreshold` (20)
  — pool size, on-device queue length, and the refill trigger.

## How to evaluate a change

1. Edit `RankingConfig` defaults (or pass a custom config in tests).
2. `cd Packages/DreamRanking && swift test` — the 7-day simulation
   (`SevenDaySimulationTests`) must still show every dream reaching the floor,
   and the invariant tests must stay green.
3. Seed a local stack (`supabase db reset`, runs `supabase/seed.sql`) and
   inspect candidates/ranked output for a few personas (funding-only backer,
   coder, local supporter).
4. In production, watch `fairness_report.sql` section 2: the share of 30-day
   dreams with zero offers is the number this system exists to shrink; section
   4's funnel conversion tells you whether matches were real. If zero-offer
   share falls but acceptance collapses, you are spraying irrelevant matches —
   prefer tightening candidate sources over inflating the boost.

## Adding an embedding-based candidate source later

`get_feed_candidates` builds candidates as a UNION of per-source CTEs and tags
each row with its sources. Add an `src_embedding` CTE (pgvector similarity),
union it in, add `case embedding` to `CandidateSource` in Swift — scoring,
fairness, and diversity need no changes.
