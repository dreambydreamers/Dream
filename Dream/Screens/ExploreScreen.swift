import SwiftUI

private struct ExploreHeaderHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 178

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct ExploreScreen: View {
    @Binding private var isSearchFocused: Bool

    @State private var searchText = ""
    @State private var selectedItem: ExploreMediaItem?
    @State private var profileForUser: UUID?
    @State private var dreamForDetail: Dream?
    @State private var headerHeight: CGFloat = 178
    @FocusState private var searchFieldFocused: Bool
    @ObservedObject private var searchRepo = SearchRepository.shared
    @ObservedObject private var mediaRepo = ExploreMediaRepository.shared

    init(isSearchFocused: Binding<Bool> = .constant(false)) {
        _isSearchFocused = isSearchFocused
    }

    private var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ZStack(alignment: .top) {
            DreamTheme.paper.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Color.clear.frame(height: headerHeight + 8)
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
        .onPreferenceChange(ExploreHeaderHeightKey.self) { height in
            headerHeight = max(height, 178)
        }
        .task { await mediaRepo.loadRecent() }
        .onChange(of: searchText) { _, new in searchRepo.search(new) }
        .onChange(of: searchFieldFocused) { _, focused in isSearchFocused = focused }
        .onDisappear { isSearchFocused = false }
        .fullScreenCover(item: $selectedItem) { item in
            ExploreMediaDetailSheet(
                initialItem: item,
                items: mediaRepo.items,
                onOpenProfile: { openedItem in
                    selectedItem = nil
                    DispatchQueue.main.async { profileForUser = openedItem.ownerId }
                },
                onOpenDream: { openedItem in
                    selectedItem = nil
                    DispatchQueue.main.async { dreamForDetail = openedItem.dream }
                }
            )
        }
        .fullScreenCover(item: $profileForUser) { uid in
            ProfileScreen(userId: uid, onBack: { profileForUser = nil })
        }
        .fullScreenCover(item: $dreamForDetail) { dream in
            DreamDetailScreen(dream: dream, onBack: { dreamForDetail = nil })
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
        Button {
            searchFieldFocused = false
            profileForUser = p.id
        } label: {
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
        Button {
            searchFieldFocused = false
            if let ownerId = d.ownerId { profileForUser = ownerId }
        } label: {
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

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(DreamTheme.ink3)
                    .font(.system(size: 15))
                TextField("Search people, dreams, places...", text: $searchText)
                    .font(DreamTheme.Font.text(15))
                    .foregroundStyle(DreamTheme.ink)
                    .focused($searchFieldFocused)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        searchRepo.clear()
                    } label: {
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
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: ExploreHeaderHeightKey.self, value: proxy.size.height)
            }
        }
    }

    // MARK: - Grid

    @ViewBuilder
    private var exploreGrid: some View {
        if mediaRepo.isLoading && mediaRepo.items.isEmpty {
            ProgressView()
                .tint(DreamTheme.blue)
                .padding(.top, 80)
        } else if mediaRepo.items.isEmpty {
            emptyExplore
        } else {
            ThreeColumnGrid {
                ForEach(mediaRepo.items) { item in
                    ExploreMediaGridCell(item: item)
                        .onTapGesture { selectedItem = item }
                }
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

    private var emptyExplore: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.grid.3x3")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(DreamTheme.ink3)
            Text("No updates yet.")
                .font(DreamTheme.Font.display(20, weight: .regular, italic: true))
                .foregroundStyle(DreamTheme.ink)
            Text("Photos and videos people post to their dreams will appear here.")
                .font(DreamTheme.Font.text(14))
                .foregroundStyle(DreamTheme.ink2)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 80)
        .padding(.horizontal, 40)
    }
}

// MARK: - Grid cell

struct ExploreMediaGridCell: View {
    let item: ExploreMediaItem

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
            PosterImage(url: item.imageURL, category: item.category)
                .frame(width: size.width, height: size.height)
                .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.52)],
                startPoint: .center,
                endPoint: .bottom
            )

            Text("@\(item.handle)")
                .font(DreamTheme.Font.text(10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

            if item.kind == .video {
                Image(systemName: "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(Color.black.opacity(0.35), in: Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(5)
            }
        }
        .clipped()
    }
}

