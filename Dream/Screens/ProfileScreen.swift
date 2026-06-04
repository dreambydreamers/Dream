import Combine
import SwiftUI

/// A user's profile: header (avatar, name, handle, location, skills, stats) and a
/// grid of their dreams. Reused for the current user (Profile tab) and for any
/// author opened from the Discover feed.
struct ProfileScreen: View {
    let userId: UUID
    /// When true, shows the sign-out control instead of a follow button.
    var isCurrentUser: Bool = false
    /// When provided, a back chevron is shown (i.e. presented over the feed).
    var onBack: (() -> Void)? = nil

    @StateObject private var model = ProfileViewModel()
    @ObservedObject private var auth = AuthService.shared
    @State private var presentedDream: Dream?
    @State private var following = false

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
                    dreamsSection.padding(.top, 26)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
            }

            if let onBack {
                topBar(onBack: onBack)
            }
        }
        .task(id: userId) { await model.load(userId: userId) }
        .fullScreenCover(item: $presentedDream) { d in
            DreamDetailScreen(dream: d, onBack: { presentedDream = nil })
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                Avatar(name: model.name, seed: model.avatarSeed, size: 76)
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
            Button {
                Task { await auth.signOut() }
            } label: {
                Text("Sign out")
                    .font(DreamTheme.Font.text(14, weight: .semibold))
                    .foregroundStyle(DreamTheme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .overlay(Capsule().stroke(DreamTheme.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
        } else {
            Button { following.toggle() } label: {
                Text(following ? "Following" : "Follow")
                    .font(DreamTheme.Font.text(14, weight: .semibold))
                    .foregroundStyle(following ? DreamTheme.blueDeep : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(following ? Color.white : DreamTheme.blue))
                    .overlay(Capsule().strokeBorder(DreamTheme.blue, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
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
            statCell("\(model.dreams.count)", "Dreams")
            statCell("\(model.totalSupporters)", "Supporters")
            statCell("\(model.totalOffers)", "Offers")
        }
        .padding(.vertical, 16)
        .overlay(alignment: .top) { Rectangle().fill(DreamTheme.line).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(DreamTheme.line).frame(height: 1) }
    }

    private func statCell(_ n: String, _ l: String) -> some View {
        VStack(spacing: 2) {
            Text(n)
                .font(DreamTheme.Font.display(22, weight: .medium))
                .foregroundStyle(DreamTheme.ink)
            Text(l.uppercased())
                .font(DreamTheme.Font.text(11, weight: .semibold))
                .tracking(0.3)
                .foregroundStyle(DreamTheme.ink2)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Dreams grid

    private var dreamsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            eyebrow(isCurrentUser ? "My Dreams" : "Dreams")

            if model.isLoading && model.dreams.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else if model.dreams.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                    GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(model.dreams) { dream in
                        Button { presentedDream = dream } label: {
                            DreamGridCard(dream: dream)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
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
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 56)
    }

    private func eyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .font(DreamTheme.Font.text(11, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(DreamTheme.ink2)
    }
}

/// Square dream thumbnail used in the profile grid.
private struct DreamGridCard: View {
    let dream: Dream

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                poster
                CategoryBadge(category: dream.category, dark: true)
                    .padding(8)
            }
            .frame(height: 150)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text(dream.title)
                .font(DreamTheme.Font.display(15, weight: .regular))
                .foregroundStyle(DreamTheme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var poster: some View {
        if let url = dream.posterURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    ScenePoster(category: dream.category)
                }
            }
        } else {
            ScenePoster(category: dream.category)
        }
    }
}

/// Owns the loaded profile + dreams for a `ProfileScreen`.
@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var name = ""
    @Published var handle = ""
    @Published var location = ""
    @Published var avatarSeed = 0
    @Published var skills: [String] = []
    @Published var dreams: [Dream] = []
    @Published var isLoading = false

    var totalSupporters: Int { dreams.reduce(0) { $0 + $1.supporters } }
    var totalOffers: Int { dreams.reduce(0) { $0 + $1.offers } }

    private var loadedUserId: UUID?

    func load(userId: UUID) async {
        guard loadedUserId != userId else { return }
        loadedUserId = userId
        isLoading = true
        defer { isLoading = false }

        async let profile = ProfileRepository.shared.profile(userId: userId)
        async let dreams = DreamRepository.shared.dreams(ownedBy: userId)
        let (p, d) = await (profile, dreams)

        if let p {
            name = p.name ?? "Dreamer"
            handle = p.handle ?? "anon"
            location = p.location ?? ""
            avatarSeed = p.avatarSeed
            skills = p.skills
        } else if let first = d.first {
            // Fall back to the author info embedded in their dreams.
            name = first.name
            handle = first.handle
            location = first.location
            avatarSeed = first.avatarSeed
        }
        self.dreams = d
    }
}
