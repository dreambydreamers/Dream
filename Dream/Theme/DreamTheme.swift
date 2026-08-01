import SwiftUI
import UIKit

// Colors, ported from the Dream Design System's `tokens/colors.css`.
//
// Every semantic token is a *dynamic* color: it resolves against the current
// trait collection, so a single definition covers light and dark. Call sites
// never branch on color scheme — they just ask for the role they mean
// (`DreamTheme.Surface.page`, `DreamTheme.Text.secondary`) and get the right value.
//
// Three families are deliberately mode-invariant, because they sit on top of
// video rather than on a page: `Glass`, `OnMedia`, and the category/achievement
// accents that are already tuned for both.

enum DreamTheme {

    // MARK: - Base palette
    //
    // Raw ramps. Prefer the semantic roles below at call sites; these exist so the
    // semantic layer has something to point at, and for the rare literal need.

    /// Sky-blue accent ramp.
    enum Blue {
        static let base = Color(hex: 0x3A9DC4)
        static let deep = Color(hex: 0x2C7A9B)
        static let bright = Color(hex: 0x5BBBDE)
        static let soft = Color(hex: 0xDEEAF4)
        static let tint = Color(hex: 0xF1F7FB)
    }

    /// Warm paper neutrals — the identity of the light theme.
    enum Paper {
        static let base = Color(hex: 0xF7F3EA)
        static let raised = Color(hex: 0xFBF9F3)
        static let cream = Color(hex: 0xF1EADC)
        static let warm = Color(hex: 0xE9DFCB)
    }

    /// Ink ramp — warm-leaning greys, not the cool system greys.
    enum InkScale {
        static let base = Color(hex: 0x14171A)
        static let secondary = Color(hex: 0x5A6068)
        static let tertiary = Color(hex: 0x8A8377)
        static let quaternary = Color(hex: 0xB4AEA2)
        static let line = Color(hex: 0xE3DCCE)
        static let lineStrong = Color(hex: 0xD2C9B6)
    }

    // MARK: - Semantic roles

    /// Backgrounds, from the page ground up to raised cards.
    enum Surface {
        /// The ground every screen sits on.
        static let page = Color(light: 0xF7F3EA, dark: 0x101315)
        /// Raised content: cards, fields, sheets' inner surfaces.
        static let card = Color(light: 0xFFFFFF, dark: 0x191D20)
        /// Recessed wells: segmented-control tracks, skeleton bases.
        static let sunken = Color(light: 0xF1EADC, dark: 0x0A0C0E)
        /// The warmest surface — stage pills and other "paper" accents.
        static let warm = Color(light: 0xE9DFCB, dark: 0x232725)
        /// Flipped surface for high-contrast chips and toasts.
        static let inverse = Color(light: 0x14171A, dark: 0xF7F3EA)
    }

    /// Foreground text roles.
    ///
    /// Note: inside `DreamTheme` this name shadows `SwiftUI.Text`. Nothing in this
    /// file builds views, so that's harmless — but qualify as `SwiftUI.Text` if you
    /// ever add one here.
    enum Text {
        static let primary = Color(light: 0x14171A, dark: 0xF3EFE6)
        static let secondary = Color(light: 0x5A6068, dark: 0xA8AFB5)
        static let tertiary = Color(light: 0x8A8377, dark: 0x798086)
        static let disabled = Color(light: 0xB4AEA2, dark: 0x4E555B)
        /// For text on `Surface.inverse`.
        static let inverse = Color(light: 0xFFFFFF, dark: 0x14171A)
        /// Links and accent text — a step deeper than `Accent.base` for legibility.
        static let accent = Color(light: 0x2C7A9B, dark: 0x5BBBDE)
    }

    /// Hairlines. The kit leans on borders instead of shadows, so these carry a lot.
    enum Border {
        /// Default hairline. Named `standard` because `default` is a keyword.
        static let standard = Color(light: 0xE3DCCE, dark: 0x272C30)
        static let strong = Color(light: 0xD2C9B6, dark: 0x363C41)
        static let accent = Color(light: 0x3A9DC4, dark: 0x5BBBDE)
    }

    /// The brand accent and its washes.
    enum Accent {
        static let base = Color(light: 0x3A9DC4, dark: 0x5BBBDE)
        static let deep = Color(light: 0x2C7A9B, dark: 0x3A9DC4)
        /// Filled backgrounds for accent chips and check pills.
        static let soft = Color(light: 0xDEEAF4, dark: 0x1B3540)
        /// The lightest accent wash — informational panels.
        static let tint = Color(light: 0xF1F7FB, dark: 0x15242B)
    }

