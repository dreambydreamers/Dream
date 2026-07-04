import SwiftUI

struct CategoryBadge: View {
    let category: DreamCategory
    var dark: Bool = false

    var body: some View {
        let p = category.palette
        HStack(spacing: 7) {
            Circle()
                .fill(dark ? Color.white : p.fg)
                .frame(width: 6, height: 6)
            Text(category.rawValue)
                .font(DreamTheme.Font.text(12, weight: .semibold))
                .foregroundStyle(dark ? Color.white : p.fg)
        }
        .padding(.vertical, 5)
        .padding(.leading, 10)
        .padding(.trailing, 11)
        .background(
            Capsule().fill(dark ? Color.white.opacity(0.18) : p.bg)
        )
        .overlay(
            Capsule().strokeBorder(Color.white.opacity(dark ? 0.30 : 0), lineWidth: 0.5)
        )
    }
}
