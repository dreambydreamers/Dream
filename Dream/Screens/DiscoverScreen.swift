import SwiftUI

struct DiscoverScreen: View {
    @ObservedObject private var repo = DreamRepository.shared
    @ObservedObject private var auth = AuthService.shared
    /// Shrinks the floating tab bar while the user pages through the feed.
    var tabBarCollapsed: Binding<Bool> = .constant(false)
    /// Lets us snap back to Discover after any sheet/cover dismissal (fixes paged-TabView jump).
    var activeTab: Binding<DreamTab> = .constant(.discover)
    /// Virtual slot currently centred in the paged scroll view. Slots repeat the
    /// real feed several times so the user can keep swiping forever; video/player
    /// state still keys on the real card's `feedID`.
    @State private var currentSlot: Int?
    @State private var cleanDisplay: Bool = false
    @State private var presentedDream: Dream?
    @State private var helpForDream: Dream?
    @State private var shareDream: Dream?
    @State private var profileForUser: UUID?
    @State private var isMuted: Bool = false
    @StateObject private var videoActions = VideoActionsModel()
    @ObservedObject private var savedStore = SavedDreamsStore.shared
    @State private var moreMenuDream: Dream? = nil
    @State private var expandedDesc: Set<UUID> = []
    @State private var followedOwners: Set<UUID> = []
    @State private var loadedFollowOwners: Set<UUID> = []
    @State private var followBusyOwners: Set<UUID> = []
    @State private var shareToast: String?
    @State private var shareToastTask: Task<Void, Never>?
    @State private var feedResetToken = UUID()

