import SwiftUI
import MapKit

// MARK: - Mock data model

struct ExploreDream: Identifiable {
    let id = UUID()
    let title: String
    let name: String
    let handle: String
    let category: DreamCategory
    let stage: DreamStage
    let location: String
    let supporters: Int
    let desc: String
    let coordinate: CLLocationCoordinate2D

    static let mock: [ExploreDream] = [
        .init(title: "Open-source climate risk API", name: "Ana Marić", handle: "amaric",
              category: .tech, stage: .needs, location: "Zagreb, HR", supporters: 14,
              desc: "Free API for startups to assess climate risks at any global location.",
              coordinate: .init(latitude: 45.815, longitude: 15.982)),
        .init(title: "Fermented foods market app", name: "Luka Horvat", handle: "lukaferment",
              category: .food, stage: .early, location: "Ljubljana, SI", supporters: 8,
              desc: "Connecting small batch fermenters with health-conscious buyers.",
              coordinate: .init(latitude: 46.057, longitude: 14.506)),
        .init(title: "AI music teacher for kids", name: "Mia Kovač", handle: "mia_music",
              category: .music, stage: .idea, location: "Vienna, AT", supporters: 22,
              desc: "Adaptive lessons that adjust to each child's learning style in real time.",
              coordinate: .init(latitude: 48.208, longitude: 16.374)),
        .init(title: "Outdoor sculpture walk", name: "David Balogh", handle: "dbalogh",
              category: .art, stage: .almost, location: "Budapest, HU", supporters: 31,
              desc: "Permanent art trail through the city with local artist commissions.",
              coordinate: .init(latitude: 47.498, longitude: 19.040)),
        .init(title: "Coding bootcamp for refugees", name: "Jana Novak", handle: "jana_code",
              category: .education, stage: .early, location: "Prague, CZ", supporters: 19,
              desc: "12-week intensive program leading to junior developer roles.",
              coordinate: .init(latitude: 50.075, longitude: 14.438)),
        .init(title: "Zero-waste packaging startup", name: "Erik Schmidt", handle: "erikzero",
              category: .impact, stage: .needs, location: "Berlin, DE", supporters: 44,
              desc: "Seaweed-based packaging that dissolves in water within 30 days.",
              coordinate: .init(latitude: 52.520, longitude: 13.405)),
        .init(title: "Remote mental health platform", name: "Sophie Visser", handle: "sophiev",
              category: .health, stage: .early, location: "Amsterdam, NL", supporters: 37,
              desc: "Matching rural patients with licensed therapists via video.",
              coordinate: .init(latitude: 52.368, longitude: 4.904)),
        .init(title: "Adaptive sports gear lab", name: "Carlos Vega", handle: "carlosvega",
              category: .sport, stage: .idea, location: "Barcelona, ES", supporters: 6,
              desc: "Custom equipment designed with para-athletes for para-athletes.",
              coordinate: .init(latitude: 41.385, longitude: 2.173)),
        .init(title: "AR museum for digital art", name: "Claire Dubois", handle: "claired",
              category: .art, stage: .needs, location: "Paris, FR", supporters: 28,
              desc: "Walk through holographic galleries in public spaces across the city.",
              coordinate: .init(latitude: 48.857, longitude: 2.352)),
        .init(title: "Sustainable fashion collective", name: "Giulia Rossi", handle: "giulia_r",
              category: .art, stage: .early, location: "Milan, IT", supporters: 15,
              desc: "Curated marketplace for slow-fashion designers with ethical supply chain.",
              coordinate: .init(latitude: 45.464, longitude: 9.190)),
        .init(title: "Live score community platform", name: "Tom Allen", handle: "tomallen",
              category: .music, stage: .almost, location: "London, UK", supporters: 52,
              desc: "Real-time score sharing so orchestras and bands can collaborate globally.",
              coordinate: .init(latitude: 51.507, longitude: -0.128)),
        .init(title: "AgriTech soil scanner", name: "Piotr Wiśniewski", handle: "piotrw",
              category: .tech, stage: .needs, location: "Warsaw, PL", supporters: 11,
              desc: "Pocket device that reads soil nutrient levels and gives crop recommendations.",
              coordinate: .init(latitude: 52.230, longitude: 21.012)),
    ]
}

// MARK: - Screen

