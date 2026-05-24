import SwiftUI

struct RootView: View {
    @State private var signedIn = false
    @State private var activeTab: DreamTab = .discover

    var body: some View {
        Group {
            if signedIn {
                MainShell(activeTab: $activeTab)
            } else {
                OnboardingScreen(onSignIn: { withAnimation(.easeInOut) { signedIn = true } })
            }
        }
    }
}

private struct MainShell: View {
    @Binding var activeTab: DreamTab

    var body: some View {
        ZStack(alignment: .bottom) {
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            DreamTabBar(active: $activeTab, dark: activeTab == .discover, onCreate: {})
        }
        .ignoresSafeArea(edges: .bottom)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch activeTab {
        case .discover: DiscoverPlaceholder()
        case .explore:  ExplorePlaceholder()
        case .activity: ActivityPlaceholder()
        case .profile:  ProfilePlaceholder()
        }
    }
}

#Preview { RootView() }
