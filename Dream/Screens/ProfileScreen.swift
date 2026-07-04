import Combine
import SwiftUI

/// A user's profile: header (avatar, name, @handle, location, skills, stats),
/// a featured "main" dream with its video, and that dream's other clips.
/// Reused for the current user (Profile tab) and any author opened from Discover.
struct ProfileScreen: View {
    let userId: UUID
    /// When true, shows edit/sign-out controls instead of a follow button.
    var isCurrentUser: Bool = false
    /// When provided, a back chevron is shown (i.e. presented over the feed).
    var onBack: (() -> Void)? = nil

    @StateObject private var model = ProfileViewModel()
    @ObservedObject private var auth = AuthService.shared
    @ObservedObject private var feedRepo = DreamRepository.shared
    @ObservedObject private var savedStore = SavedDreamsStore.shared
    @State private var presentedDream: Dream?
    @State private var playingMedia: DreamMedia?
    @State private var editing = false
    @State private var postingUpdate = false
    @State private var profileTab: ProfileTab = .dreams
    @State private var shareFromSaved: Dream?

    enum ProfileTab { case dreams, updates, saved }

    var body: some View {
        ZStack(alignment: .top) {
            DreamTheme.paper.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header.padding(.top, onBack == nil ? 60 : 64)
                    if !model.skills.isEmpty {
                        skills.padding(.top, 20)
                    }
                    stats.padding(.top, 22)
                    profileTabBar.padding(.top, 26)
                    Divider().background(DreamTheme.line)

                    switch profileTab {
                    case .dreams:
                        mainDreamSection.padding(.top, 20)
                        Divider().background(DreamTheme.line).padding(.top, 28)
                        DreamAchievementsView(dream: model.featuredDream)
                            .padding(.top, 24)
                    case .updates:
                        updatesGrid.padding(.top, 12)
                    case .saved:
                        savedGrid.padding(.top, 12)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
            }

            if let onBack {
                topBar(onBack: onBack)
            }
        }
        .task(id: userId) { await model.load(userId: userId, isCurrentUser: isCurrentUser) }
        // When pushed over the discover feed (onBack != nil), pause the feed
        // video so it doesn't keep playing behind this profile; resume on close.
        .onAppear { if onBack != nil { FeedVideoPreloader.shared.pauseFeedPlayer() } }
        .onDisappear { if onBack != nil { FeedVideoPreloader.shared.resumeFeedPlayer() } }
        .fullScreenCover(item: $presentedDream) { d in
            DreamDetailScreen(dream: d, onBack: { presentedDream = nil })
        }
        .fullScreenCover(item: $playingMedia) { m in
            MediaVideoPlayer(media: m, onClose: { playingMedia = nil })
        }
        .fullScreenCover(isPresented: $postingUpdate) {
            if let dream = model.featuredDream {
                PostUpdateScreen(
                    dream: dream,
                    onClose: { postingUpdate = false },
                    onPosted: {
                        postingUpdate = false
                        Task { await model.reload(userId: userId, isCurrentUser: isCurrentUser) }
                    }
                )
            }
        }
        .sheet(item: $shareFromSaved) { d in
            InAppShareSheet(dream: d, onClose: { shareFromSaved = nil })
        }
        .sheet(isPresented: $editing) {
            EditProfileScreen(
                userId: userId,
                name: model.name,
                handle: model.handle,
                location: model.location,
                skills: model.skills,
                avatarSeed: model.avatarSeed,
                avatarURL: model.avatarURL,
                dreams: model.dreams,
                onSaved: {
                    editing = false
                    Task { await model.reload(userId: userId, isCurrentUser: isCurrentUser) }
                },
                onCancel: {
                    editing = false
                    // The avatar persists immediately (independent of the text save),
                    // so reflect any change even when the user cancels the form.
                    Task { await model.reload(userId: userId, isCurrentUser: isCurrentUser) }
                }
            )
        }
        // Only the pushed-over-feed profile (onBack != nil) gets edge-swipe back;
        // the root profile tab is reached by tab/page swipe instead.
        .modifier(ConditionalBackSwipe(onBack: onBack))
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                Avatar(name: model.name, seed: model.avatarSeed, size: 76, url: model.avatarURL)
                    .overlay(Circle().strokeBorder(DreamTheme.line, lineWidth: 1))

                VStack(alignment: .leading, spacing: 3) {
                    Text(model.name)
                        .font(DreamTheme.Font.display(26, weight: .regular))
                        .tracking(-0.5)
                        .foregroundStyle(DreamTheme.ink)
                    Text("@\(model.handle)")
                        .font(DreamTheme.Font.text(14, weight: .medium))
                        .foregroundStyle(DreamTheme.ink2)
                    if !model.location.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 11))
                            Text(model.location)
                                .font(DreamTheme.Font.text(13))
                        }
                        .foregroundStyle(DreamTheme.ink3)
                        .padding(.top, 1)
                    }
                }
                Spacer(minLength: 0)
            }

            actionButton
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if isCurrentUser {
            HStack(spacing: 10) {
                Button { editing = true } label: {
                    Text("Edit Profile")
                        .font(DreamTheme.Font.text(14, weight: .semibold))
                        .foregroundStyle(DreamTheme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .overlay(Capsule().stroke(DreamTheme.line, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button { Task { await auth.signOut() } } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DreamTheme.ink2)
                        .frame(width: 44, height: 44)
                        .overlay(Circle().stroke(DreamTheme.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Sign out")
            }
        } else {
            FollowButton(isFollowing: model.isFollowing, style: .fullWidth) {
                Task { await model.toggleFollow(userId: userId) }
            }
        }
    }

    // MARK: - Skills

    private var skills: some View {
        VStack(alignment: .leading, spacing: 10) {
            eyebrow("Skills")
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(model.skills, id: \.self) { skill in
                    Text(skill)
                        .font(DreamTheme.Font.text(13, weight: .semibold))
                        .foregroundStyle(DreamTheme.blueDeep)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(DreamTheme.blueSoft))
                }
            }
        }
    }

    // MARK: - Stats

    private var stats: some View {
        HStack(spacing: 10) {
            StatCell(value: "\(model.videosCount)", label: "Videos")
            StatCell(value: "\(model.followersCount)", label: "Followers")
            StatCell(value: "\(model.offersCount)", label: "Offers")
        }
        .padding(.vertical, 16)
        .overlay(alignment: .top) { Rectangle().fill(DreamTheme.line).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(DreamTheme.line).frame(height: 1) }
    }

    // MARK: - Profile tab bar (Dreams / Updates)

    private var profileTabBar: some View {
        HStack(spacing: 0) {
            tabBarButton("Dreams", icon: "play.square.stack", tab: .dreams)
            tabBarButton("Updates", icon: "square.grid.2x2", tab: .updates)
            tabBarButton("Saved", icon: "bookmark.fill", tab: .saved)
        }
    }

    private func tabBarButton(_ label: String, icon: String, tab: ProfileTab) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { profileTab = tab }
        } label: {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: profileTab == tab ? .semibold : .regular))
                    Text(label)
                        .font(DreamTheme.Font.text(14, weight: profileTab == tab ? .semibold : .regular))
                }
                .foregroundStyle(profileTab == tab ? DreamTheme.ink : DreamTheme.ink3)
                Rectangle()
                    .fill(profileTab == tab ? DreamTheme.ink : Color.clear)
                    .frame(height: 1.5)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Updates grid (daily life posts from this user)

    @ViewBuilder
    private var updatesGrid: some View {
        let userPosts = ExplorePost.mock.filter { $0.handle == model.handle }

        if userPosts.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(DreamTheme.ink3)
                Text("No updates yet.")
                    .font(DreamTheme.Font.text(14))
                    .foregroundStyle(DreamTheme.ink2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 48)
        } else {
            ThreeColumnGrid {
                ForEach(userPosts) { post in
                    PostGridCell(post: post)
                }
            }
        }
    }

    // MARK: - Saved grid

    @ViewBuilder
    private var savedGrid: some View {
        let saved = feedRepo.dreams.filter { savedStore.isSaved($0.feedID) }

        if saved.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "bookmark")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(DreamTheme.ink3)
                Text("No saved videos yet.")
                    .font(DreamTheme.Font.text(14))
                    .foregroundStyle(DreamTheme.ink2)
                Text("Tap the bookmark on any video in the feed.")
                    .font(DreamTheme.Font.text(13))
                    .foregroundStyle(DreamTheme.ink3)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 48)
            .padding(.horizontal, 20)
        } else {
            ThreeColumnGrid {
                ForEach(saved) { dream in
                    ZStack(alignment: .topTrailing) {
                        savedCell(dream)
                            .onTapGesture { presentedDream = dream }

                        Button { shareFromSaved = dream } label: {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(7)
                                .background(DreamTheme.blue.opacity(0.85), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Send saved video")
                        .padding(5)
                    }
                    .aspectRatio(1, contentMode: .fit)
                }
            }
        }
    }

    private func savedCell(_ dream: Dream) -> some View {
        ZStack(alignment: .bottomLeading) {
            PosterImage(url: dream.posterURL, category: dream.category)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .center, endPoint: .bottom)

            Image(systemName: "bookmark.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
                .padding(5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
    }

    // MARK: - Main dream

    @ViewBuilder
    private var mainDreamSection: some View {
        if model.isLoading && model.featuredDream == nil {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else if let dream = model.featuredDream {
            VStack(alignment: .leading, spacing: 14) {
                eyebrow(isCurrentUser ? "My Dream" : "Their Dream")
                mainVideoCard(dream)
                if isCurrentUser {
                    postUpdateButton
                }
                if !model.otherVideos.isEmpty {
                    moreVideos
                }
            }
        } else {
            emptyState
        }
    }

    private func mainVideoCard(_ dream: Dream) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if dream.videoStoragePath != nil {
                        DreamVideoBackground(dream: dream, isMuted: true)
                    } else if dream.posterURL != nil {
                        PosterImage(url: dream.posterURL, category: dream.category)
                    } else {
                        ScenePoster(category: dream.category)
                    }
                }
                .frame(height: 440)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                LinearGradient(
                    colors: [.clear, .black.opacity(0.55)],
                    startPoint: .center, endPoint: .bottom
                )
                .frame(height: 440)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 10) {
                    CategoryBadge(category: dream.category, dark: true)
                    Text(dream.title)
                        .font(DreamTheme.Font.display(24, weight: .regular))
                        .tracking(-0.4)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Button { presentedDream = dream } label: {
                        HStack(spacing: 6) {
                            Text("View dream")
                            Image(systemName: "arrow.right")
                        }
                        .font(DreamTheme.Font.text(13, weight: .semibold))
                        .foregroundStyle(DreamTheme.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(.white))
                    }
                    .buttonStyle(.plain)
                }
                .padding(18)
                .allowsHitTesting(true)
            }
        }
    }

    private var postUpdateButton: some View {
        Button { postingUpdate = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text("Post an update")
            }
            .font(DreamTheme.Font.text(14, weight: .semibold))
            .foregroundStyle(DreamTheme.blueDeep)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Capsule().fill(DreamTheme.blueSoft))
        }
        .buttonStyle(.plain)
    }

    private var moreVideos: some View {
        VStack(alignment: .leading, spacing: 10) {
            eyebrow("More from this dream")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(model.otherVideos) { media in
                        Button { playingMedia = media } label: {
                            clipThumbnail(media, category: model.featuredDream?.category ?? .tech)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func clipThumbnail(_ media: DreamMedia, category: DreamCategory) -> some View {
        ZStack {
            PosterImage(url: media.posterURL, category: category)
            Image(systemName: "play.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(.white.opacity(0.9))
                .shadow(color: .black.opacity(0.35), radius: 6)
        }
        .frame(width: 124, height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DreamTheme.line, lineWidth: 0.5))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "moon.stars")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(DreamTheme.ink3)
            Text(isCurrentUser ? "You haven't shared a dream yet." : "No dreams yet.")
                .font(DreamTheme.Font.text(14))
                .foregroundStyle(DreamTheme.ink2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Top bar (over-feed presentation)

    private func topBar(onBack: @escaping () -> Void) -> some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DreamTheme.ink)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.9), in: Circle())
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(DreamTheme.line, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 56)
    }

    private func eyebrow(_ text: String) -> some View {
        EyebrowLabel(text: text)
    }
}

