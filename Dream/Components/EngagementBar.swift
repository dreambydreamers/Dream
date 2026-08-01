import SwiftUI

/// Like / comment / save / share cluster — the kit's `social/EngagementBar.jsx`.
///
/// Replaces the feed's `ActionButton` rail. Two differences from the old rail: the
/// glass tiles are `radius-sm` squircles rather than circles, matching the rest of
/// the icon chrome, and a horizontal orientation exists for DreamDetail.
struct EngagementBar: View {
    enum Orientation {
        case vertical, horizontal
    }

    var orientation: Orientation = .vertical
    /// Glass tiles for placement over video.
    var onMedia: Bool = false

    var likeCount: Int
    var commentCount: Int
    var saveCount: Int
    var isLiked: Bool = false
    var isSaved: Bool = false

    var onLike: () -> Void = {}
    var onComment: () -> Void = {}
    var onSave: () -> Void = {}
    var onShare: () -> Void = {}

    var body: some View {
        let layout = orientation == .vertical
            ? AnyLayout(VStackLayout(spacing: DreamSpace.s8))
            : AnyLayout(HStackLayout(spacing: DreamSpace.s11))

        layout {
            item(icon: isLiked ? "heart.fill" : "heart", count: likeCount, label: "Like",
                 isActive: isLiked, activeColor: DreamTheme.Status.error, action: onLike)
            item(icon: "bubble.left", count: commentCount, label: "Comments", action: onComment)
            item(icon: isSaved ? "bookmark.fill" : "bookmark", count: saveCount, label: "Save",
                 isActive: isSaved, action: onSave)
            item(icon: "paperplane", count: nil, label: "Share", action: onShare)
        }
    }

    private func item(icon: String, count: Int?, label: String, isActive: Bool = false,
                      activeColor: Color = DreamTheme.Accent.base, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: DreamSpace.s1) {
                Image(systemName: icon)
                    .font(.system(size: 21, weight: .medium))
                    .frame(width: 44, height: 44)
                    .background {
                        if onMedia {
                            DreamShape.sm
                                .fill(DreamTheme.Glass.fill)
                                .background(.ultraThinMaterial, in: DreamShape.sm)
                                .environment(\.colorScheme, .dark)
                                .overlay(DreamShape.sm.strokeBorder(DreamTheme.Glass.stroke, lineWidth: 1))
                        }
                    }

                if let count {
                    Text(count.abbreviated)
                        .dreamStyle(.ui(11))
                        .shadow(color: onMedia ? .black.opacity(0.55) : .clear, radius: 1.5, y: 1)
                }
            }
            .foregroundStyle(foreground(isActive: isActive, activeColor: activeColor))
            .contentShape(Rectangle())
        }
        .buttonStyle(DreamPressStyle(scale: 0.88))
        .accessibilityLabel(label)
    }

    private func foreground(isActive: Bool, activeColor: Color) -> Color {
        if isActive { return activeColor }
        return onMedia ? DreamTheme.OnMedia.base : DreamTheme.Text.secondary
    }
}

extension Int {
    /// Compact count for engagement chrome — 1200 reads as "1.2K".
    var abbreviated: String {
        switch self {
        case 1_000_000...:
            return String(format: "%.1fM", Double(self) / 1_000_000).replacingOccurrences(of: ".0", with: "")
        case 1_000...:
            return String(format: "%.1fK", Double(self) / 1_000).replacingOccurrences(of: ".0", with: "")
        default:
            return "\(self)"
        }
    }
}
