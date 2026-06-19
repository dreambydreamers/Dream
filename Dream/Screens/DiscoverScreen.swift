import SwiftUI

struct DiscoverScreen: View {
    @StateObject private var repo = DreamRepository.shared
    @ObservedObject private var auth = AuthService.shared
    /// Shrinks the floating tab bar while the user pages through the feed.
    var tabBarCollapsed: Binding<Bool> = .constant(false)
    @State private var index: Int = 0
    @State private var supporterMode: Bool = true
    @State private var supporterSkills: [String] = ["Design", "Funding"]
    @State private var presentedDream: Dream?
    @State private var helpForDream: Dream?
    @State private var shareDream: Dream?
    @State private var profileForUser: UUID?
    @State private var isMuted: Bool = false
    @StateObject private var videoActions = VideoActionsModel()
    @State private var followedOwners: Set<UUID> = []
    @State private var loadedFollowOwners: Set<UUID> = []
    @State private var followBusyOwners: Set<UUID> = []
    @State private var shareToast: String?
    @State private var shareToastTask: Task<Void, Never>?

    private var dreams: [Dream] { repo.dreams }
    private var dream: Dream { dreams[index % dreams.count] }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if dreams.isEmpty {
                placeholder
            } else {
                feed
            }
        }
        .task {
            if repo.dreams.isEmpty { await repo.loadFeed() }
            FeedVideoPreloader.shared.prefetchNeighbors(of: dreams, around: index)
            markFeedActive()
            if !dreams.isEmpty { await refreshFollowState(for: dream) }
        }
        // The feed view persists inside the paged TabView, so `.task` won't fire
        // again when paging back here — re-mark the feed active on every appear
        // so its video resumes after a tab switch.
        .onAppear { markFeedActive() }
        .onChange(of: index) { _, newIndex in
            FeedVideoPreloader.shared.prefetchNeighbors(of: dreams, around: newIndex)
            markFeedActive()
            if !dreams.isEmpty { Task { await refreshFollowState(for: dream) } }
        }
        .onChange(of: repo.dreams.count) { _, _ in
            FeedVideoPreloader.shared.prefetchNeighbors(of: dreams, around: index)
            markFeedActive()
            if !dreams.isEmpty { Task { await refreshFollowState(for: dream) } }
        }
        .onChange(of: isMuted) { _, muted in
            FeedVideoPreloader.shared.feedMuted = muted
        }
        .onDisappear {
            // The feed has left the screen (tab switch) — not merely covered by a
            // detail/profile sheet, which doesn't fire onDisappear. Stop driving
            // the feed player so a covering screen never resumes an off-screen feed.
            FeedVideoPreloader.shared.feedActiveID = nil
        }
        .fullScreenCover(item: $presentedDream) { d in
            DreamDetailScreen(
                dream: d,
                onBack: { presentedDream = nil }
            )
        }
        .sheet(item: $helpForDream) { d in
            HelpSheet(dream: d, onClose: { helpForDream = nil })
                .pausesDiscoverFeed()
        }
        .sheet(item: $shareDream) { d in
            InAppShareSheet(
                dream: d,
                onClose: { shareDream = nil },
                onSent: { name in showShareToast("Sent to \(name)") }
            )
            .pausesDiscoverFeed()
        }
        .fullScreenCover(item: $profileForUser) { userId in
            ProfileScreen(userId: userId, onBack: { profileForUser = nil })
        }
        .videoActions(videoActions)
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

    /// Tell the preloader which feed card is on screen so a covering detail/
    /// profile page can pause + resume it (see `FeedVideoPreloader.feedActiveID`).
    private func markFeedActive() {
        guard !dreams.isEmpty else { return }
        FeedVideoPreloader.shared.feedActiveID = dream.feedID
        FeedVideoPreloader.shared.feedMuted = isMuted
    }

    // MARK: - Feed

    private var feed: some View {
        ZStack {
            DreamVideoBackground(dream: dream, isMuted: isMuted)
                .ignoresSafeArea()
                .id(dream.feedID)
                .transition(.opacity)

            topGradient
            bottomGradient

            GeometryReader { geo in
                VStack(alignment: .leading, spacing: 0) {
                    topBar
                    if supporterMode {
                        supporterBanner.padding(.top, 10)
                    }
                    if let matchedSkill = dream.matched(against: supporterSkills), supporterMode {
                        matchBadge(matchedSkill).padding(.top, 10)
                    }

                    Spacer(minLength: 24)

                    HStack(alignment: .bottom, spacing: 12) {
                        bottomInfo
                            .frame(maxWidth: .infinity, alignment: .leading)
                        rightRail
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 132)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            }
        }
        .contentShape(Rectangle())
        // Simultaneous + vertical-guarded so horizontal swipes pass through to
        // the paged TabView (tab switching) while vertical swipes page the feed.
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    guard abs(value.translation.height) > abs(value.translation.width) else { return }
                    if value.translation.height < -60 {
                        tabBarCollapsed.wrappedValue = true
                        withAnimation(.easeInOut(duration: 0.35)) {
                            index = (index + 1) % dreams.count
                        }
                    } else if value.translation.height > 60 {
                        tabBarCollapsed.wrappedValue = true
                        withAnimation(.easeInOut(duration: 0.35)) {
                            index = (index - 1 + dreams.count) % dreams.count
                        }
                    }
                }
        )
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
                circleButton(systemImage: "slider.horizontal.3") {}
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

    private var supporterBanner: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: 0x8AD3A7))
                .frame(width: 8, height: 8)
                .shadow(color: Color(hex: 0x8AD3A7), radius: 4)
            Text("Supporter mode · matching")
                .font(DreamTheme.Font.text(12))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                ForEach(supporterSkills, id: \.self) { s in
                    Text(s)
                        .font(DreamTheme.Font.text(11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.2), in: Capsule())
                }
            }
            .fixedSize()
            .layoutPriority(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
        )
    }

    private func matchBadge(_ skill: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "star.fill")
                .font(.system(size: 11, weight: .bold))
            Text("\(skill) match")
                .font(DreamTheme.Font.text(12, weight: .bold))
        }
        .foregroundStyle(Color(hex: 0x1F4731))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(hex: 0x8AD3A7), in: Capsule())
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bottomInfo: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                CategoryBadge(category: dream.category, dark: true)
                HStack(spacing: 4) {
                    Text("◐")
                    Text(dream.stage.rawValue)
                }
                .font(DreamTheme.Font.text(12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.18), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5))
            }

            authorRow

            Button { presentedDream = dream } label: {
                Text(dream.displayTitle)
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
                .fill(dream.category.palette.fg)
                .frame(width: 36, height: 3)
                .clipShape(Capsule())
                .shadow(color: dream.category.palette.fg.opacity(0.7), radius: 6)

            if !dream.desc.isEmpty {
                Text(descriptionWithMore)
                    .font(DreamTheme.Font.text(13))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineSpacing(2)
                    .lineLimit(2)
            }
        }
    }

    private var descriptionWithMore: AttributedString {
        let snippet = String(dream.desc.prefix(90)) + "... "
        var s = AttributedString(snippet)
        s.foregroundColor = .white.opacity(0.9)
        var more = AttributedString("more")
        more.foregroundColor = .white.opacity(0.7)
        more.font = DreamTheme.Font.text(13, weight: .semibold)
        return s + more
    }

    private var rightRail: some View {
        VStack(spacing: 16) {
            let matched = dream.matched(against: supporterSkills) != nil && supporterMode
            ActionButton(
                systemImage: "heart.fill",
                label: matched ? "Offer \(dream.matched(against: supporterSkills) ?? "")" : "I can help",
                highlight: matched,
                action: { helpForDream = dream }
            )
            ActionButton(systemImage: "paperplane.fill", label: "Send") {
                shareDream = dream
            }
            ActionButton(systemImage: "bookmark.fill", label: "Save") {
                videoActions.save(storagePath: dream.videoStoragePath)
            }
        }
        .frame(width: 64)
    }

    private var authorRow: some View {
        HStack(spacing: 8) {
            Button { profileForUser = dream.ownerId } label: {
                Avatar(name: dream.name, seed: dream.avatarSeed, size: 34, url: dream.avatarURL)
                    .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.28), radius: 7, y: 2)
            }
            .buttonStyle(.plain)

            Button { profileForUser = dream.ownerId } label: {
                Text("@\(dream.handle)")
                    .font(DreamTheme.Font.text(14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.94))
                    .lineLimit(1)
            }
            .buttonStyle(.plain)

            if !isOwnDream {
                Button { toggleFollow() } label: {
                    Text(isFollowingOwner ? "Following" : "Follow")
                        .font(DreamTheme.Font.text(12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(Color.white.opacity(0.18))
                        )
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .disabled(followBusyOwners.contains(dream.ownerId))
            }

            if !dream.distance.isEmpty {
                Circle().fill(.white.opacity(0.5)).frame(width: 3, height: 3)
                Text(dream.distance)
                    .font(DreamTheme.Font.text(14))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }
        }
    }

    private var isOwnDream: Bool {
        auth.userId == dream.ownerId
    }

    private var isFollowingOwner: Bool {
        followedOwners.contains(dream.ownerId)
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

    private func toggleFollow() {
        guard !isOwnDream, !followBusyOwners.contains(dream.ownerId) else { return }
        let ownerId = dream.ownerId
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
                if wasFollowing {
                    followedOwners.insert(ownerId)
                } else {
                    followedOwners.remove(ownerId)
                }
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
