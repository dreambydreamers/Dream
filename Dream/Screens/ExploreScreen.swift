import SwiftUI

// MARK: - Mock post model

struct ExplorePost: Identifiable {
    let id = UUID()
    let authorName: String
    let handle: String
    let avatarSeed: Int
    let category: DreamCategory
    let caption: String
    let location: String
    let dreamTitle: String

    static let mock: [ExplorePost] = [
        .init(authorName: "Ana Marić", handle: "amaric", avatarSeed: 12,
              category: .tech, caption: "Late night lab sessions — testing our first drug candidate compound 🧬",
              location: "Zagreb", dreamTitle: "AI-powered drug discovery engine"),
        .init(authorName: "Erik Schmidt", handle: "erikbci", avatarSeed: 27,
              category: .tech, caption: "First successful signal from the neural array. Can't believe this is working.",
              location: "Berlin", dreamTitle: "Brain-computer interface for paralysis"),
        .init(authorName: "Mia Kovač", handle: "mia_music", avatarSeed: 5,
              category: .music, caption: "Teaching my first group of 7-year-olds with the AI system 🎹",
              location: "Vienna", dreamTitle: "AI music teacher for kids"),
        .init(authorName: "Sophie Visser", handle: "sophiev", avatarSeed: 33,
              category: .health, caption: "Biosensor array under electron microscope — beautiful and terrifying at once",
              location: "Amsterdam", dreamTitle: "Nanotech cancer early detection"),
        .init(authorName: "David Balogh", handle: "dbalogh", avatarSeed: 8,
              category: .sport, caption: "Training session with the national swim team today. The EEG data is incredible.",
              location: "Budapest", dreamTitle: "Neurofeedback training for athletes"),
        .init(authorName: "Tom Allen", handle: "tomallen", avatarSeed: 41,
              category: .music, caption: "First live rehearsal between London and Tokyo via the platform. Zero latency 🎻",
              location: "London", dreamTitle: "Live score collaboration network"),
        .init(authorName: "Jana Novak", handle: "jana_code", avatarSeed: 19,
              category: .education, caption: "Our quantum simulator just ran its first entanglement demo for high schoolers 🤯",
              location: "Prague", dreamTitle: "Quantum computing education platform"),
        .init(authorName: "Carlos Vega", handle: "carlosvega", avatarSeed: 56,
              category: .sport, caption: "Patient walked 3 meters today with the exoskeleton. First time in 4 years.",
              location: "Barcelona", dreamTitle: "Exoskeleton for motor rehabilitation"),
        .init(authorName: "Giulia Rossi", handle: "giulia_r", avatarSeed: 3,
              category: .impact, caption: "Sent 40 prosthetic hand designs to makers in rural Kenya this week 🤝",
              location: "Milan", dreamTitle: "Open-source prosthetics lab"),
        .init(authorName: "Luka Horvat", handle: "lukaferment", avatarSeed: 22,
              category: .health, caption: "CRISPR edit confirmed in vitro — the gene correction is holding 💉",
              location: "Ljubljana", dreamTitle: "Gene therapy for rare childhood diseases"),
        .init(authorName: "Claire Dubois", handle: "claired", avatarSeed: 37,
              category: .art, caption: "First public test of our black hole AR installation in Place du Palais-Royal",
              location: "Paris", dreamTitle: "Holographic science museum"),
        .init(authorName: "Piotr Wiśniewski", handle: "piotrw", avatarSeed: 14,
              category: .tech, caption: "Drone sensor grid over 200 hectares. Yield prediction is 94% accurate now.",
              location: "Warsaw", dreamTitle: "Precision agriculture AI"),
        .init(authorName: "Ana Marić", handle: "amaric", avatarSeed: 12,
              category: .tech, caption: "Paper submitted to Nature Methods. Two years of work in 14 pages 📄",
              location: "Zagreb", dreamTitle: "AI-powered drug discovery engine"),
        .init(authorName: "David Balogh", handle: "dbalogh", avatarSeed: 8,
              category: .sport, caption: "Alpha meditation state in under 90 seconds. New personal best for the team.",
              location: "Budapest", dreamTitle: "Neurofeedback training for athletes"),
        .init(authorName: "Mia Kovač", handle: "mia_music", avatarSeed: 5,
              category: .music, caption: "A student who couldn't read notes 3 months ago just played Chopin 🎶",
              location: "Vienna", dreamTitle: "AI music teacher for kids"),
    ]
}

// MARK: - Screen

struct ExploreScreen: View {
    @State private var searchText = ""
    @State private var selectedPost: ExplorePost? = nil
    @State private var profileForUser: UUID? = nil
    @ObservedObject private var searchRepo = SearchRepository.shared

