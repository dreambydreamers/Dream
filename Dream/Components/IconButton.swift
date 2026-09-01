import SwiftUI

/// Square icon button — the kit's `core/IconButton.jsx`.
///
/// Note the shape: the design system uses a `radius-sm` squircle, not a circle,
/// for icon chrome. `GlassCircleButton` remains for the round treatments that are
/// still circular by design (e.g. the feed's play overlay).
struct IconButton: View {
    enum Variant {
        /// Over media — translucent dark fill with a light hairline.
        case glass
        /// On a page — card fill with a hairline border.
        case solid
        /// Bare icon, no chrome.
        case plain
        /// Filled accent.
        case accent
    }

    let systemName: String
    let accessibilityLabel: String
    var variant: Variant = .glass
    var size: CGFloat = 40
    var badge: Int = 0
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: (size * 0.45).rounded(), weight: .medium))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .background {
                    if variant == .glass {
                        DreamShape.sm
                            .fill(DreamTheme.Glass.fill)
                            .background(.ultraThinMaterial, in: DreamShape.sm)
                            .environment(\.colorScheme, .dark)
                    } else {
                        DreamShape.sm.fill(fill)
                    }
                }
                .overlay(DreamShape.sm.strokeBorder(border, lineWidth: 1))
                .clipShape(DreamShape.sm)
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        BadgeDot(count: badge).offset(x: 5, y: -5)
                    }
                }
                .contentShape(DreamShape.sm)
        }
        .buttonStyle(DreamPressStyle(scale: 0.92))
        .accessibilityLabel(accessibilityLabel)
    }

    private var fill: Color {
        switch variant {
        case .solid: return DreamTheme.Surface.card
        case .accent: return DreamTheme.Accent.base
        case .plain, .glass: return .clear
        }
    }

    private var foreground: Color {
        switch variant {
        case .glass: return DreamTheme.OnMedia.base
        case .solid, .plain: return DreamTheme.Text.primary
        case .accent: return DreamTheme.Action.primaryForeground
        }
    }

    private var border: Color {
        switch variant {
        case .glass: return DreamTheme.Glass.stroke
        case .solid: return DreamTheme.Border.standard
        case .plain, .accent: return .clear
        }
    }
}

/// Unread count pill. Red, per the kit — the app previously used the brand blue,
/// which read as decoration rather than as something needing attention.
struct BadgeDot: View {
    let count: Int
    var showsBorder: Bool = false

    var body: some View {
        Text(count > 9 ? "9+" : "\(count)")
            .dreamStyle(.ui(10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, count > 9 ? 4 : 0)
            .frame(minWidth: 17, minHeight: 17)
            .background(DreamTheme.Status.error, in: Capsule())
            .overlay {
                if showsBorder {
                    Capsule().strokeBorder(Color(hex: 0x14171A, alpha: 0.7), lineWidth: 1.5)
                }
            }
    }
}