/// Owns the loaded profile + featured dream + stats for a `ProfileScreen`.
@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var name = ""
    @Published var handle = ""
    @Published var location = ""
    @Published var avatarSeed = 0
    @Published var avatarURL: URL?
    @Published var skills: [String] = []
    @Published var dreams: [Dream] = []
    @Published var featuredDream: Dream?
    @Published var otherVideos: [DreamMedia] = []
    @Published var videosCount = 0
    @Published var followersCount = 0
    @Published var offersCount = 0
    @Published var isFollowing = false
    @Published var isLoading = false

    private var loadedUserId: UUID?

    func load(userId: UUID, isCurrentUser: Bool) async {
        guard loadedUserId != userId else { return }
        await reload(userId: userId, isCurrentUser: isCurrentUser)
    }

    func reload(userId: UUID, isCurrentUser: Bool) async {
        loadedUserId = userId
        isLoading = true
        defer { isLoading = false }

        async let profile = ProfileRepository.shared.profile(userId: userId)
        async let dreams = DreamRepository.shared.dreams(ownedBy: userId)
        async let stats = ProfileRepository.shared.stats(userId: userId)
        async let following = isCurrentUser ? false : ProfileRepository.shared.isFollowing(userId)
        let (p, d, s, f) = await (profile, dreams, stats, following)

        if let p {
            name = p.name ?? "Dreamer"
            handle = p.handle ?? "anon"
            location = p.location ?? ""
            avatarSeed = p.avatarSeed
            avatarURL = p.avatarURLValue
            skills = p.skills
        } else if let first = d.first {
            // Fall back to the author info embedded in their dreams.
            name = first.name
            handle = first.handle
            location = first.location
            avatarSeed = first.avatarSeed
            avatarURL = first.avatarURL
        }
        self.dreams = d
        videosCount = s?.videosCount ?? 0
        followersCount = s?.followersCount ?? 0
        offersCount = s?.offersCount ?? 0
        isFollowing = f

        // Featured dream = the one the user pinned, else their most recent.
        let featured = d.first(where: { $0.isFeatured }) ?? d.first
        featuredDream = featured
        await loadOtherVideos(for: featured)
    }

    private func loadOtherVideos(for dream: Dream?) async {
        guard let dream else { otherVideos = []; return }
        let videos = await DreamRepository.shared.videos(forDream: dream.id)
        otherVideos = videos.filter { !$0.isPrimary }
    }

    func toggleFollow(userId: UUID) async {
        let wasFollowing = isFollowing
        isFollowing.toggle()
        followersCount += wasFollowing ? -1 : 1
        do {
            if wasFollowing {
                try await ProfileRepository.shared.unfollow(userId)
            } else {
                try await ProfileRepository.shared.follow(userId)
            }
        } catch {
            // Revert on failure.
            isFollowing = wasFollowing
            followersCount += wasFollowing ? 1 : -1
        }
    }
}
