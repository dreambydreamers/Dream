import SwiftUI

struct RootView: View {
    @StateObject private var auth = AuthService.shared
    @State private var activeTab: DreamTab = .discover
    @State private var creating = false
    @State private var showPublishedToast = false

    var body: some View {
        Group {
            if auth.isSignedIn {
                MainShell(
                    activeTab: $activeTab,
                    creating: $creating,
                    showPublishedToast: $showPublishedToast
                )
            } else {
                OnboardingScreen()
            }
        }
        .animation(.easeInOut, value: auth.isSignedIn)
    }
}

private struct MainShell: View {
    @Binding var activeTab: DreamTab
    @Binding var creating: Bool
    @Binding var showPublishedToast: Bool

    /// The user's existing dream, looked up when they tap "+". When set, we offer
    /// a choice between posting an update to it or starting a brand-new dream.
    @State private var updateTarget: Dream?
    @State private var chooseCreateKind = false
    @State private var postingUpdate = false
    @State private var publishedMessage = "Dream published"
    /// Shrinks the floating tab bar while the user scrolls the feed.
    @State private var tabBarCollapsed = false
    /// Hides the tab bar while inside a pushed ChatScreen.
    @State private var tabBarHidden = false
    /// Hides the tab bar while Explore search is focused so it never rides above
    /// the keyboard.
    @State private var exploreSearchFocused = false
    /// App-wide activity feed — drives the tab bar's unread badge and keeps it
    /// live over Realtime even when the user isn't on the Activity tab.
    @ObservedObject private var activity = ActivityRepository.shared

    var body: some View {
        ZStack(alignment: .bottom) {
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            DreamTabBar(active: $activeTab, collapsed: $tabBarCollapsed, dark: activeTab == .discover, badgeCount: activity.unreadCount, onCreate: { Task { await handleCreateTap() } })
                .offset(y: shouldHideTabBar ? 150 : 0)
                .animation(.easeInOut(duration: 0.22), value: shouldHideTabBar)
                .allowsHitTesting(!shouldHideTabBar)
                // Stay at the physical bottom when the keyboard opens (e.g. the
                // Explore search) instead of riding up on top of it.
                .ignoresSafeArea(.keyboard, edges: .bottom)

            if showPublishedToast {
                publishedToast
                    .padding(.bottom, 110)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // Container region only — ignoring the default `.all` would also ignore
        // the keyboard safe area for every tab screen, which breaks keyboard
        // avoidance app-wide (the chat composer ends up hidden under the keyboard).
        .ignoresSafeArea(.container, edges: .bottom)
        .task { await activity.start() }
        .onChange(of: activeTab) { _, tab in
            tabBarCollapsed = false
            if tab != .explore {
                exploreSearchFocused = false
            }
            if tabBarHidden {
                // Tab bar is hidden = user is inside a pushed screen (chat / dream detail).
                // An accidental swipe to another tab would leave them stranded with no nav.
                // Snap them back to Activity so they can continue where they were.
                DispatchQueue.main.async { activeTab = .activity }
            }
        }
        .confirmationDialog("Create", isPresented: $chooseCreateKind, titleVisibility: .visible) {
            Button("Post an update") { postingUpdate = true }
            Button("Start a new dream") { creating = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Share an update on your dream, or start a brand-new one.")
        }
        .fullScreenCover(isPresented: $creating) {
            CreateDreamScreen(
                onClose: { creating = false },
                onPublish: {
                    creating = false
                    flashToast("Dream published")
                }
            )
            .pausesDiscoverFeed()
        }
        .fullScreenCover(isPresented: $postingUpdate) {
            if let updateTarget {
                PostUpdateScreen(
                    dream: updateTarget,
                    onClose: { postingUpdate = false },
                    onPosted: {
                        postingUpdate = false
                        flashToast("Update posted")
                    }
                )
                .pausesDiscoverFeed()
            }
        }
    }

    /// On "+", route to a new-dream composer if the user has no dream yet,
    /// otherwise let them choose between an update and a new dream.
    private func handleCreateTap() async {
        if let mine = await DreamRepository.shared.myDream() {
            updateTarget = mine
            chooseCreateKind = true
        } else {
            creating = true
        }
    }

    private func flashToast(_ message: String) {
        publishedMessage = message
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showPublishedToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            withAnimation(.easeOut(duration: 0.3)) { showPublishedToast = false }
        }
    }

    private var shouldHideTabBar: Bool {
        tabBarHidden || exploreSearchFocused
    }

    private var publishedToast: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .bold))
            Text(publishedMessage)
                .font(DreamTheme.Font.text(14, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(DreamTheme.ink, in: Capsule())
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
    }

    /// Horizontally swipeable pages, one per tab, in tab-bar order. Swiping
    /// left/right moves between adjacent tabs; the tab bar drives the same
    /// `activeTab` selection.
    private var tabContent: some View {
        TabView(selection: $activeTab) {
            DiscoverScreen(tabBarCollapsed: $tabBarCollapsed, activeTab: $activeTab)
                .tag(DreamTab.discover)
            ExploreScreen(isSearchFocused: $exploreSearchFocused)
                .tag(DreamTab.explore)
            ActivityScreen(isTabBarHidden: $tabBarHidden)
                .tag(DreamTab.activity)
            profilePage
                .tag(DreamTab.profile)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea(.container)
    }

    @ViewBuilder
    private var profilePage: some View {
        if let userId = AuthService.shared.userId {
            ProfileScreen(userId: userId, isCurrentUser: true)
        } else {
            ProfilePlaceholder()
        }
    }
}

#Preview { RootView() }
