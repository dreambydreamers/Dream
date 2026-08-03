import SwiftUI

/// Stage indicator — the kit's `badges/StagePill.jsx`.
///
/// New to the app: `DreamStage` existed as a model but had no shared UI, so where
/// a stage was shown at all it was rendered inline. Pairs with `CategoryBadge` —
/// category says *what* the dream is, stage says *how far along* it is.
struct StagePill: View {
    let stage: DreamStage
    /// Transparent with a white hairline, for placement over video.
    var onMedia: Bool = false
    var isCompact: Bool = false

    var body: some View {
        HStack(spacing: DreamSpace.s3) {
            Image(systemName: icon)
                .font(.system(size: isCompact ? 11 : 12, weight: .medium))
            Text(stage.rawValue)
                .dreamStyle(.ui(isCompact ? 10 : 11))
                .tracking((isCompact ? 10 : 11) * 0.06)
                .textCase(.uppercase)
        }
        .foregroundStyle(foreground)
        .lineLimit(1)
        .padding(.horizontal, isCompact ? DreamSpace.s4 : DreamSpace.s5)
        .padding(.vertical, isCompact ? 5 : DreamSpace.s3)
        .background(onMedia ? Color.clear : DreamTheme.Surface.warm, in: DreamShape.sm)
        .overlay(
            DreamShape.sm.strokeBorder(onMedia ? Color.white.opacity(0.55) : .clear, lineWidth: 1)
        )
    }

    private var icon: String {
        switch stage {
        case .idea: return "lightbulb"
        case .early: return "leaf"
        case .needs: return "hand.raised"
        case .almost: return "flag"
        }
    }

    private var foreground: Color {
        // A warm brown that sits on `Surface.warm` in light; the warm surface goes
        // dark in dark mode, so the label lifts to match.
        onMedia ? DreamTheme.OnMedia.base : Color(light: 0x7A5828, dark: 0xD9B87E)
    }
}