    private var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ZStack(alignment: .top) {
            DreamTheme.paper.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 130)
                    if isSearching {
                        searchResultsContent
                    } else {
                        exploreGrid
                    }
                    Color.clear.frame(height: 120)
                }
            }
            .scrollDismissesKeyboard(.immediately)

            headerOverlay
        }
        .ignoresSafeArea(edges: .top)
        .onChange(of: searchText) { _, new in searchRepo.search(new) }
        .sheet(item: $selectedPost) { post in
            PostDetailSheet(post: post, onOpenProfile: { selectedPost = nil })
        }
        .fullScreenCover(item: $profileForUser) { uid in
            ProfileScreen(userId: uid, onBack: { profileForUser = nil })
        }
    }

    // MARK: - Search results

    @ViewBuilder private var searchResultsContent: some View {
        if searchRepo.isSearching {
            ProgressView().tint(DreamTheme.blue).padding(.top, 60)
        } else if searchRepo.profileResults.isEmpty && searchRepo.dreamResults.isEmpty {
            emptySearch
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if !searchRepo.profileResults.isEmpty {
                    searchSectionHeader("People")
                    ForEach(searchRepo.profileResults) { p in
                        profileSearchRow(p)
                        Divider().padding(.leading, 76).background(DreamTheme.line)
                    }
                }
                if !searchRepo.dreamResults.isEmpty {
                    searchSectionHeader("Dreams")
                    ForEach(searchRepo.dreamResults) { d in
                        dreamSearchRow(d)
                        Divider().padding(.leading, 76).background(DreamTheme.line)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func searchSectionHeader(_ title: String) -> some View {
        EyebrowLabel(text: title, color: DreamTheme.ink3)
            .padding(.top, 16)
            .padding(.bottom, 6)
    }

    private func profileSearchRow(_ p: SearchProfileResult) -> some View {
        Button { profileForUser = p.id } label: {
            HStack(spacing: 12) {
                Avatar(name: p.name ?? "Dreamer", seed: p.avatarSeed, size: 48, url: p.avatarURL)
                    .overlay(Circle().strokeBorder(DreamTheme.line, lineWidth: 1))
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.name ?? "Dreamer")
                        .font(DreamTheme.Font.text(15, weight: .semibold))
                        .foregroundStyle(DreamTheme.ink)
                    HStack(spacing: 6) {
                        Text("@\(p.handle ?? "anon")")
                            .font(DreamTheme.Font.text(13))
                            .foregroundStyle(DreamTheme.ink2)
                        if let loc = p.location, !loc.isEmpty {
                            Circle().fill(DreamTheme.ink3).frame(width: 2, height: 2)
                            Text(loc)
                                .font(DreamTheme.Font.text(13))
                                .foregroundStyle(DreamTheme.ink3)
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DreamTheme.ink3)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func dreamSearchRow(_ d: SearchDreamResult) -> some View {
        Button { if let ownerId = d.ownerId { profileForUser = ownerId } } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(d.resolvedCategory.palette.bg)
                        .frame(width: 48, height: 48)
                    Text(d.resolvedCategory.emoji)
                        .font(.system(size: 22))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(d.title)
                        .font(DreamTheme.Font.text(15, weight: .semibold))
                        .foregroundStyle(DreamTheme.ink)
                        .lineLimit(1)
                    if let name = d.ownerName, let handle = d.ownerHandle {
                        Text("\(name) · @\(handle)")
                            .font(DreamTheme.Font.text(13))
                            .foregroundStyle(DreamTheme.ink2)
                            .lineLimit(1)
                    }
                }
                Spacer()
                CategoryBadge(category: d.resolvedCategory)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Header

    private var headerOverlay: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Explore")
                    .font(DreamTheme.Font.display(34, weight: .regular, italic: true))
                    .foregroundStyle(DreamTheme.ink)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 64)

            // Search bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(DreamTheme.ink3)
                    .font(.system(size: 15))
                TextField("Search people, dreams, places…", text: $searchText)
                    .font(DreamTheme.Font.text(15))
                    .foregroundStyle(DreamTheme.ink)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(DreamTheme.ink3)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(DreamTheme.bg, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .background(DreamTheme.paper.opacity(0.96))
    }

    // MARK: - Grid

    private var exploreGrid: some View {
        ThreeColumnGrid {
            ForEach(ExplorePost.mock) { post in
                PostGridCell(post: post)
                    .onTapGesture { selectedPost = post }
            }
        }
    }

    private var emptySearch: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(DreamTheme.ink3)
            Text("No results for \"\(searchText)\"")
                .font(DreamTheme.Font.display(20, weight: .regular, italic: true))
                .foregroundStyle(DreamTheme.ink)
            Text("Try searching by name, dream or location.")
                .font(DreamTheme.Font.text(14))
                .foregroundStyle(DreamTheme.ink2)
        }
        .padding(.top, 80)
        .padding(.horizontal, 40)
    }
}

// MARK: - Grid cell

struct PostGridCell: View {
    let post: ExplorePost

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    content(size: proxy.size)
                }
            }
    }

    private func content(size: CGSize) -> some View {
        ZStack(alignment: .bottomLeading) {
            // Gradient background simulating a photo
            LinearGradient(
                colors: gradientColors(for: post),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(width: size.width, height: size.height)

            // Category emoji watermark
            categorySymbol(size: size)
                .frame(width: size.width, height: size.height)

            // Bottom fade with author handle
            LinearGradient(
                colors: [.clear, .black.opacity(0.5)],
                startPoint: .center, endPoint: .bottom
            )

            Text("@\(post.handle)")
                .font(DreamTheme.Font.text(10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .clipped()
    }

    private func categorySymbol(size: CGSize) -> some View {
        Text(post.category.emoji)
            .font(.system(size: size.height * 0.32))
            .opacity(0.18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func gradientColors(for post: ExplorePost) -> [Color] {
        let base = post.category.palette.bg
        let accent = post.category.palette.fg
        // Mix with avatar seed for visual variety
        let shift = Double(post.avatarSeed % 40) / 100.0
        return [
            base.opacity(0.7 + shift * 0.3),
            accent.opacity(0.5 + shift * 0.2),
            base.opacity(0.85)
        ]
    }
}

// MARK: - Post detail sheet

struct PostDetailSheet: View {
    let post: ExplorePost
    let onOpenProfile: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Large image area
                    ZStack(alignment: .bottomLeading) {
                        LinearGradient(
                            colors: [post.category.palette.bg.opacity(0.8),
                                     post.category.palette.fg.opacity(0.6),
                                     post.category.palette.bg],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                        .frame(height: 360)
                        .frame(maxWidth: .infinity)

                        Text(post.category.emoji)
                            .font(.system(size: 110))
                            .opacity(0.25)
                            .frame(maxWidth: .infinity, maxHeight: 360)

                        LinearGradient(
                            colors: [.clear, .black.opacity(0.5)],
                            startPoint: .center, endPoint: .bottom
                        )
                        .frame(height: 360)

                        VStack(alignment: .leading, spacing: 4) {
                            CategoryBadge(category: post.category, dark: true)
                            Text(post.dreamTitle)
                                .font(DreamTheme.Font.display(22, weight: .regular))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                        }
                        .padding(18)
                    }
                    .clipped()

                    VStack(alignment: .leading, spacing: 16) {
                        // Author row
                        HStack(spacing: 12) {
                            Avatar(name: post.authorName, seed: post.avatarSeed, size: 44)
                                .overlay(Circle().strokeBorder(DreamTheme.line, lineWidth: 1))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(post.authorName)
                                    .font(DreamTheme.Font.text(15, weight: .semibold))
                                    .foregroundStyle(DreamTheme.ink)
                                HStack(spacing: 6) {
                                    Text("@\(post.handle)")
                                        .font(DreamTheme.Font.text(13))
                                        .foregroundStyle(DreamTheme.ink2)
                                    Circle().fill(DreamTheme.ink3).frame(width: 2, height: 2)
                                    Text(post.location)
                                        .font(DreamTheme.Font.text(13))
                                        .foregroundStyle(DreamTheme.ink3)
                                }
                            }
                            Spacer()
                            Button {
                                dismiss()
                                onOpenProfile()
                            } label: {
                                Text("View profile")
                                    .font(DreamTheme.Font.text(13, weight: .semibold))
                                    .foregroundStyle(DreamTheme.blue)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(DreamTheme.blue.opacity(0.08), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }

                        Divider().background(DreamTheme.line)

                        // Caption
                        Text(post.caption)
                            .font(DreamTheme.Font.text(16))
                            .foregroundStyle(DreamTheme.ink)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)

                        // Location chip
                        HStack(spacing: 5) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 12))
                            Text(post.location)
                                .font(DreamTheme.Font.text(13))
                        }
                        .foregroundStyle(DreamTheme.ink3)
                    }
                    .padding(20)
                }
            }
            .ignoresSafeArea(edges: .top)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(DreamTheme.ink)
                            .frame(width: 32, height: 32)
                            .background(DreamTheme.bg, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
            }
        }
    }
}

// MARK: - Helpers (keep from old ExploreScreen)

extension DreamCategory {
    static var allCases: [DreamCategory] {
        [.tech, .food, .art, .impact, .education, .health, .music, .sport]
    }

    var emoji: String {
        switch self {
        case .tech:      return "💡"
        case .food:      return "🍽️"
        case .art:       return "🎨"
        case .impact:    return "🌍"
        case .education: return "📚"
        case .health:    return "❤️"
        case .music:     return "🎵"
        case .sport:     return "⚡"
        }
    }
}
