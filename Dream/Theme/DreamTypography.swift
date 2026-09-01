import SwiftUI

// Typography, ported from the Dream Design System's `tokens/typography.css`.
//
// Two faces do all the work:
//   • Instrument Sans  — everything, including headlines. Strong weight contrast
//                        (400 body vs 700 headline) is the point.
//   • Instrument Serif — italic accent words only, never whole paragraphs.
//
// Tracking and line height can't ride on a `Font`, so a role is a `DreamTextStyle`
// (font + tracking + line spacing + optional case) applied with `.dreamStyle(_:)`.
// Every size goes through `relativeTo:` so the app finally honours Dynamic Type.

// MARK: - Faces

enum DreamFontFace {
    static let sansRegular = "InstrumentSans-Regular"
    static let sansMedium = "InstrumentSans-Medium"
    static let sansSemiBold = "InstrumentSans-SemiBold"
    static let sansBold = "InstrumentSans-Bold"
    static let sansItalic = "InstrumentSans-Italic"
    static let serifRegular = "InstrumentSerif-Regular"
    static let serifItalic = "InstrumentSerif-Italic"

    static func sans(_ weight: Font.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black: return sansBold
        case .semibold: return sansSemiBold
        case .medium: return sansMedium
        default: return sansRegular
        }
    }
}

// MARK: - Fonts

enum DreamType {
    /// Body face at an explicit size. Prefer a `DreamTextStyle` role where one fits.
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(DreamFontFace.sans(weight), size: size, relativeTo: textStyle(for: size))
    }

    /// Display face. Reserved for accent words — see `DreamHeadline`.
    static func serif(_ size: CGFloat, italic: Bool = false) -> Font {
        .custom(italic ? DreamFontFace.serifItalic : DreamFontFace.serifRegular,
                size: size, relativeTo: textStyle(for: size))
    }

    /// Anchors a custom size to the nearest system text style so Dynamic Type
    /// scales it at a sensible rate.
    static func textStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case 30...: return .largeTitle
        case 26..<30: return .title
        case 22..<26: return .title2
        case 20..<22: return .title3
        case 17..<20: return .body
        case 16..<17: return .callout
        case 15..<16: return .subheadline
        case 13..<15: return .footnote
        case 11..<13: return .caption
        default: return .caption2
        }
    }
}

// MARK: - Roles

/// A complete type role: face, size, tracking and line spacing travel together so
/// they can't drift apart at a call site.
struct DreamTextStyle {
    let font: Font
    let tracking: CGFloat
    let lineSpacing: CGFloat
    var textCase: SwiftUI.Text.Case?

    // Tracking is expressed in em in the kit; points = em × size.
    private static let trackingDisplay: CGFloat = -0.04
    private static let trackingTitle: CGFloat = -0.025
    private static let trackingLabel: CGFloat = 0.16

    // Line height is a multiplier in CSS. SwiftUI's `lineSpacing` is *extra* space
    // on top of the font's natural leading (~1.2×), so subtract that baseline.
    private static func spacing(_ leading: CGFloat, _ size: CGFloat) -> CGFloat {
        max(0, size * (leading - 1.2))
    }

    /// Big statements. Sans bold, tight tracking. Sizes 20/22/24/26/30/36/48.
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> DreamTextStyle {
        .init(font: DreamType.sans(size, weight: weight),
              tracking: size * trackingDisplay,
              lineSpacing: spacing(1.12, size))
    }

    /// Section and card headings. Sans bold, moderate tracking. Sizes 18–22.
    static func title(_ size: CGFloat, weight: Font.Weight = .bold) -> DreamTextStyle {
        .init(font: DreamType.sans(size, weight: weight),
              tracking: size * trackingTitle,
              lineSpacing: spacing(1.25, size))
    }

    /// Running text. Sizes 10–18.
    static func body(_ size: CGFloat, weight: Font.Weight = .regular, relaxed: Bool = false) -> DreamTextStyle {
        .init(font: DreamType.sans(size, weight: weight),
              tracking: 0,
              lineSpacing: spacing(relaxed ? 1.6 : 1.5, size))
    }

    /// Single-line UI text — buttons, pills, row titles. No extra line spacing.
    static func ui(_ size: CGFloat, weight: Font.Weight = .semibold) -> DreamTextStyle {
        .init(font: DreamType.sans(size, weight: weight), tracking: 0, lineSpacing: 0)
    }

    /// Uppercase micro-label with wide tracking — the kit's eyebrow treatment.
    static let label = DreamTextStyle(
        font: DreamType.sans(10, weight: .semibold),
        tracking: 10 * trackingLabel,
        lineSpacing: 0,
        textCase: .uppercase
    )

    /// Instrument Serif italic, used for accent words inside a sans headline and
    /// for the "Dream" wordmark. Tracking resets to zero — the serif is already loose.
    static func serifAccent(_ size: CGFloat) -> DreamTextStyle {
        .init(font: DreamType.serif(size, italic: true), tracking: 0, lineSpacing: spacing(1.12, size))
    }
}

extension View {
    func dreamStyle(_ style: DreamTextStyle) -> some View {
        self.font(style.font)
            .tracking(style.tracking)
            .lineSpacing(style.lineSpacing)
            .textCase(style.textCase)
    }
}

// MARK: - Headline

/// The kit's signature headline: a sans-bold phrase with one serif-italic accent
/// word — *"What's happening"*, *"Where dreams meet opportunity"*.
///
/// ```swift
/// DreamHeadline("What's", accent: "happening", size: 26)
/// ```
struct DreamHeadline: View {
    let lead: String
    let accent: String?
    var size: CGFloat = 26
    var color: Color = DreamTheme.Text.primary
    var alignment: TextAlignment = .leading

    init(_ lead: String, accent: String? = nil, size: CGFloat = 26,
         color: Color = DreamTheme.Text.primary, alignment: TextAlignment = .leading) {
        self.lead = lead
        self.accent = accent
        self.size = size
        self.color = color
        self.alignment = alignment
    }

    /// One `AttributedString` rather than two views, so the phrase wraps as a
    /// single paragraph and the accent word can fall to the next line naturally.
    private var phrase: AttributedString {
        let display = DreamTextStyle.display(size)

        var lead = AttributedString(self.lead)
        lead.swiftUI.font = display.font
        lead.swiftUI.tracking = display.tracking

        guard let accent, !accent.isEmpty else { return lead }

        var accentRun = AttributedString(" " + accent)
        accentRun.swiftUI.font = DreamType.serif(size, italic: true)
        accentRun.swiftUI.tracking = 0
        return lead + accentRun
    }

    var body: some View {
        SwiftUI.Text(phrase)
            .lineSpacing(DreamTextStyle.display(size).lineSpacing)
            .foregroundStyle(color)
            .multilineTextAlignment(alignment)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The italic serif "Dream" wordmark.
struct DreamWordmark: View {
    var size: CGFloat = 22
    var color: Color = DreamTheme.Accent.base

    var body: some View {
        SwiftUI.Text("Dream")
            .font(DreamType.serif(size, italic: true))
            .tracking(size * -0.02)
            .foregroundStyle(color)
    }
}
