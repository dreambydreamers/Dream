import SwiftUI

struct DreamDetailScreen: View {
    let dream: Dream
    var onBack: () -> Void = {}

    /// The dream whose video the hero plays — the dream's *main* (primary/cover)
    /// clip. Starts as the incoming `dream` and, for update-clip cards, is
    /// refined to the primary video by `resolveMainVideo()`.
    @State private var heroDream: Dream
    /// Drives the "I can help" sheet, presented over this detail page.
    @State private var helpForDream: Dream?
    /// Drives navigation to the dream author's profile (tap avatar/name).
    @State private var profileForUser: UUID?
    /// Hero video mute state, toggled by the speaker button. Starts unmuted.
    @State private var isMuted = false
    @State private var following = false
    @State private var followBusy = false
    @ObservedObject private var auth = AuthService.shared
    @StateObject private var videoActions = VideoActionsModel()

    init(dream: Dream, onBack: @escaping () -> Void = {}) {
        self.dream = dream
        self.onBack = onBack
        _heroDream = State(initialValue: dream)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            DreamTheme.paper.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                    VStack(alignment: .leading, spacing: 0) {
                        profileRow.padding(.bottom, 18)
                        title.padding(.bottom, 14)
                        badges.padding(.bottom, 22)
                        description.padding(.bottom, 28)
                        if !dream.journey.isEmpty {
                            journey.padding(.bottom, 28)
                        }
                        lookingFor.padding(.bottom, 24)
                        stats.padding(.bottom, 12)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 120)
                }
            }
            .ignoresSafeArea(edges: .top)

            stickyCTA
        }
        .task {
            await resolveMainVideo()
            await loadFollowState()
        }
        .onAppear { FeedVideoPreloader.shared.pauseFeedPlayer() }
        .onDisappear { FeedVideoPreloader.shared.resumeFeedPlayer() }
        .sheet(item: $helpForDream) { d in
            HelpSheet(dream: d, onClose: { helpForDream = nil })
        }
        .fullScreenCover(item: $profileForUser) { uid in
            ProfileScreen(userId: uid, onBack: { profileForUser = nil })
        }
        .interactiveBackSwipe { onBack() }
        .videoActions(videoActions)
    }

    /// When opened from a feed *update* card, the incoming `dream` points at the
    /// update clip. Resolve the dream's primary (main) video so the hero plays
    /// that instead. Cover cards / profile dreams (`videoTitle == nil`) already
    /// carry the main video, so no fetch is needed.
    private func resolveMainVideo() async {
        guard dream.videoTitle != nil else { return }
        let videos = await DreamRepository.shared.videos(forDream: dream.id)
        guard let primary = videos.first(where: { $0.isPrimary }) ?? videos.first else { return }
        var d = dream
        d.videoStoragePath = primary.storagePath
        d.videoId = primary.id
        d.posterURL = primary.posterURL
        d.videoTitle = nil
        heroDream = d
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack {
            Group {
                if heroDream.videoStoragePath != nil {
                    DreamVideoBackground(dream: heroDream, isMuted: isMuted)
                } else if heroDream.posterURL != nil {
                    PosterImage(url: heroDream.posterURL, category: heroDream.category)
                } else {
                    ScenePoster(category: heroDream.category)
                }
            }
            .aspectRatio(16.0/11.0, contentMode: .fill)
            .frame(maxWidth: .infinity)
            .clipped()

            VStack {
                HStack {
                    GlassCircleButton(systemName: "chevron.left", accessibilityLabel: "Back", action: onBack)
                    Spacer()
                    if heroDream.videoStoragePath != nil {
                        GlassCircleButton(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", accessibilityLabel: isMuted ? "Unmute video" : "Mute video") {
                            isMuted.toggle()
                        }
                        GlassCircleButton(systemName: "arrow.down.to.line", accessibilityLabel: "Save video") {
                            videoActions.save(storagePath: heroDream.videoStoragePath)
                        }
                        GlassCircleButton(systemName: "square.and.arrow.up", accessibilityLabel: "Share video") {
                            videoActions.share(storagePath: heroDream.videoStoragePath)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 56)
                Spacer()
            }
        }
    }

    // MARK: - Profile

    private var profileRow: some View {
        HStack(spacing: 12) {
            Button { profileForUser = dream.ownerId } label: {
                HStack(spacing: 12) {
                    Avatar(name: dream.name, seed: dream.avatarSeed, size: 44, url: dream.avatarURL)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(dream.name)
                            .font(DreamTheme.Font.text(15, weight: .semibold))
                            .foregroundStyle(DreamTheme.ink)
                        Text("\(dream.location) · Dreamer")
                            .font(DreamTheme.Font.text(12))
                            .foregroundStyle(DreamTheme.ink2)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
            if auth.userId != dream.ownerId {
                FollowButton(isFollowing: following, style: .detail, isBusy: followBusy) {
                    toggleFollow()
                }
            }
        }
    }

    private func loadFollowState() async {
        guard auth.userId != dream.ownerId else { return }
        following = await ProfileRepository.shared.isFollowing(dream.ownerId)
    }

    private func toggleFollow() {
        guard auth.userId != dream.ownerId, !followBusy else { return }
        let wasFollowing = following
        following.toggle()
        followBusy = true
        Task {
            do {
                if wasFollowing {
                    try await ProfileRepository.shared.unfollow(dream.ownerId)
                } else {
                    try await ProfileRepository.shared.follow(dream.ownerId)
                }
            } catch {
                following = wasFollowing
                print("[DreamDetailScreen] toggle follow failed: \(error)")
            }
            followBusy = false
        }
    }

    private var title: some View {
        Text(dream.title)
            .font(DreamTheme.Font.display(32, weight: .regular))
            .tracking(-0.7)
            .foregroundStyle(DreamTheme.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var badges: some View {
        HStack(spacing: 8) {
            CategoryBadge(category: dream.category)
            HStack(spacing: 4) {
                Text("◐")
                Text(dream.stage.rawValue)
            }
            .font(DreamTheme.Font.text(12, weight: .semibold))
            .foregroundStyle(Color(hex: 0x7A5828))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(DreamTheme.warm))
        }
    }

    private var description: some View {
        Text(dream.desc)
            .font(DreamTheme.Font.display(18))
            .foregroundStyle(DreamTheme.ink)
            .lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Journey

    private var journey: some View {
        VStack(alignment: .leading, spacing: 16) {
            eyebrow("The Journey")
            JourneyTimeline(steps: dream.journey, accent: dream.category.palette.fg)
        }
    }

    // MARK: - Looking for

    private var lookingFor: some View {
        VStack(alignment: .leading, spacing: 12) {
            eyebrow("Looking for")
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(dream.help, id: \.self) { h in
                    Text(h)
                        .font(DreamTheme.Font.text(13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(DreamTheme.blue))
                }
            }
        }
    }

    // MARK: - Stats

    private var stats: some View {
        HStack(spacing: 10) {
            StatCell(value: "\(dream.supporters)", label: "Supporters")
            StatCell(value: "\(dream.offers)", label: "Offers")
            StatCell(value: dream.viewsLabel, label: "Views")
        }
        .padding(.vertical, 16)
        .overlay(alignment: .top) { Rectangle().fill(DreamTheme.line).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(DreamTheme.line).frame(height: 1) }
    }

    // MARK: - CTA

    private var stickyCTA: some View {
        VStack(spacing: 0) {
            Rectangle().fill(DreamTheme.line).frame(height: 1)
            PrimaryButton(title: "I can help", icon: "heart.fill", background: dream.category.palette.fg) {
                helpForDream = dream
            }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 32)
        }
        .background(DreamTheme.paper)
    }

    private func eyebrow(_ text: String) -> some View {
        EyebrowLabel(text: text)
    }
}
