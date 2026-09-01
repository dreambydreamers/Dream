import SwiftUI

// Raw design scales, ported from the Dream Design System's `tokens/*.css`.
// Colors live in `DreamTheme.swift`; type roles live in `DreamTypography.swift`.
//
// Rule of thumb from the kit: reach for a token, never a literal. If a value
// genuinely isn't on a scale, that's a signal the design drifted — fix the
// design rather than adding a one-off here.

// MARK: - Spacing

/// The kit's 18-step spacing ramp (`tokens/spacing.css`). Steps are deliberately
/// dense at the low end — most padding lands between `s4` and `s11`.
enum DreamSpace {
    static let s1: CGFloat = 2
    static let s2: CGFloat = 4
    static let s3: CGFloat = 6
    static let s4: CGFloat = 8
    static let s5: CGFloat = 10
    static let s6: CGFloat = 12
    static let s7: CGFloat = 14
    static let s8: CGFloat = 16
    static let s9: CGFloat = 18
    static let s10: CGFloat = 20
    static let s11: CGFloat = 24
    static let s12: CGFloat = 28
    static let s13: CGFloat = 32
    static let s14: CGFloat = 40
    static let s15: CGFloat = 48
    static let s16: CGFloat = 56
    static let s17: CGFloat = 72
    static let s18: CGFloat = 96

    // Layout constants — the frame every screen is built inside.

    /// Horizontal inset for screen content. Every full-width screen uses this.
    static let screenGutter: CGFloat = 18
    /// Top inset for screens that draw their own header instead of a nav bar.
    static let safeTop: CGFloat = 56
    /// Bottom inset that clears the floating tab bar in a scrolling screen.
    static let safeBottom: CGFloat = 100
    /// Height of the `DreamTabBar` pill itself, excluding its outer padding.
    static let tabBarHeight: CGFloat = 54
}

// MARK: - Radii

/// Apple's continuous-curvature (squircle) scale. The kit upgrades these to true
/// superellipses in CSS via `corner-shape`; on iOS the equivalent is pairing every
/// radius with `style: .continuous`, which `DreamShape` does for you.
enum DreamRadius {
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 22
    static let xl: CGFloat = 30
}

/// Squircle shape helpers. Prefer these over raw `RoundedRectangle` so the
/// `.continuous` style is never accidentally dropped.
enum DreamShape {
    static var xs: RoundedRectangle { .init(cornerRadius: DreamRadius.xs, style: .continuous) }
    static var sm: RoundedRectangle { .init(cornerRadius: DreamRadius.sm, style: .continuous) }
    static var md: RoundedRectangle { .init(cornerRadius: DreamRadius.md, style: .continuous) }
    static var lg: RoundedRectangle { .init(cornerRadius: DreamRadius.lg, style: .continuous) }
    static var xl: RoundedRectangle { .init(cornerRadius: DreamRadius.xl, style: .continuous) }

    static func radius(_ r: CGFloat) -> RoundedRectangle { .init(cornerRadius: r, style: .continuous) }
}

// MARK: - Elevation

/// The kit is explicit: *hairline borders, not shadows. Shadows are reserved for
/// things that FLOAT* (`tokens/shadows.css`). There are exactly four.
///
/// CSS blur radii are halved on the way in — a CSS `28px` blur reads as a
/// SwiftUI shadow radius of `14`.
struct DreamShadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat

    /// Elements genuinely lifted off the page: the tab bar, floating buttons.
    static let float = DreamShadow(color: Color(hex: 0x14171A, alpha: 0.30), radius: 14, x: 0, y: 10)
    /// Bottom sheets, casting upward.
    static let sheet = DreamShadow(color: Color(hex: 0x14171A, alpha: 0.16), radius: 16, x: 0, y: -8)
    /// Glass chrome sitting over media.
    static let glass = DreamShadow(color: .black.opacity(0.20), radius: 5, x: 0, y: 2)
    /// Legibility shadow for text drawn directly on video.
    static let textOnMedia = DreamShadow(color: .black.opacity(0.55), radius: 1.5, x: 0, y: 1)
}

extension View {
    func dreamShadow(_ shadow: DreamShadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}

// MARK: - Motion

/// Durations, curves and press feedback from `tokens/motion.css`. Using these
/// keeps every transition in the app on the same rhythm.
enum DreamMotion {
    static let instant: Double = 0.10
    static let fast: Double = 0.16
    static let base: Double = 0.24
    static let slow: Double = 0.40

    /// `cubic-bezier(0.25, 0.8, 0.25, 1)` — the default for state changes.
    static func smooth(_ duration: Double = base) -> Animation {
        .timingCurve(0.25, 0.8, 0.25, 1, duration: duration)
    }

    /// `cubic-bezier(0.4, 0, 1, 1)` — accelerating, for things leaving the screen.
    static func exit(_ duration: Double = fast) -> Animation {
        .timingCurve(0.4, 0, 1, 1, duration: duration)
    }

    /// `cubic-bezier(0.34, 1.4, 0.64, 1)` overshoots, so it maps to a real spring
    /// rather than a timing curve. Used for press feedback and anything that pops in.
    static let spring: Animation = .spring(response: 0.32, dampingFraction: 0.62)

    /// Press feedback, applied uniformly by `DreamButtonStyle`.
    static let pressScale: CGFloat = 0.97
    static let pressOpacity: Double = 0.72
}
