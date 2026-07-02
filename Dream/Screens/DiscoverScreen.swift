import SwiftUI

struct DiscoverScreen: View {
    @StateObject private var repo = DreamRepository.shared
    @ObservedObject private var auth = AuthService.shared
    /// Shrinks the floating tab bar while the user pages through the feed.
    var tabBarCollapsed: Binding<Bool> = .constant(false)
    /// Lets us snap back to Discover after any sheet/cover dismissal (fixes paged-TabView jump).
    var activeTab: Binding<DreamTab> = .constant(.discover)
    /// feedID of the card currently centred in the paged scroll view.
    @State private var currentFeedID: UUID?
    @State private var cleanDisplay: Bool = false
    @State private var presentedDream: Dream?
    @State private var helpForDream: Dream?
    @State private var shareDream: Dream?
    @State private var profileForUser: UUID?
    @State private var isMuted: Bool = false
    @StateObject private var videoActions = VideoActionsModel()
    @StateObject private var savedStore = SavedDreamsStore.shared
    @State private var moreMenuDream: Dream? = nil
    @State private var expandedDesc: Set<UUID> = []
    @State private var followedOwners: Set<UUID> = []
    @State private var loadedFollowOwners: Set<UUID> = []
    @State private var followBusyOwners: Set<UUID> = []
    @State private var shareToast: String?
    @State private var shareToastTask: Task<Void, Never>?

