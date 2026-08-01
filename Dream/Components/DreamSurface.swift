import SwiftUI

/// A card surface — the kit's `core/Surface.jsx`.
///
/// The design system leans on hairline borders rather than shadows, so a surface
/// is a fill plus a 1pt border and nothing else. Use this instead of another
/// ad-hoc `RoundedRectangle` background.
struct DreamSurface<Content: View>: View {
    enum Tone {
        /// Raised content on the page ground. The default.
        case card
        /// Recessed well — segmented tracks, inline fields.
        case sunken
        /// Informational panels tied to the brand accent.
        case accent
        /// No fill or border; use when you only want the padding and radius.
        case plain
    }

    var tone: Tone = .card
    var padding: CGFloat = DreamSpace.s8
    var radius: CGFloat = DreamRadius.lg
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: DreamShape.radius(radius))
            .overlay(DreamShape.radius(radius).strokeBorder(border, lineWidth: 1))
    }

    private var fill: Color {
        switch tone {
        case .card: return DreamTheme.Surface.card
        case .sunken: return DreamTheme.Surface.sunken
        case .accent: return DreamTheme.Accent.tint
        case .plain: return .clear
        }
    }

    private var border: Color {
        switch tone {
        case .card: return DreamTheme.Border.standard
        case .accent: return DreamTheme.Border.accent
        case .sunken, .plain: return .clear
        }
    }
}

/// An accent panel with a leading icon — the "Dreams that name what they need get
/// three times more offers" note in Create, and the offer-origin banner in Chat.
struct DreamNote: View {
    let icon: String
    let text: String

    var body: some View {
        DreamSurface(tone: .accent, padding: DreamSpace.s7) {
            HStack(alignment: .top, spacing: DreamSpace.s5) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(DreamTheme.Accent.deep)
                    .padding(.top, 1)

                Text(text)
                    .dreamStyle(.body(12))
                    .foregroundStyle(DreamTheme.Text.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
