import SwiftUI

/// Category tag — the kit's `badges/CategoryBadge.jsx`.
///
/// Deliberately no leading dot: the badge is a plain uppercase label whose color
/// *is* the category signal, which keeps it the same visual weight as the
/// `StagePill` it always sits beside.
struct CategoryBadge: View {
    let category: DreamCategory
    /// Over-media treatment — transparent with a white hairline.
    var dark: Bool = false
    var isCompact: Bool = false

    var body: some View {
        let p = category.palette
        Text(category.rawValue)
            .dreamStyle(.ui(isCompact ? 10 : 11))
            .tracking((isCompact ? 10 : 11) * 0.06)
            .textCase(.uppercase)
            .foregroundStyle(dark ? DreamTheme.OnMedia.base : p.fg)
            .lineLimit(1)
            .padding(.horizontal, isCompact ? DreamSpace.s4 : DreamSpace.s5)
            .padding(.vertical, isCompact ? 5 : DreamSpace.s3)
            .background(dark ? Color.clear : p.bg, in: DreamShape.sm)
            .overlay(
                DreamShape.sm.strokeBorder(dark ? Color.white.opacity(0.55) : .clear, lineWidth: 1)
            )
    }
}
