import SwiftUI

/// Stubs for tabs not yet ported from the v2 prototype.
struct PlaceholderScreen: View {
    let title: String
    let subtitle: String
    var dark: Bool = false

    var body: some View {
        ZStack {
            (dark ? Color.black : DreamTheme.paper).ignoresSafeArea()
            VStack(spacing: 12) {
                Text(title)
                    .font(DreamTheme.Font.display(40, weight: .regular, italic: true))
                    .foregroundStyle(dark ? .white : DreamTheme.ink)
                Text(subtitle)
                    .font(DreamTheme.Font.text(14))
                    .foregroundStyle(dark ? Color.white.opacity(0.7) : DreamTheme.ink2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
    }
}

struct DiscoverPlaceholder: View {
    var body: some View {
        PlaceholderScreen(
            title: "Discover",
            subtitle: "Feed with supporter-mode matches will live here.",
            dark: true
        )
    }
}

struct ExplorePlaceholder: View {
    var body: some View {
        PlaceholderScreen(title: "Explore", subtitle: "Map of dreams near you — coming soon.")
    }
}

struct ActivityPlaceholder: View {
    var body: some View {
        PlaceholderScreen(title: "Activity", subtitle: "Everything that happens to your dream and the dreams you back.")
    }
}

struct ProfilePlaceholder: View {
    var body: some View {
        PlaceholderScreen(title: "Profile", subtitle: "Your dreams, your skills, the people you've helped.")
    }
}