struct ExploreScreen: View {
    @State private var viewMode: ViewMode = .map
    @State private var selectedDream: ExploreDream? = nil
    @State private var searchText = ""
    @State private var selectedCategory: DreamCategory? = nil
    @State private var cameraPosition = MapCameraPosition.region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 48.0, longitude: 12.0),
            span: MKCoordinateSpan(latitudeDelta: 22, longitudeDelta: 22)
        )
    )

    enum ViewMode { case map, list }

    private var filtered: [ExploreDream] {
        ExploreDream.mock.filter {
            (searchText.isEmpty ||
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.location.localizedCaseInsensitiveContains(searchText))
            && (selectedCategory == nil || $0.category == selectedCategory)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            switch viewMode {
            case .map:  mapContent
            case .list: listContent
            }
            headerOverlay
        }
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Header

    private var headerOverlay: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text("Explore")
                    .font(DreamTheme.Font.display(34, weight: .regular, italic: true))
                    .foregroundStyle(viewMode == .map ? .white : DreamTheme.ink)
                    .shadow(color: viewMode == .map ? .black.opacity(0.3) : .clear, radius: 6)

                Spacer()

                // Map / List toggle
                HStack(spacing: 2) {
                    modeButton(icon: "map.fill", mode: .map)
                    modeButton(icon: "list.bullet", mode: .list)
                }
                .padding(4)
                .background(
                    Capsule().fill(viewMode == .map
                        ? Color.black.opacity(0.35)
                        : DreamTheme.bg)
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 64)
            .padding(.bottom, 12)

            // Category filter pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    categoryPill(nil, label: "All")
                    ForEach(DreamCategory.allCases, id: \.self) { cat in
                        categoryPill(cat, label: cat.rawValue.capitalized)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }

            // Search bar (list mode only)
            if viewMode == .list {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(DreamTheme.ink3)
                        .font(.system(size: 15))
                    TextField("Search dreams…", text: $searchText)
                        .font(DreamTheme.Font.text(15))
                        .foregroundStyle(DreamTheme.ink)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(DreamTheme.bg, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
        }
        .background(
            viewMode == .map
                ? LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: viewMode == .map ? 220 : 0)
                    .allowsHitTesting(false)
                    .eraseToAnyView()
                : DreamTheme.paper.eraseToAnyView()
        )
        .animation(.easeInOut(duration: 0.2), value: viewMode)
    }

    private func modeButton(icon: String, mode: ViewMode) -> some View {
        Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { viewMode = mode } } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(viewMode == mode
                    ? (mode == .map ? .white : DreamTheme.blue)
                    : (mode == .map ? Color.white.opacity(0.6) : DreamTheme.ink3))
                .frame(width: 38, height: 32)
                .background(viewMode == mode
                    ? (mode == .map ? Color.white.opacity(0.25) : Color.white)
                    : Color.clear,
                    in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func categoryPill(_ cat: DreamCategory?, label: String) -> some View {
        let selected = selectedCategory == cat
        let isMap = viewMode == .map

        let textColor: Color = {
            if selected { return isMap ? .white : (cat?.palette.fg ?? DreamTheme.blue) }
            return isMap ? Color.white.opacity(0.85) : DreamTheme.ink2
        }()
        let bgColor: Color = {
            if selected { return isMap ? Color.white.opacity(0.3) : (cat?.palette.bg ?? DreamTheme.blue.opacity(0.12)) }
            return isMap ? Color.black.opacity(0.3) : DreamTheme.bg
        }()
        let strokeColor: Color = selected ? (cat?.palette.fg ?? DreamTheme.blue).opacity(0.4) : Color.clear

        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                selectedCategory = selected ? nil : cat
            }
        } label: {
            Text(label)
                .font(DreamTheme.Font.text(13, weight: selected ? .semibold : .regular))
                .foregroundStyle(textColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(bgColor))
                .overlay(Capsule().strokeBorder(strokeColor, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Map

    private var mapContent: some View {
        ZStack(alignment: .bottom) {
            Map(position: $cameraPosition) {
                ForEach(filtered) { d in
                    Annotation(d.title, coordinate: d.coordinate, anchor: .bottom) {
                        mapPin(d)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    selectedDream = (selectedDream?.id == d.id) ? nil : d
                                }
                            }
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat))
            .ignoresSafeArea()

            // Preview card when pin selected
            if let d = selectedDream {
                mapPreviewCard(d)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 110)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: selectedDream?.id)
    }

    private func mapPin(_ d: ExploreDream) -> some View {
        let isSelected = selectedDream?.id == d.id
        return VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(d.category.palette.bg)
                    .frame(width: isSelected ? 48 : 36, height: isSelected ? 48 : 36)
                    .shadow(color: d.category.palette.fg.opacity(0.4), radius: isSelected ? 8 : 4, y: 2)
                Text(d.category.emoji)
                    .font(.system(size: isSelected ? 22 : 16))
            }
            // Pin tail
            Triangle()
                .fill(d.category.palette.bg)
                .frame(width: isSelected ? 10 : 8, height: isSelected ? 7 : 5)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }

    private func mapPreviewCard(_ d: ExploreDream) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(d.category.palette.bg).frame(width: 50, height: 50)
                Text(d.category.emoji).font(.system(size: 24))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(d.title)
                    .font(DreamTheme.Font.text(15, weight: .semibold))
                    .foregroundStyle(DreamTheme.ink)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text(d.location)
                        .font(DreamTheme.Font.text(12))
                        .foregroundStyle(DreamTheme.ink3)
                    Circle().fill(DreamTheme.ink3).frame(width: 3, height: 3)
                    Text("\(d.supporters) supporters")
                        .font(DreamTheme.Font.text(12))
                        .foregroundStyle(DreamTheme.ink3)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DreamTheme.ink3)
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 16, y: 6)
    }

    // MARK: - List

    private var listContent: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 12) {
                // Top spacer for fixed header (title + pills + search)
                Color.clear.frame(height: 180)

                if filtered.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(DreamTheme.ink3)
                        Text("No dreams found")
                            .font(DreamTheme.Font.display(20, weight: .regular, italic: true))
                            .foregroundStyle(DreamTheme.ink)
                    }
                    .padding(.top, 60)
                } else {
                    ForEach(filtered) { d in listCard(d) }
                }

                Color.clear.frame(height: 120)
            }
            .padding(.horizontal, 20)
        }
        .background(DreamTheme.paper.ignoresSafeArea())
    }

    private func listCard(_ d: ExploreDream) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(d.category.palette.bg)
                        .frame(width: 52, height: 52)
                    Text(d.category.emoji)
                        .font(.system(size: 26))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(d.title)
                        .font(DreamTheme.Font.text(16, weight: .semibold))
                        .foregroundStyle(DreamTheme.ink)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text("@\(d.handle)")
                            .font(DreamTheme.Font.text(13))
                            .foregroundStyle(DreamTheme.ink2)
                        Circle().fill(DreamTheme.ink3).frame(width: 2, height: 2)
                        Text(d.location)
                            .font(DreamTheme.Font.text(13))
                            .foregroundStyle(DreamTheme.ink3)
                    }
                }
                Spacer(minLength: 8)
                stageChip(d.stage)
            }

            Text(d.desc)
                .font(DreamTheme.Font.text(14))
                .foregroundStyle(DreamTheme.ink2)
                .lineLimit(2)
                .lineSpacing(2)

            HStack(spacing: 16) {
                HStack(spacing: 5) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(d.category.palette.fg)
                    Text("\(d.supporters) supporters")
                        .font(DreamTheme.Font.text(12, weight: .medium))
                        .foregroundStyle(DreamTheme.ink2)
                }

                CategoryBadge(category: d.category, dark: false)

                Spacer()

                Button {} label: {
                    Text("View dream")
                        .font(DreamTheme.Font.text(13, weight: .semibold))
                        .foregroundStyle(DreamTheme.blue)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(DreamTheme.blue.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }

    private func stageChip(_ stage: DreamStage) -> some View {
        Text(stage.shortLabel)
            .font(DreamTheme.Font.text(11, weight: .semibold))
            .foregroundStyle(DreamTheme.ink2)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(DreamTheme.bg, in: Capsule())
    }
}

// MARK: - Helpers

extension DreamCategory {
    /// All cases for the filter pills
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

extension DreamStage {
    var shortLabel: String {
        switch self {
        case .idea:   return "Idea"
        case .early:  return "Early"
        case .needs:  return "Needs help"
        case .almost: return "Almost there"
        }
    }
}

/// Pin tail triangle shape
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.closeSubpath()
        }
    }
}

private extension View {
    func eraseToAnyView() -> AnyView { AnyView(self) }
}