    /// Filled-button pairings, so foreground and background never drift apart.
    enum Action {
        static let primaryBackground = Accent.base
        static let primaryForeground = Color(light: 0xFFFFFF, dark: 0x0B1114)
        static let secondaryBackground = Color(light: 0xFFFFFF, dark: 0x191D20)
        static let secondaryForeground = Color(light: 0x14171A, dark: 0xF3EFE6)
        static let secondaryBorder = Color(light: 0xD2C9B6, dark: 0x363C41)
    }

    /// Status colors.
    ///
    /// `tokens/colors.css` overrides only the `-bg` values for dark. The foregrounds
    /// are lifted here as well, because the light values (e.g. success `#2F7A52`)
    /// fail contrast against `Surface.page` in dark. The lifted values are the kit's
    /// own dark treatments of the same hues, taken from its category ramps.
    enum Status {
        static let error = Color(light: 0xB83D45, dark: 0xDE868C)
        static let success = Color(light: 0x2F7A52, dark: 0x7DC49B)
        static let warning = Color(light: 0xB07908, dark: 0xDFB755)

        static let errorBackground = Color(light: 0xF4D2D4, dark: 0x3A1E20)
        static let successBackground = Color(light: 0xD4E8DA, dark: 0x16301F)
        static let warningBackground = Color(light: 0xF4E4B8, dark: 0x3A2E10)
    }

    /// Translucent chrome that sits over video. Identical in both modes — the
    /// backdrop is the video, not the page.
    enum Glass {
        static let fill = Color(hex: 0x14171A, alpha: 0.42)
        static let fillStrong = Color(hex: 0x14171A, alpha: 0.62)
        static let stroke = Color.white.opacity(0.18)
    }

    /// Foregrounds drawn directly on media. Always white, in both modes.
    enum OnMedia {
        static let base = Color.white
        static let dim = Color.white.opacity(0.72)
    }

    /// Full-bleed dimmer behind modals and sheets.
    static let scrim = Color(lightRGBA: (0x14171A, 0.45), darkRGBA: (0x000000, 0.6))

    /// Shimmer placeholder ramp.
    enum Skeleton {
        static let base = Color(light: 0xF1EADC, dark: 0x1E2225)
        static let sheen = Color(light: 0xFBF9F3, dark: 0x272C30)
    }

    // MARK: - Layout

    enum Layout {
        /// Bottom padding a scrolling screen needs so its last row clears the
        /// floating tab bar.
        static let tabBarClearance: CGFloat = 132
    }

    // MARK: - Back-compatibility aliases
    //
    // The flat names predate the semantic layer and are still used across the app.
    // They now resolve to roles, which is how the kit's palette shift (accent to
    // #3A9DC4, neutrals to warm) and dark mode reach existing call sites unchanged.

    static let blue = Accent.base
    static let blueDeep = Accent.deep
    static let blueSoft = Accent.soft
    static let blueTint = Accent.tint

    static let ink = Text.primary
    static let ink2 = Text.secondary
    static let ink3 = Text.tertiary
    static let line = Border.standard
    static let error = Status.error

    // `bg` and `paper` were near-identical off-whites used for opposite jobs. An
    // audit of all 49 sites showed the split cleanly: `paper` is the full-screen
    // ground (18 of 20 uses are `.ignoresSafeArea()` or a sheet background), while
    // `bg` is always a recessed well *inside* a card — field fills, incoming chat
    // bubbles, unselected pill tracks. They map to opposite ends of the ramp.
    static let paper = Surface.page
    static let bg = Surface.sunken
    static let cream = Surface.sunken
    static let warm = Surface.warm

    // MARK: - Fonts
    //
    // Deprecated in favour of the roles in `DreamTypography.swift`, which carry
    // tracking, line spacing and Dynamic Type scaling. Kept so existing call sites
    // compile while screens migrate.

    enum Font {
        static func display(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular, italic: Bool = false) -> SwiftUI.Font {
            italic ? DreamType.serif(size, italic: true) : DreamType.serif(size)
        }

        static func text(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            DreamType.sans(size, weight: weight)
        }
    }
}

// MARK: - Categories

struct CategoryPalette {
    let fg: Color
    let bg: Color
    let tint: Color
}

enum DreamCategory: String, CaseIterable, Hashable {
    case tech = "Tech"
    case food = "Food"
    case art = "Art"
    case impact = "Social Impact"
    case education = "Education"
    case health = "Health"
    case music = "Music"
    case sport = "Sport"

