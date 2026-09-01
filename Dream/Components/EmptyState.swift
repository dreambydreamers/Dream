import SwiftUI

/// The kit's `feedback/EmptyState.jsx`.
///
/// Consolidates four near-identical private copies that had grown in
/// ActivityScreen, CommentsSheet, ProfileScreen and ExploreScreen. Every empty and
/// error state in the app should route through here so the voice stays consistent:
/// a headline whose last word is a serif-italic accent, one sentence of plain
/// explanation, and at most one primary action.
struct EmptyState: View {
    enum Tone {
        case neutral, error
    }

    /// SF Symbol for the icon tile.
    let icon: String
    let title: String
    /// The serif-italic word that closes the headline — "No offers *yet*".
    var accent: String? = nil
    var message: String? = nil
    var tone: Tone = .neutral
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var secondaryTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: DreamSpace.s6) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(iconForeground)
                .frame(width: 60, height: 60)
                .background(iconFill, in: DreamShape.lg)
                .overlay(DreamShape.lg.strokeBorder(iconBorder, lineWidth: 1))

            VStack(spacing: DreamSpace.s2) {
                DreamHeadline(title, accent: accent, size: 20, alignment: .center)

                if let message {
                    Text(message)
                        .dreamStyle(.body(13, relaxed: true))
                        .foregroundStyle(DreamTheme.Text.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                }
            }

            if actionTitle != nil || secondaryTitle != nil {
                VStack(spacing: DreamSpace.s2) {
                    if let actionTitle {
                        DreamButton(title: actionTitle, size: .md, fullWidth: true) { action?() }
                    }
                    if let secondaryTitle {
                        DreamButton(title: secondaryTitle, variant: .ghost, size: .md, fullWidth: true) {
                            secondaryAction?()
                        }
                    }
                }
                .frame(maxWidth: 240)
                .padding(.top, DreamSpace.s1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DreamSpace.s14)
        .padding(.horizontal, DreamSpace.s11)
    }

    private var iconFill: Color {
        tone == .error ? DreamTheme.Status.errorBackground : DreamTheme.Surface.sunken
    }

    private var iconBorder: Color {
        tone == .error ? DreamTheme.Status.error : DreamTheme.Border.standard
    }

    private var iconForeground: Color {
        tone == .error ? DreamTheme.Status.error : DreamTheme.Text.tertiary
    }
}
