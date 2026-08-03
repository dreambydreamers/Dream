import SwiftUI

/// Transient confirmation — the kit's `feedback/Toast.jsx`.
///
/// Extracted from `RootView`, which was the only place a toast existed even though
/// several flows want one ("Saved to your collection", "Link copied").
struct Toast: View {
    enum Tone {
        case neutral, success, error
    }

    let message: String
    var tone: Tone = .neutral

    var body: some View {
        HStack(spacing: DreamSpace.s6) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
            Text(message)
                .dreamStyle(.ui(13, weight: .medium))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, DreamSpace.s7)
        .padding(.vertical, DreamSpace.s6)
        .background(background, in: DreamShape.lg)
        .dreamShadow(.float)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }

    private var icon: String {
        switch tone {
        case .neutral: return "info.circle"
        case .success: return "checkmark"
        case .error: return "exclamationmark.circle"
        }
    }

    private var background: Color {
        switch tone {
        case .neutral: return DreamTheme.Surface.inverse
        case .success: return DreamTheme.Status.success
        case .error: return DreamTheme.Status.error
        }
    }

    private var foreground: Color {
        tone == .neutral ? DreamTheme.Text.inverse : .white
    }
}
