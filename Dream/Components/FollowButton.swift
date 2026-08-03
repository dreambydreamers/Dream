import SwiftUI

enum FollowButtonStyle {
    /// Fills its container — profile headers.
    case fullWidth
    /// Standard inline size — dream detail author row.
    case detail
    /// Small, over video — the Discover author row.
    case feed
    /// Small, on a page — search result rows.
    case compact
}

/// Follow / Following toggle — the kit's `social/FollowButton.jsx`.
///
/// Two changes from the previous treatment: the shape is a `radius-sm` squircle
/// rather than a capsule, matching the category and stage tags it sits beside; and
/// the feed variant now fills with the accent when *not* following, so the action
/// reads as an invitation rather than as another piece of glass chrome.
struct FollowButton: View {
    let isFollowing: Bool
    var style: FollowButtonStyle = .fullWidth
    var isBusy: Bool = false
    var onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            Text(isFollowing ? "Following" : "Follow")
                .dreamStyle(.ui(fontSize))
                .foregroundStyle(foreground)
                .frame(maxWidth: style == .fullWidth ? .infinity : nil)
                .frame(minHeight: height)
                .padding(.horizontal, horizontalPadding)
                .background(background, in: DreamShape.sm)
                .overlay(DreamShape.sm.strokeBorder(stroke, lineWidth: 1))
                .contentShape(DreamShape.sm)
        }
        .buttonStyle(DreamPressStyle())
        .disabled(isBusy)
        .opacity(isBusy ? 0.6 : 1)
        .accessibilityLabel(isFollowing ? "Following. Tap to unfollow." : "Follow")
    }

    private var isOverMedia: Bool { style == .feed }

    private var height: CGFloat {
        switch style {
        case .fullWidth: return 44
        case .detail: return 36
        case .feed, .compact: return 30
        }
    }

    private var horizontalPadding: CGFloat {
        switch style {
        case .fullWidth: return DreamSpace.s9
        case .detail: return 15
        case .feed, .compact: return DreamSpace.s6
        }
    }

    private var fontSize: CGFloat {
        switch style {
        case .fullWidth: return 14
        case .detail: return 12
        case .feed, .compact: return 11
        }
    }

    private var background: Color {
        if isOverMedia { return isFollowing ? .clear : DreamTheme.Accent.base }
        return isFollowing ? DreamTheme.Action.secondaryBackground : DreamTheme.Accent.base
    }

    private var foreground: Color {
        if isOverMedia { return DreamTheme.OnMedia.base }
        return isFollowing ? DreamTheme.Text.secondary : DreamTheme.Action.primaryForeground
    }

    private var stroke: Color {
        if isOverMedia { return isFollowing ? Color.white.opacity(0.6) : .clear }
        return isFollowing ? DreamTheme.Action.secondaryBorder : .clear
    }
}