    private var dreams: [Dream] { repo.dreams }
    private var dream: Dream { dreams.first { $0.feedID == currentFeedID } ?? dreams[0] }
    private var currentIndex: Int { dreams.firstIndex { $0.feedID == currentFeedID } ?? 0 }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if dreams.isEmpty {
                placeholder
            } else {
                feed

                // Fixed top bar — never scrolls, always above videos
                if !cleanDisplay {
                    VStack(spacing: 0) {
                        topBar
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                        Spacer()
                    }
                    .transition(.opacity)
                }

                // Clean display: small X to exit
                if cleanDisplay {
                    VStack(spacing: 0) {
                        HStack {
                            Spacer()
                            Button {
                                withAnimation(.easeInOut(duration: 0.22)) { cleanDisplay = false }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(10)
                                    .background(Color.black.opacity(0.45), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 16)
                            .padding(.top, 8)
                        }
                        Spacer()
                    }
                    .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.22), value: cleanDisplay)
        .task {
            if repo.dreams.isEmpty { await repo.loadFeed() }
            if currentFeedID == nil { currentFeedID = dreams.first?.feedID }
            FeedVideoPreloader.shared.prefetchNeighbors(of: dreams, around: currentIndex)
            markFeedActive()
            if !dreams.isEmpty { await refreshFollowState(for: dream) }
        }
        .onAppear {
            if currentFeedID == nil { currentFeedID = dreams.first?.feedID }
            markFeedActive()
        }
        .onChange(of: currentFeedID) { _, _ in
            tabBarCollapsed.wrappedValue = true
            FeedVideoPreloader.shared.prefetchNeighbors(of: dreams, around: currentIndex)
            markFeedActive()
            if !dreams.isEmpty { Task { await refreshFollowState(for: dream) } }
        }
        .onChange(of: repo.dreams.count) { _, _ in
            if currentFeedID == nil { currentFeedID = dreams.first?.feedID }
            FeedVideoPreloader.shared.prefetchNeighbors(of: dreams, around: currentIndex)
            markFeedActive()
            if !dreams.isEmpty { Task { await refreshFollowState(for: dream) } }
        }
        .onChange(of: isMuted) { _, muted in
            FeedVideoPreloader.shared.feedMuted = muted
        }
        .onDisappear {
            FeedVideoPreloader.shared.feedActiveID = nil
        }
        .fullScreenCover(item: $presentedDream, onDismiss: { activeTab.wrappedValue = .discover }) { d in
            DreamDetailScreen(dream: d, onBack: { presentedDream = nil })
        }
        .sheet(item: $helpForDream, onDismiss: { activeTab.wrappedValue = .discover }) { d in
            HelpSheet(dream: d, onClose: { helpForDream = nil })
                .pausesDiscoverFeed()
        }
        .sheet(item: $shareDream, onDismiss: { activeTab.wrappedValue = .discover }) { d in
            InAppShareSheet(
                dream: d,
                onClose: { shareDream = nil },
                onSent: { name in showShareToast("Sent to \(name)") }
            )
            .pausesDiscoverFeed()
        }
        .fullScreenCover(item: $profileForUser, onDismiss: { activeTab.wrappedValue = .discover }) { userId in
            ProfileScreen(userId: userId, onBack: { profileForUser = nil })
        }
        .videoActions(videoActions)
        .confirmationDialog("", isPresented: Binding(
            get: { moreMenuDream != nil },
            set: { if !$0 { moreMenuDream = nil } }
        ), titleVisibility: .hidden) {
            if let d = moreMenuDream {
                Button("Save to Gallery") {
                    videoActions.save(storagePath: d.videoStoragePath)
                }
                Button("Share outside Dream") {
                    videoActions.share(storagePath: d.videoStoragePath)
                }
                Button("Cancel", role: .cancel) { }
            }
        }
        .overlay(alignment: .bottom) {
            if let shareToast {
                HStack(spacing: 8) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text(shareToast)
                        .font(DreamTheme.Font.text(14, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.74), in: Capsule())
                .padding(.bottom, 118)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: shareToast)
    }

    private func markFeedActive() {
        guard !dreams.isEmpty else { return }
        FeedVideoPreloader.shared.feedActiveID = currentFeedID
        FeedVideoPreloader.shared.feedMuted = isMuted
    }

    // MARK: - Feed

    private var feed: some View {
        GeometryReader { geo in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(dreams, id: \.feedID) { d in
                        cardView(d, geo: geo, safeTop: geo.safeAreaInsets.top,
                                 isActive: d.feedID == currentFeedID)
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $currentFeedID)
            .scrollIndicators(.hidden)
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }

    // Each card: full-screen video + optional overlay. Non-active cards are muted
    // and non-interactive; they only appear during the transition swipe.
    private func cardView(_ d: Dream, geo: GeometryProxy, safeTop: CGFloat, isActive: Bool) -> some View {
        ZStack {
            DreamVideoBackground(dream: d, isMuted: isActive ? isMuted : true)
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()

            // Overlay hidden for the active card when clean display is on;
            // adjacent cards always show it (they're off-screen during clean mode).
            if !(cleanDisplay && isActive) {
                topGradient
                bottomGradient

                VStack(alignment: .leading, spacing: 0) {
                    // Reserve space for the fixed top bar that sits above all cards.
                    // safeTop (status bar) + 8pt (bar padding) + ~40pt (bar height)
                    Color.clear.frame(height: safeTop + 48)

                    Spacer(minLength: 24)

                    HStack(alignment: .bottom, spacing: 12) {
                        bottomInfo(for: d, isActive: isActive)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        rightRail(for: d, isActive: isActive)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 132)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            }
        }
        .frame(width: geo.size.width, height: geo.size.height)
        .clipped()
        .allowsHitTesting(isActive)
    }

    private var placeholder: some View {
        VStack(spacing: 14) {
            if repo.isLoading {
                ProgressView()
                    .tint(.white)
                Text("Finding dreams near you…")
                    .font(DreamTheme.Font.text(14))
                    .foregroundStyle(.white.opacity(0.75))
            } else {
                Image(systemName: "moon.stars")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.white.opacity(0.6))
                Text("No dreams yet")
                    .font(DreamTheme.Font.display(22, weight: .regular))
                    .foregroundStyle(.white)
                Text("Be the first to share one.")
                    .font(DreamTheme.Font.text(14))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(32)
    }

    // MARK: - Pieces

    private var topGradient: some View {
        LinearGradient(
            colors: [.black.opacity(0.55), .clear],
            startPoint: .top, endPoint: .bottom
        )
        .frame(height: 220)
        .frame(maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var bottomGradient: some View {
        LinearGradient(
            colors: [.clear, .black.opacity(0.65)],
            startPoint: .top, endPoint: .bottom
        )
        .frame(height: 320)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // Fixed header — lives in body ZStack, never slides with card transitions.
    private var topBar: some View {
        HStack {
            Text("Dream")
                .font(DreamTheme.Font.display(28, weight: .light, italic: true))
                .foregroundStyle(DreamTheme.blue)
                .tracking(-0.8)
                .shadow(color: DreamTheme.blue.opacity(0.6), radius: 8)
                .shadow(color: .white.opacity(0.3), radius: 16)

            Spacer()

            HStack(spacing: 10) {
                circleButton(systemImage: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill") {
                    isMuted.toggle()
                }
                // Clears all overlay chrome so the video fills the screen.
                // Tap the × corner button that appears to restore the UI.
                circleButton(systemImage: "arrow.up.left.and.arrow.down.right") {
                    withAnimation(.easeInOut(duration: 0.22)) { cleanDisplay = true }
                }
            }
        }
    }

    private func circleButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.16), in: Circle())
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func bottomInfo(for d: Dream, isActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                CategoryBadge(category: d.category, dark: true)
                HStack(spacing: 4) {
                    Text("◐")
                    Text(d.stage.rawValue)
                }
                .font(DreamTheme.Font.text(12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.18), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5))
            }

            authorRow(for: d, isActive: isActive)

            Button { presentedDream = d } label: {
                Text(d.displayTitle)
                    .font(DreamTheme.Font.display(30, weight: .regular))
                    .tracking(-0.6)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 6, y: 1)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(d.category.palette.fg)
                .frame(width: 36, height: 3)
                .clipShape(Capsule())
                .shadow(color: d.category.palette.fg.opacity(0.7), radius: 6)

            if !d.desc.isEmpty {
                descriptionBlock(for: d)
            }
        }
    }

    private func descriptionBlock(for d: Dream) -> some View {
        let expanded = expandedDesc.contains(d.feedID)
        let long = d.desc.count > 90

        if expanded || !long {
            return AnyView(
                Text(d.desc)
                    .font(DreamTheme.Font.text(13))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            )
        }
        let snippet = String(d.desc.prefix(90))
        return AnyView(
            (Text(snippet + "… ")
                .font(DreamTheme.Font.text(13))
                .foregroundStyle(Color.white.opacity(0.9))
             + Text("more")
                .font(DreamTheme.Font.text(13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.65))
            )
            .lineSpacing(2)
            .onTapGesture {
                let id = d.feedID
                withAnimation(.easeInOut(duration: 0.2)) {
                    _ = expandedDesc.insert(id)
                }
            }
        )
    }

    private func rightRail(for d: Dream, isActive: Bool) -> some View {
        VStack(spacing: 16) {
            ActionButton(systemImage: "heart.fill", label: "I can help") {
                helpForDream = d
            }
            ActionButton(systemImage: "paperplane.fill", label: "Send") {
                shareDream = d
            }
            ActionButton(
                systemImage: savedStore.isSaved(d.feedID) ? "bookmark.fill" : "bookmark",
                label: savedStore.isSaved(d.feedID) ? "Saved" : "Save"
            ) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                savedStore.toggle(d.feedID)
            }
            ActionButton(systemImage: "ellipsis", label: "More") {
                moreMenuDream = d
            }
        }
        .frame(width: 64)
    }

    private func authorRow(for d: Dream, isActive: Bool) -> some View {
        HStack(spacing: 8) {
            Button { profileForUser = d.ownerId } label: {
                Avatar(name: d.name, seed: d.avatarSeed, size: 34, url: d.avatarURL)
                    .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.28), radius: 7, y: 2)
            }
            .buttonStyle(.plain)

            Button { profileForUser = d.ownerId } label: {
                Text("@\(d.handle)")
                    .font(DreamTheme.Font.text(14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.94))
                    .lineLimit(1)
            }
            .buttonStyle(.plain)

            if !isOwnDream(d) {
                Button { toggleFollow(for: d) } label: {
                    Text(isFollowingOwner(d) ? "Following" : "Follow")
                        .font(DreamTheme.Font.text(12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.18)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .disabled(followBusyOwners.contains(d.ownerId))
            }

            if !d.distance.isEmpty {
                Circle().fill(.white.opacity(0.5)).frame(width: 3, height: 3)
                Text(d.distance)
                    .font(DreamTheme.Font.text(14))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }
        }
    }

    private func isOwnDream(_ d: Dream) -> Bool {
        auth.userId == d.ownerId
    }

    private func isFollowingOwner(_ d: Dream) -> Bool {
        followedOwners.contains(d.ownerId)
    }

    private func refreshFollowState(for dream: Dream) async {
        guard auth.userId != dream.ownerId, !loadedFollowOwners.contains(dream.ownerId) else { return }
        let following = await ProfileRepository.shared.isFollowing(dream.ownerId)
        loadedFollowOwners.insert(dream.ownerId)
        if following {
            followedOwners.insert(dream.ownerId)
        } else {
            followedOwners.remove(dream.ownerId)
        }
    }

    private func toggleFollow(for d: Dream) {
        guard !isOwnDream(d), !followBusyOwners.contains(d.ownerId) else { return }
        let ownerId = d.ownerId
        let wasFollowing = followedOwners.contains(ownerId)
        followBusyOwners.insert(ownerId)
        if wasFollowing {
            followedOwners.remove(ownerId)
        } else {
            followedOwners.insert(ownerId)
        }
        loadedFollowOwners.insert(ownerId)
        Task {
            do {
                if wasFollowing {
                    try await ProfileRepository.shared.unfollow(ownerId)
                } else {
                    try await ProfileRepository.shared.follow(ownerId)
                }
            } catch {
                if wasFollowing { followedOwners.insert(ownerId) } else { followedOwners.remove(ownerId) }
                print("[DiscoverScreen] toggle follow failed: \(error)")
            }
            followBusyOwners.remove(ownerId)
        }
    }

    private func showShareToast(_ message: String) {
        shareToastTask?.cancel()
        shareToast = message
        shareToastTask = Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            shareToast = nil
        }
    }
}

#Preview {
    DiscoverScreen()
}

/// Lets a bare `UUID` drive `.sheet(item:)` / `.fullScreenCover(item:)`.
extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}
