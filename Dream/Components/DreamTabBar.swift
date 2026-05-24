import SwiftUI

enum DreamTab: Hashable {
    case discover, explore, activity, profile
}

struct DreamTabBar: View {
    @Binding var active: DreamTab
    var dark: Bool = false
    var onCreate: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            tabButton(.discover, icon: "sparkles", label: "Discover")
            tabButton(.explore,  icon: "map",      label: "Explore")
            createButton
            tabButton(.activity, icon: "bell",     label: "Activity")
            tabButton(.profile,  icon: "person",   label: "Profile")
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 18)
        .background(
            (dark ? Color.black.opacity(0.55) : Color(hex: 0xFBF8F2).opacity(0.94))
                .background(.ultraThinMaterial)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(dark ? Color.white.opacity(0.12) : DreamTheme.line)
                .frame(height: dark ? 0.5 : 1)
        }
    }

    private func tabButton(_ tab: DreamTab, icon: String, label: String) -> some View {
        let isActive = active == tab
        let color: Color = isActive ? DreamTheme.ink
                                    : (dark ? Color.white.opacity(0.55) : DreamTheme.ink2)
        return Button { active = tab } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .regular))
                Text(label)
                    .font(DreamTheme.Font.text(10, weight: isActive ? .bold : .medium))
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private var createButton: some View {
        Button(action: onCreate) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(DreamTheme.ink, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .offset(y: -8)
        .frame(width: 60)
    }
}
