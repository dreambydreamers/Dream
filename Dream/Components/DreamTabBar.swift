import SwiftUI

enum DreamTab: Hashable {
    case discover, explore, activity, profile
}

/// Floating, translucent capsule tab bar. Icon-only buttons with an animated
/// highlight that slides behind the active tab; a tinted accent "+" in the
/// middle for creating. Adapts to a dark feed (`dark`) or light surfaces.
struct DreamTabBar: View {
    @Binding var active: DreamTab
    /// When true (the user is scrolling the feed) the bar shrinks out of the
    /// way; any tap on the bar restores it to full size.
    @Binding var collapsed: Bool
    var dark: Bool = false
    var onCreate: () -> Void

    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 0) {
            tabButton(.discover, icon: "house.fill")
            tabButton(.explore,  icon: "play.rectangle")
            createButton
            tabButton(.activity, icon: "bell")
            tabButton(.profile,  icon: "person.crop.circle")
        }
        .padding(.horizontal, 8)
        .frame(height: 64)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .overlay(Capsule(style: .continuous).fill(Color.black.opacity(dark ? 0.35 : 0.18)))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75)
                )
        }
        .clipShape(Capsule(style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
        .scaleEffect(collapsed ? 0.78 : 1, anchor: .bottom)
        .opacity(collapsed ? 0.85 : 1)
        .animation(.smooth(duration: 0.55, extraBounce: 0.1), value: collapsed)
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
    }

    private func tabButton(_ tab: DreamTab, icon: String) -> some View {
        let isActive = active == tab
        return Button {
            collapsed = false   // driven by the smooth .animation(value:) modifier
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { active = tab }
        } label: {
            ZStack {
                if isActive {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.22))
                        .matchedGeometryEffect(id: "activeHighlight", in: highlight)
                        .frame(width: 60, height: 44)
                }
                Image(systemName: icon)
                    .font(.system(size: 22, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? .white : Color.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var createButton: some View {
        Button {
            collapsed = false   // driven by the smooth .animation(value:) modifier
            onCreate()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(DreamTheme.blue, in: Circle())
                .shadow(color: DreamTheme.blue.opacity(0.5), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}
