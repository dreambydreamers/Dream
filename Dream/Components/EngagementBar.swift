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

    /// One action in the bar. Composed rather than fixed, because the actions a
    /// surface actually offers differ — the feed rail has "more" and no like,
    /// while dream detail has the full set.
    struct Item: Identifiable {
        let id = UUID()
        let icon: String
        let label: String
        var count: Int? = nil
        var isActive: Bool = false
        var activeColor: Color = DreamTheme.Accent.base
        var action: () -> Void = {}

        static func like(count: Int, isLiked: Bool, action: @escaping () -> Void) -> Item {
            .init(icon: isLiked ? "heart.fill" : "heart", label: "Like", count: count,
                  isActive: isLiked, activeColor: DreamTheme.Status.error, action: action)
        }

        static func comment(count: Int, action: @escaping () -> Void) -> Item {
            .init(icon: "bubble.left", label: "Comments", count: count, action: action)
        }

        static func save(count: Int? = nil, isSaved: Bool, action: @escaping () -> Void) -> Item {
            .init(icon: isSaved ? "bookmark.fill" : "bookmark", label: isSaved ? "Saved" : "Save",
                  count: count, isActive: isSaved, action: action)
        }

        static func share(action: @escaping () -> Void) -> Item {
            .init(icon: "paperplane", label: "Share", action: action)
        }

        static func more(action: @escaping () -> Void) -> Item {
            .init(icon: "ellipsis", label: "More", action: action)
        }
    }

    let items: [Item]
    var orientation: Orientation = .vertical
    /// Glass tiles for placement over video.
    var onMedia: Bool = false

    var body: some View {
        let layout = orientation == .vertical
            ? AnyLayout(VStackLayout(spacing: DreamSpace.s8))
            : AnyLayout(HStackLayout(spacing: DreamSpace.s11))

        layout {
            ForEach(items) { item in
                button(for: item)
            }
        }
    }

    private func button(for item: Item) -> some View {
        let icon = item.icon
        let count = item.count
        let isActive = item.isActive
        let activeColor = item.activeColor

        return Button(action: item.action) {
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
        .accessibilityLabel(item.label)
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