// MARK: - Media detail sheet

struct ExploreMediaDetailSheet: View {
    let allItems: [ExploreMediaItem]
    var onOpenProfile: (ExploreMediaItem) -> Void = { _ in }
    var onOpenDream: (ExploreMediaItem) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @StateObject private var videoActions = VideoActionsModel()
    @ObservedObject private var savedStore = SavedDreamsStore.shared
    @State private var currentItem: ExploreMediaItem
    @State private var currentVideoID: UUID?
    @State private var videoItems: [ExploreMediaItem]
    @State private var likedItems: Set<UUID> = []
    @State private var savedItems: Set<UUID> = []
    @State private var helpDream: Dream?
    @State private var shareDream: Dream?
    @State private var moreMenuItem: ExploreMediaItem?
    @State private var externalShareItem: ShareItem?
    @State private var shareToast: String?
    @State private var shareToastTask: Task<Void, Never>?

    init(
        initialItem: ExploreMediaItem,
        items: [ExploreMediaItem],
        onOpenProfile: @escaping (ExploreMediaItem) -> Void = { _ in },
        onOpenDream: @escaping (ExploreMediaItem) -> Void = { _ in }
    ) {
        let media = Self.normalizedItems(initialItem: initialItem, items: items)
        self.allItems = media
        self.onOpenProfile = onOpenProfile
        self.onOpenDream = onOpenDream
        _currentItem = State(initialValue: initialItem)
        _currentVideoID = State(initialValue: initialItem.kind == .video ? initialItem.id : nil)
        _videoItems = State(initialValue: Self.videoFeed(startingWith: initialItem, in: media))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.black.ignoresSafeArea()

                if currentItem.kind == .video {
                    videoPager(size: geo.size, safeTop: geo.safeAreaInsets.top)
                } else {
                    photoDetail(size: geo.size)
                }

                closeButton(safeTop: geo.safeAreaInsets.top)
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(currentItem.kind == .video)
        .videoActions(videoActions)
        .sheet(item: $helpDream) { dream in
            HelpSheet(dream: dream, onClose: { helpDream = nil })
        }
        .sheet(item: $shareDream) { dream in
            InAppShareSheet(
                dream: dream,
                onClose: { shareDream = nil },
                onSent: { name in showShareToast("Sent to \(name)") }
            )
        }
        .sheet(item: $externalShareItem) { item in
            ShareSheet(items: [item.url])
        }
        .confirmationDialog("", isPresented: Binding(
            get: { moreMenuItem != nil },
            set: { if !$0 { moreMenuItem = nil } }
        ), titleVisibility: .hidden) {
            if let item = moreMenuItem {
                if let storagePath = moreStoragePath(for: item) {
                    Button("Save to Gallery") {
                        videoActions.save(storagePath: storagePath)
                    }
                    Button("Share outside Dream") {
                        videoActions.share(storagePath: storagePath)
                    }
                } else if let imageURL = item.imageURL {
                    Button("Share outside Dream") {
                        externalShareItem = ShareItem(url: imageURL)
                    }
                }
                if item.kind == .photo {
                    Button("I can help") {
                        help(item)
                    }
                    Button("View dream") {
                        openDream(item)
                    }
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
        .interactiveBackSwipe { dismiss() }
    }

    private func photoDetail(size: CGSize) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                detailHero(item: currentItem, height: min(size.width * 1.08, size.height * 0.68))

                actionStrip(item: currentItem)
                    .padding(.horizontal, 20)
                    .padding(.top, 18)

                postContext(item: currentItem)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                moreToExplore
                    .padding(.top, 34)

                Color.clear.frame(height: 36)
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    private func videoPager(size: CGSize, safeTop: CGFloat) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(videoItems) { item in
                    ExploreVideoDetailPage(
                        item: item,
                        isActive: currentVideoID == item.id,
                        isSaved: isSaved(item),
                        safeTop: safeTop,
                        onHelp: { help(item) },
                        onSave: { toggleSaved(item) },
                        onShare: { share(item) },
                        onMore: { more(item) },
                        onOpenProfile: { openProfile(item) },
                        onOpenDream: { openDream(item) }
                    )
                    .frame(width: size.width, height: size.height)
                    .id(item.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: Binding(
            get: { currentVideoID ?? currentItem.id },
            set: { id in
                currentVideoID = id
                if let id, let item = videoItems.first(where: { $0.id == id }) {
                    currentItem = item
                }
            }
        ))
        .scrollIndicators(.hidden)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func detailHero(item: ExploreMediaItem, height: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if item.kind == .video, let videoDream = item.videoDream {
                    DreamVideoBackground(dream: videoDream, isMuted: false)
                } else {
                    PosterImage(url: item.imageURL, category: item.category)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.26)],
                startPoint: .center,
                endPoint: .bottom
            )
            .frame(height: height)

            HStack(spacing: 10) {
                Avatar(name: item.authorName, seed: item.avatarSeed, size: 34, url: item.avatarURL)
                    .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                VStack(alignment: .leading, spacing: 1) {
                    Text("@\(item.handle)")
                        .font(DreamTheme.Font.text(13, weight: .semibold))
                        .foregroundStyle(.white)
                    if !item.location.isEmpty {
                        Text(item.location)
                            .font(DreamTheme.Font.text(11))
                            .foregroundStyle(.white.opacity(0.78))
                    }
                }
            }
            .padding(16)
        }
    }

    private func actionStrip(item: ExploreMediaItem) -> some View {
        HStack(spacing: 22) {
            ExploreDetailIconButton(
                systemName: likedItems.contains(item.id) ? "heart.fill" : "heart",
                label: "Like",
                foreground: likedItems.contains(item.id) ? Color.red : .white,
                action: { toggleLiked(item.id) }
            )
            ExploreDetailIconButton(systemName: "square.and.arrow.up", label: "Share", action: { shareOutside(item) })
            ExploreDetailIconButton(systemName: "ellipsis", label: "More", action: { more(item) })
            Spacer()
            ExploreDetailIconButton(
                systemName: isSaved(item) ? "bookmark.fill" : "bookmark",
                label: "Save",
                foreground: isSaved(item) ? DreamTheme.blue : .white,
                action: { toggleSaved(item) }
            )
        }
    }

    private func postContext(item: ExploreMediaItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Button { openProfile(item) } label: {
                    HStack(spacing: 10) {
                        Avatar(name: item.authorName, seed: item.avatarSeed, size: 38, url: item.avatarURL)
                            .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.authorName)
                                .font(DreamTheme.Font.text(14, weight: .semibold))
                                .foregroundStyle(.white)
                            Text("@\(item.handle)")
                                .font(DreamTheme.Font.text(12))
                                .foregroundStyle(.white.opacity(0.62))
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                HStack(spacing: 8) {
                    Button { help(item) } label: {
                        Text("I can help")
                            .font(DreamTheme.Font.text(12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(Color.white.opacity(0.14), in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)

                    Button { openDream(item) } label: {
                        Text("View dream")
                            .font(DreamTheme.Font.text(12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(DreamTheme.blue, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(item.displayTitle)
                    .font(DreamTheme.Font.display(24, weight: .regular))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                Text(item.dreamTitle)
                    .font(DreamTheme.Font.text(13, weight: .semibold))
                    .foregroundStyle(DreamTheme.blue.opacity(0.9))
                    .lineLimit(2)

                if let caption = item.caption {
                    Text(caption)
                        .font(DreamTheme.Font.text(15))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
        }
    }

    private var moreToExplore: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("More to explore")
                .font(DreamTheme.Font.text(24, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 16
            ) {
                ForEach(relatedItems) { item in
                    ExploreRelatedMediaCell(item: item)
                        .onTapGesture { openRelated(item) }
                }
            }
            .padding(.horizontal, 10)
        }
    }

    private var relatedItems: [ExploreMediaItem] {
        allItems.filter { $0.id != currentItem.id }
    }

    private func closeButton(safeTop: CGFloat) -> some View {
        GlassCircleButton(
            systemName: "chevron.left",
            accessibilityLabel: "Close",
            size: 44,
            background: Color.white.opacity(0.16),
            action: { dismiss() }
        )
        .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
        .padding(.top, currentItem.kind == .video ? max(safeTop + 24, 84) : max(safeTop + 16, 56))
        .padding(.leading, 16)
        .accessibilityLabel("Close")
    }

    private func openRelated(_ item: ExploreMediaItem) {
        currentItem = item
        if item.kind == .video {
            videoItems = Self.videoFeed(startingWith: item, in: allItems)
            currentVideoID = item.id
        } else {
            currentVideoID = nil
        }
    }

    private func openProfile(_ item: ExploreMediaItem) {
        dismiss()
        DispatchQueue.main.async { onOpenProfile(item) }
    }

    private func openDream(_ item: ExploreMediaItem) {
        dismiss()
        DispatchQueue.main.async { onOpenDream(item) }
    }

    private func help(_ item: ExploreMediaItem) {
        helpDream = item.dream
    }

    private func share(_ item: ExploreMediaItem) {
        guard let dream = item.videoDream ?? (item.dream.videoStoragePath == nil ? nil : item.dream) else {
            return
        }
        shareDream = dream
    }

    private func shareOutside(_ item: ExploreMediaItem) {
        if let imageURL = item.imageURL {
            externalShareItem = ShareItem(url: imageURL)
            return
        }
        share(item)
    }

    private func more(_ item: ExploreMediaItem) {
        guard moreStoragePath(for: item) != nil || item.imageURL != nil || item.kind == .photo else { return }
        moreMenuItem = item
    }

    private func moreStoragePath(for item: ExploreMediaItem) -> String? {
        item.videoStoragePath ?? item.videoDream?.videoStoragePath ?? item.dream.videoStoragePath
    }

    private func toggleLiked(_ id: UUID) {
        if likedItems.contains(id) {
            likedItems.remove(id)
        } else {
            likedItems.insert(id)
        }
    }

    private func isSaved(_ item: ExploreMediaItem) -> Bool {
        if let videoDream = item.videoDream {
            return savedStore.isSaved(videoDream.feedID)
        }
        return savedItems.contains(item.id)
    }

    private func toggleSaved(_ item: ExploreMediaItem) {
        if let videoDream = item.videoDream {
            savedStore.toggle(videoDream.feedID)
            return
        }
        if savedItems.contains(item.id) {
            savedItems.remove(item.id)
        } else {
            savedItems.insert(item.id)
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

    private static func normalizedItems(initialItem: ExploreMediaItem, items: [ExploreMediaItem]) -> [ExploreMediaItem] {
        var seen: Set<UUID> = []
        var result: [ExploreMediaItem] = []
        for item in [initialItem] + items {
            if seen.insert(item.id).inserted {
                result.append(item)
            }
        }
        return result
    }

    private static func videoFeed(startingWith item: ExploreMediaItem, in items: [ExploreMediaItem]) -> [ExploreMediaItem] {
        let videos = normalizedItems(initialItem: item, items: items).filter { $0.kind == .video }
        guard let index = videos.firstIndex(where: { $0.id == item.id }) else { return videos }
        return Array(videos[index...]) + Array(videos[..<index])
    }
}

private struct ExploreVideoDetailPage: View {
    let item: ExploreMediaItem
    let isActive: Bool
    let isSaved: Bool
    let safeTop: CGFloat
    var onHelp: () -> Void
    var onSave: () -> Void
    var onShare: () -> Void
    var onMore: () -> Void
    var onOpenProfile: () -> Void
    var onOpenDream: () -> Void

    var body: some View {
        ZStack {
            Group {
                if isActive, let videoDream = item.videoDream {
                    DreamVideoBackground(dream: videoDream, isMuted: false)
                } else {
                    PosterImage(url: item.imageURL, category: item.category)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .clipped()

            if isActive {
                LinearGradient(
                    colors: [.black.opacity(0.55), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 220)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()
                .allowsHitTesting(false)

                LinearGradient(
                    colors: [.clear, .black.opacity(0.65)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .frame(height: 320)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: safeTop + 48)
                    Spacer(minLength: 24)

                    HStack(alignment: .bottom, spacing: 12) {
                        discoverInfo
                            .frame(maxWidth: .infinity, alignment: .leading)
                        discoverRail
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, DreamTheme.Layout.tabBarClearance)
            }
        }
        .clipped()
        .allowsHitTesting(isActive)
    }

    private var discoverInfo: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                CategoryBadge(category: item.category, dark: true)
                HStack(spacing: 4) {
                    Text("◐")
                    Text(item.dream.stage.rawValue)
                }
                .font(DreamTheme.Font.text(12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.18), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5))
            }

            authorRow

            Button(action: onOpenDream) {
                Text(item.displayTitle)
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
                .fill(item.category.palette.fg)
                .frame(width: 36, height: 3)
                .clipShape(Capsule())
                .shadow(color: item.category.palette.fg.opacity(0.7), radius: 6)

            if let description {
                Text(description)
                    .font(DreamTheme.Font.text(13))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineSpacing(2)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var authorRow: some View {
        HStack(spacing: 8) {
            Button(action: onOpenProfile) {
                Avatar(name: item.authorName, seed: item.avatarSeed, size: 34, url: item.avatarURL)
                    .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.28), radius: 7, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(item.authorName)'s profile")

            Button(action: onOpenProfile) {
                Text("@\(item.handle)")
                    .font(DreamTheme.Font.text(14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.94))
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open @\(item.handle)'s profile")
        }
    }

    private var discoverRail: some View {
        VStack(spacing: 16) {
            ActionButton(systemImage: "heart.fill", label: "I can help", action: onHelp)
            ActionButton(systemImage: "paperplane.fill", label: "Send", action: onShare)
            ActionButton(systemImage: isSaved ? "bookmark.fill" : "bookmark", label: isSaved ? "Saved" : "Save", action: onSave)
            ActionButton(systemImage: "ellipsis", label: "More", action: onMore)
        }
        .frame(width: 64)
    }

    private var description: String? {
        if let caption = item.caption?.trimmingCharacters(in: .whitespacesAndNewlines), !caption.isEmpty {
            return caption
        }
        let dreamDescription = item.dream.desc.trimmingCharacters(in: .whitespacesAndNewlines)
        return dreamDescription.isEmpty ? nil : dreamDescription
    }
}

private struct ExploreDetailIconButton: View {
    let systemName: String
    let label: String
    var foreground: Color = .white
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 27, weight: .regular))
                .foregroundStyle(foreground)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct ExploreRelatedMediaCell: View {
    let item: ExploreMediaItem

    var body: some View {
        Color.clear
            .aspectRatio(0.72, contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    ZStack(alignment: .bottomTrailing) {
                        PosterImage(url: item.imageURL, category: item.category)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()

                        LinearGradient(
                            colors: [.clear, .black.opacity(0.35)],
                            startPoint: .center,
                            endPoint: .bottom
                        )

                        Image(systemName: item.kind == .video ? "play.fill" : "ellipsis")
                            .font(.system(size: item.kind == .video ? 12 : 18, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(10)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
