import SwiftUI

enum DreamTab: Hashable {
    case discover, explore, activity, profile
}

/// Floating tab bar — the kit's `navigation/DreamTabBar.jsx`.
///
/// Glass pill with an accent underline marking the active tab and a filled "+"
/// that is an action rather than a tab. The kit's shape is a `radius-xl` squircle
/// rather than a full capsule, which reads as less pill-like beside the app's other
/// squircle chrome.
///
/// Two layout invariants (see AGENTS.md, "Navigation & gestures"):
///  • the collapse must run through the single `.animation(_:value:)` below, not
///    through per-property animations;
///  • `.scaleEffect` must wrap the *assembled* pill — after background, clip and
///    shadow — or the glass and shadow scale independently of the content.
struct DreamTabBar: View {
    @Binding var active: DreamTab
    /// When true (the user is scrolling the feed) the bar shrinks out of the
    /// way; any tap on the bar restores it to full size.
    @Binding var collapsed: Bool
    var dark: Bool = false
    /// Unread-notification count shown as a badge on the Activity (bell) tab.
    var badgeCount: Int = 0
    var onCreate: () -> Void

    var body: some View {
        HStack(spacing: DreamSpace.s1) {
            tabButton(.discover, icon: "house")
            tabButton(.explore, icon: "safari")
            createButton
            tabButton(.activity, icon: "bell", badge: badgeCount)
            tabButton(.profile, icon: "person.crop.circle")
        }
        .padding(.horizontal, DreamSpace.s5)
        .frame(height: DreamSpace.tabBarHeight)
        .background {
            DreamShape.xl
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .overlay(DreamShape.xl.fill(DreamTheme.Glass.fillStrong.opacity(dark ? 1 : 0.75)))
                .overlay(DreamShape.xl.strokeBorder(DreamTheme.Glass.stroke, lineWidth: 0.75))
        }
        .clipShape(DreamShape.xl)
        .dreamShadow(.float)
        // Assembled pill only — see the invariant note above.
        .scaleEffect(collapsed ? 0.78 : 1, anchor: .bottom)
        .opacity(collapsed ? 0.85 : 1)
        .animation(.smooth(duration: 0.55, extraBounce: 0.1), value: collapsed)
        .padding(.horizontal, DreamSpace.s10)
        .padding(.bottom, DreamSpace.s12)
    }

    private func tabButton(_ tab: DreamTab, icon: String, badge: Int = 0) -> some View {
        let isActive = active == tab
        return Button {
            collapsed = false   // driven by the smooth .animation(value:) modifier
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { active = tab }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 21, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? DreamTheme.OnMedia.base : Color.white.opacity(0.55))
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 {
                            BadgeDot(count: badge, showsBorder: true)
                                .scaleEffect(0.88)
                                .offset(x: 13, y: -9)
                        }
                    }

                // Underline marker. A fixed-width bar rather than a sliding
                // highlight — it keeps the icons at a constant size and needs no
                // matchedGeometry namespace.
                Capsule()
                    .fill(isActive ? DreamTheme.Accent.base : .clear)
                    .frame(width: 14, height: 2)
                    .animation(DreamMotion.smooth(), value: isActive)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: tab))
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
    }

    private var createButton: some View {
        Button {
            collapsed = false   // driven by the smooth .animation(value:) modifier
            onCreate()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(DreamTheme.Action.primaryForeground)
                .frame(width: 42, height: 42)
                .background(DreamTheme.Accent.base, in: DreamShape.sm)
        }
        .buttonStyle(DreamPressStyle(scale: 0.92))
        .accessibilityLabel("Create")
        .padding(.horizontal, DreamSpace.s3)
    }

    private func accessibilityLabel(for tab: DreamTab) -> String {
        switch tab {
        case .discover: return "Discover"
        case .explore: return "Explore"
        case .activity: return "Activity"
        case .profile: return "Profile"
        }
    }
}