    private var dreams: [Dream] { repo.dreams }
    private let feedCycleCount = 5
    private var middleCycle: Int { feedCycleCount / 2 }
    private var virtualFeedCount: Int { dreams.count <= 1 ? dreams.count : dreams.count * feedCycleCount }
    private var initialSlotIndex: Int { slotForDreamIndex(0) }
    private var currentSlotIndex: Int { currentSlot ?? initialSlotIndex }
    private var currentIndex: Int { dreamIndex(forSlot: currentSlotIndex) }
    private var dream: Dream { dreams[currentIndex] }
    private var currentFeedID: UUID? { dreams.isEmpty ? nil : dream.feedID }

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
                            .accessibilityLabel("Show controls")
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
            ensureCurrentSlot()
            FeedVideoPreloader.shared.prefetchNeighbors(of: dreams, around: currentIndex)
            markFeedActive()
            if !dreams.isEmpty { await refreshFollowState(for: dream) }
        }
        .onAppear {
            ensureCurrentSlot()
            markFeedActive()
        }
        .onChange(of: currentSlot) { _, _ in
            normalizeLoopSlotIfNeeded()
            tabBarCollapsed.wrappedValue = true
            FeedVideoPreloader.shared.prefetchNeighbors(of: dreams, around: currentIndex)
            markFeedActive()
            if !dreams.isEmpty { Task { await refreshFollowState(for: dream) } }
        }
        .onChange(of: repo.dreams.count) { _, _ in
            ensureCurrentSlot()
            normalizeLoopSlotIfNeeded()
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
        .fullScreenCover(item: $presentedDream, onDismiss: restoreFeedAfterPresentation) { d in
            DreamDetailScreen(dream: d, onBack: { presentedDream = nil })
        }
        .sheet(item: $helpForDream, onDismiss: restoreFeedAfterPresentation) { d in
            HelpSheet(dream: d, onClose: { helpForDream = nil })
                .pausesDiscoverFeed()
        }
        .sheet(item: $shareDream, onDismiss: restoreFeedAfterPresentation) { d in
            InAppShareSheet(
                dream: d,
                onClose: { shareDream = nil },
                onSent: { name in showShareToast("Sent to \(name)") }
            )
            .pausesDiscoverFeed()
        }
        .fullScreenCover(item: $profileForUser, onDismiss: restoreFeedAfterPresentation) { userId in
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
                .padding(.bottom, DreamTheme.Layout.tabBarClearance)
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

    private func dreamIndex(forSlot slot: Int) -> Int {
        guard !dreams.isEmpty else { return 0 }
        return ((slot % dreams.count) + dreams.count) % dreams.count
    }

    private func slotForDreamIndex(_ index: Int) -> Int {
        guard dreams.count > 1 else { return index }
        return middleCycle * dreams.count + dreamIndex(forSlot: index)
    }

    private func ensureCurrentSlot() {
        guard !dreams.isEmpty else {
            currentSlot = nil
            return
        }
        guard dreams.count > 1 else {
            currentSlot = 0
            return
        }
        guard let slot = currentSlot, slot >= 0, slot < virtualFeedCount else {
            currentSlot = initialSlotIndex
            return
        }
        if slot / dreams.count != middleCycle {
            currentSlot = slotForDreamIndex(dreamIndex(forSlot: slot))
        }
    }

    private func normalizeLoopSlotIfNeeded() {
        guard dreams.count > 1, let slot = currentSlot else { return }
        let cycle = slot / dreams.count
        guard cycle == 0 || cycle == feedCycleCount - 1 else { return }
        let normalized = slotForDreamIndex(dreamIndex(forSlot: slot))
        guard normalized != slot else { return }
        DispatchQueue.main.async {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                currentSlot = normalized
            }
        }
    }

    private func restoreFeedAfterPresentation() {
        activeTab.wrappedValue = .discover
        recenterFeed()
        DispatchQueue.main.async {
            recenterFeed()
        }
    }

    private func recenterFeed() {
        guard !dreams.isEmpty else { return }
        let normalized = slotForDreamIndex(currentIndex)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            currentSlot = normalized
            feedResetToken = UUID()
        }
        markFeedActive()
    }

    // MARK: - Feed

    private var feed: some View {
        GeometryReader { geo in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(0..<virtualFeedCount, id: \.self) { slot in
                        let d = dreams[dreamIndex(forSlot: slot)]
                        cardView(d, geo: geo, safeTop: geo.safeAreaInsets.top,
                                 isActive: slot == currentSlotIndex)
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: Binding(
                get: { currentSlot ?? initialSlotIndex },
                set: { currentSlot = $0 }
            ))
            .scrollIndicators(.hidden)
            .ignoresSafeArea()
            .id(feedResetToken)
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

            // Only the centered card gets chrome. If SwiftUI briefly restores the
            // paged ScrollView between slots after a sheet dismissal, neighboring
            // virtual copies stay visual-only instead of showing duplicate controls.
            if isActive && !cleanDisplay {
                topGradient
                bottomGradient

                VStack(alignment: .leading, spacing: 0) {
                    // Reserve space for the fixed top bar that sits above all cards.
                    // safeTop (status bar) + 8pt (bar padding) + ~40pt (bar height)
                    Color.clear.frame(height: safeTop + 48)

                    Spacer(minLength: 24)

                    HStack(alignment: .bottom, spacing: 12) {
                        bottomInfo(for: d)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        rightRail(for: d)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, DreamTheme.Layout.tabBarClearance)
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
                circleButton(
                    systemImage: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    accessibilityLabel: isMuted ? "Unmute video" : "Mute video"
                ) {
                    isMuted.toggle()
                }
                // Clears all overlay chrome so the video fills the screen.
                // Tap the × corner button that appears to restore the UI.
                circleButton(systemImage: "arrow.up.left.and.arrow.down.right", accessibilityLabel: "Hide controls") {
                    withAnimation(.easeInOut(duration: 0.22)) { cleanDisplay = true }
                }
            }
        }
    }

    private func circleButton(systemImage: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        GlassCircleButton(
            systemName: systemImage,
            accessibilityLabel: accessibilityLabel,
            size: 40,
            background: Color.white.opacity(0.16),
            action: action
        )
        .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
    }

    private func bottomInfo(for d: Dream) -> some View {
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

            authorRow(for: d)

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

            if !d.displayDescription.isEmpty {
                descriptionBlock(for: d)
            }
        }
    }

    @ViewBuilder
    private func descriptionBlock(for d: Dream) -> some View {
        let text = d.displayDescription
        let expanded = expandedDesc.contains(d.feedID)
        let long = text.count > 90

        if expanded || !long {
            Text(text)
                .font(DreamTheme.Font.text(13))
                .foregroundStyle(.white.opacity(0.9))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            let snippet = String(text.prefix(90))
            let moreText = Text("more")
                .font(DreamTheme.Font.text(13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.65))

            Text("\(snippet)… \(moreText)")
                .font(DreamTheme.Font.text(13))
                .foregroundStyle(Color.white.opacity(0.9))
                .lineSpacing(2)
            .onTapGesture {
                let id = d.feedID
                withAnimation(.easeInOut(duration: 0.2)) {
                    _ = expandedDesc.insert(id)
                }
            }
        }
    }

    private func rightRail(for d: Dream) -> some View {
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

    private func authorRow(for d: Dream) -> some View {
        HStack(spacing: 8) {
            Button { profileForUser = d.ownerId } label: {
                Avatar(name: d.name, seed: d.avatarSeed, size: 34, url: d.avatarURL)
                    .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.28), radius: 7, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(d.name)'s profile")

            Button { profileForUser = d.ownerId } label: {
                Text("@\(d.handle)")
                    .font(DreamTheme.Font.text(14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.94))
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open @\(d.handle)'s profile")

            if !isOwnDream(d) {
                FollowButton(
                    isFollowing: isFollowingOwner(d),
                    style: .feed,
                    isBusy: followBusyOwners.contains(d.ownerId)
                ) {
                    toggleFollow(for: d)
                }
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
