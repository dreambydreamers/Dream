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

    var body: some View {
        ZStack(alignment: .bottom) {
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            DreamTabBar(active: $activeTab, dark: activeTab == .discover, onCreate: { Task { await handleCreateTap() } })

            if showPublishedToast {
                publishedToast
                    .padding(.bottom, 110)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .ignoresSafeArea(edges: .bottom)
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

    @ViewBuilder
    private var tabContent: some View {
        switch activeTab {
        case .discover: DiscoverScreen()
        case .explore:  ExplorePlaceholder()
        case .activity: ActivityPlaceholder()
        case .profile:
            if let userId = AuthService.shared.userId {
                ProfileScreen(userId: userId, isCurrentUser: true)
            } else {
                ProfilePlaceholder()
            }
        }
    }
}

#Preview { RootView() }