    /// Per-category trios from `tokens/colors.css`. Light values are unchanged from
    /// the original app palette; dark `fg`/`bg` come from the kit's dark block, and
    /// dark `tint` is derived by blending the dark `bg` toward `Surface.page` (the
    /// kit leaves `--cat-*-tint` unoverridden, which would leave a near-white wash
    /// on a dark surface).
    var palette: CategoryPalette {
        switch self {
        case .tech:
            return .init(fg: Color(light: 0x2D6FA8, dark: 0x7FB6DE),
                         bg: Color(light: 0xDEEAF4, dark: 0x1B2F41),
                         tint: Color(light: 0xF4F8FB, dark: 0x152029))
        case .food:
            return .init(fg: Color(light: 0xC8632B, dark: 0xE39A6B),
                         bg: Color(light: 0xF4DCC8, dark: 0x3A2417),
                         tint: Color(light: 0xFBF1E7, dark: 0x231B16))
        case .art:
            return .init(fg: Color(light: 0xA23F87, dark: 0xD68FC0),
                         bg: Color(light: 0xF0D5E5, dark: 0x361B2E),
                         tint: Color(light: 0xFBF0F6, dark: 0x211720))
        case .impact:
            return .init(fg: Color(light: 0x2F7A52, dark: 0x7DC49B),
                         bg: Color(light: 0xD4E8DA, dark: 0x16301F),
                         tint: Color(light: 0xF0F7F2, dark: 0x13201A))
        case .education:
            return .init(fg: Color(light: 0xB07908, dark: 0xDFB755),
                         bg: Color(light: 0xF4E4B8, dark: 0x3A2E10),
                         tint: Color(light: 0xFBF6E7, dark: 0x231F13))
        case .health:
            return .init(fg: Color(light: 0xB83D45, dark: 0xDE868C),
                         bg: Color(light: 0xF4D2D4, dark: 0x3A1E20),
                         tint: Color(light: 0xFBEEEF, dark: 0x23181A))
        case .music:
            return .init(fg: Color(light: 0x5740A8, dark: 0xA791DE),
                         bg: Color(light: 0xDDD3F0, dark: 0x251E3E),
                         tint: Color(light: 0xF2EEFB, dark: 0x191827))
        case .sport:
            return .init(fg: Color(light: 0x1A8588, dark: 0x6FC0C2),
                         bg: Color(light: 0xC9E4E5, dark: 0x123132),
                         tint: Color(light: 0xEBF6F6, dark: 0x112122))
        }
    }

    var emoji: String {
        switch self {
        case .tech:      return "💡"
        case .food:      return "🍽️"
        case .art:       return "🎨"
        case .impact:    return "🌍"
        case .education: return "📚"
        case .health:    return "❤️"
        case .music:     return "🎵"
        case .sport:     return "⚡"
        }
    }
}

// MARK: - Illustrative accents
//
// Bright, saturated hues that read correctly on both light and dark surfaces, so
// they carry a single value. Ported from `tokens/colors.css`.

/// Achievement badge accents (`--achv-*`).
enum DreamAchievementAccent {
    static let storyteller = Color(hex: 0xE07B39)
    static let spark = Color(hex: 0xF5C518)
    static let hand = Color(hex: 0x8AD3A7)
    static let motion = Color(hex: 0xFF6B6B)
    static let star = Color(hex: 0xFFB800)
    static let halfway = Color(hex: 0x9B59B6)
    static let almost = Color(hex: 0x2ECC71)
}

/// Procedural avatar gradients (`--avatar-*`), picked by `abs(seed) % 5`.
enum DreamAvatarGradient {
    static let pairs: [(Color, Color)] = [
        (Color(hex: 0xF4B074), Color(hex: 0xC8632B)),
        (Color(hex: 0x8EC5DD), Color(hex: 0x3A7FA8)),
        (Color(hex: 0xC9A8E0), Color(hex: 0x7448A8)),
        (Color(hex: 0x9FD9B4), Color(hex: 0x2F7A52)),
        (Color(hex: 0xF1D27A), Color(hex: 0xB07908)),
    ]

    static func pair(seed: Int) -> (Color, Color) {
        pairs[abs(seed) % pairs.count]
    }
}

// MARK: - Color construction

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8)  & 0xFF) / 255
        let b = Double( hex        & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }

    /// A color that resolves against the current trait collection. This is what
    /// lets every existing `DreamTheme.*` call site become dark-aware without
    /// touching the call site.
    init(light: UInt32, dark: UInt32) {
        self.init(lightRGBA: (light, 1), darkRGBA: (dark, 1))
    }

    init(lightRGBA: (hex: UInt32, alpha: Double), darkRGBA: (hex: UInt32, alpha: Double)) {
        self.init(uiColor: UIColor { traits in
            let spec = traits.userInterfaceStyle == .dark ? darkRGBA : lightRGBA
            return UIColor(hex: spec.hex, alpha: spec.alpha)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: Double = 1) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8)  & 0xFF) / 255
        let b = CGFloat( hex        & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: CGFloat(alpha))
    }
}
