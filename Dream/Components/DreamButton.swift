import SwiftUI

/// The app's one button treatment, ported from the design system's `core/Button.jsx`.
///
/// Replaces `PrimaryButton` and the several local filled/outline pairs that had
/// drifted apart. Prefer this over hand-rolling a `Button` label.
struct DreamButton: View {
    enum Variant {
        case primary, secondary, ghost, danger
    }

    enum Size {
        case sm, md, lg

        var height: CGFloat {
            switch self {
            case .sm: return 34
            case .md: return 44
            case .lg: return 52
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .sm: return DreamSpace.s7
            case .md: return DreamSpace.s9
            case .lg: return DreamSpace.s11 - 2
            }
        }

        var fontSize: CGFloat {
            switch self {
            case .sm: return 13
            case .md: return 14
            case .lg: return 15
            }
        }

        var iconSize: CGFloat {
            switch self {
            case .sm: return 16
            case .md: return 18
            case .lg: return 19
            }
        }
    }

    let title: String
    var variant: Variant = .primary
    var size: Size = .lg
    /// SF Symbol shown before the label.
    var icon: String? = nil
    /// SF Symbol shown after the label — usually `arrow.right` on a "Continue".
    var trailingIcon: String? = nil
    var fullWidth: Bool = false
    var isEnabled: Bool = true
    /// Swaps the leading icon for a spinner and blocks interaction.
    var isBusy: Bool = false
    /// Overrides the fill on `.primary` — used for category-tinted actions.
    var tone: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DreamSpace.s4) {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(foreground)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: size.iconSize, weight: .semibold))
                }

                Text(title)
                    .dreamStyle(.ui(size.fontSize))

                if let trailingIcon, !isBusy {
                    Image(systemName: trailingIcon)
                        .font(.system(size: size.iconSize, weight: .semibold))
                }
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(minHeight: size.height)
            .padding(.horizontal, size.horizontalPadding)
            .background(background, in: DreamShape.lg)
            .overlay(DreamShape.lg.strokeBorder(border, lineWidth: 1))
            .contentShape(DreamShape.lg)
        }
        .buttonStyle(DreamPressStyle())
        .disabled(!isEnabled || isBusy)
        .opacity(isEnabled ? 1 : 0.45)
    }

    private var background: Color {
        switch variant {
        case .primary: return tone ?? DreamTheme.Action.primaryBackground
        case .secondary: return DreamTheme.Action.secondaryBackground
        case .ghost: return .clear
        case .danger: return DreamTheme.Status.error
        }
    }

    private var foreground: Color {
        switch variant {
        case .primary: return DreamTheme.Action.primaryForeground
        case .secondary: return DreamTheme.Action.secondaryForeground
        case .ghost: return DreamTheme.Text.accent
        case .danger: return .white
        }
    }

    private var border: Color {
        variant == .secondary ? DreamTheme.Action.secondaryBorder : .clear
    }
}

/// The kit's press feedback (`--press-scale`, `--press-opacity`), as a real
/// `ButtonStyle` so every tappable surface responds identically.
///
/// Most of the app uses `.buttonStyle(.plain)`, which gives no feedback at all.
/// Reach for this instead wherever a custom label needs to feel pressable.
struct DreamPressStyle: ButtonStyle {
    /// Tighter scale for small circular/square controls, where 0.97 is invisible.
    var scale: CGFloat = DreamMotion.pressScale

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? DreamMotion.pressOpacity : 1)
            .animation(DreamMotion.spring, value: configuration.isPressed)
    }
}
