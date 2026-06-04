import SwiftUI

struct DiscoverScreen: View {
    @StateObject private var repo = DreamRepository.shared
    @State private var index: Int = 0
    @State private var supporterMode: Bool = true
    @State private var supporterSkills: [String] = ["Design", "Funding"]
    @State private var presentedDream: Dream?
    @State private var helpForDream: Dream?
    @State private var profileForUser: UUID?
    @State private var isMuted: Bool = false

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
        }
        .onChange(of: index) { _, newIndex in
            FeedVideoPreloader.shared.prefetchNeighbors(of: dreams, around: newIndex)
        }
        .onChange(of: repo.dreams.count) { _, _ in
            FeedVideoPreloader.shared.prefetchNeighbors(of: dreams, around: index)
        }
        .fullScreenCover(item: $presentedDream) { d in
            DreamDetailScreen(
                dream: d,
                onBack: { presentedDream = nil },
                onHelp: {
                    presentedDream = nil
                    helpForDream = d
                }
            )
        }
        .sheet(item: $helpForDream) { d in
            HelpSheet(dream: d, onClose: { helpForDream = nil })
        }
        .fullScreenCover(item: $profileForUser) { userId in
            ProfileScreen(userId: userId, onBack: { profileForUser = nil })
        }
    }

    // MARK: - Feed

    private var feed: some View {
        ZStack {
            DreamVideoBackground(dream: dream, isMuted: isMuted)
                .ignoresSafeArea()
                .id(dream.id)
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
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if value.translation.height < -60 {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            index = (index + 1) % dreams.count
                        }
                    } else if value.translation.height > 60 {
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

            HStack(spacing: 8) {
                Button { profileForUser = dream.ownerId } label: {
                    Text("@\(dream.handle)")
                        .font(DreamTheme.Font.text(14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                }
                .buttonStyle(.plain)
                Circle().fill(.white.opacity(0.5)).frame(width: 3, height: 3)
                Text(dream.distance)
                    .font(DreamTheme.Font.text(14))
                    .foregroundStyle(.white.opacity(0.8))
            }

            Button { presentedDream = dream } label: {
                Text(dream.title)
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
            ActionButton(systemImage: "arrowshape.turn.up.right.fill", label: "124")
            ActionButton(systemImage: "bookmark.fill", label: "Save")

            Button { profileForUser = dream.ownerId } label: {
                Avatar(name: dream.name, seed: dream.avatarSeed, size: 40)
                    .padding(2)
                    .overlay(
                        Circle().strokeBorder(
                            matched ? Color(hex: 0x8AD3A7) : .white,
                            lineWidth: matched ? 2.5 : 2
                        )
                    )
                    .shadow(color: matched ? Color(hex: 0x8AD3A7).opacity(0.7) : .clear, radius: 8)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 64)
    }
}

#Preview {
    DiscoverScreen()
}

/// Lets a bare `UUID` drive `.sheet(item:)` / `.fullScreenCover(item:)`.
extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}
