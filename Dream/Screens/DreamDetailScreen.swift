import SwiftUI

struct DreamDetailScreen: View {
    let dream: Dream
    var onBack: () -> Void = {}
    var onHelp: () -> Void = {}

    @State private var following = false

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
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack {
            ScenePoster(category: dream.category)
                .aspectRatio(16.0/11.0, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipped()

            Circle()
                .fill(Color.black.opacity(0.45))
                .background(.ultraThinMaterial, in: Circle())
                .frame(width: 64, height: 64)
                .overlay(
                    Image(systemName: "play.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                        .offset(x: 2)
                )

            VStack {
                HStack {
                    glassCircleButton(systemName: "chevron.left", action: onBack)
                    Spacer()
                    glassCircleButton(systemName: "square.and.arrow.up") {}
                }
                .padding(.horizontal, 14)
                .padding(.top, 56)
                Spacer()
                HStack {
                    Text("0:42")
                        .font(DreamTheme.Font.text(12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.55), in: Capsule())
                    Spacer()
                }
                .padding(14)
            }
        }
    }

    private func glassCircleButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Color.black.opacity(0.45), in: Circle())
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Profile

    private var profileRow: some View {
        HStack(spacing: 12) {
            Avatar(name: dream.name, seed: dream.avatarSeed, size: 44)
            VStack(alignment: .leading, spacing: 1) {
                Text(dream.name)
                    .font(DreamTheme.Font.text(15, weight: .semibold))
                    .foregroundStyle(DreamTheme.ink)
                Text("\(dream.location) · Dreamer")
                    .font(DreamTheme.Font.text(12))
                    .foregroundStyle(DreamTheme.ink2)
            }
            Spacer()
            Button { following.toggle() } label: {
                Text(following ? "Following" : "Follow")
                    .font(DreamTheme.Font.text(13, weight: .semibold))
                    .foregroundStyle(following ? DreamTheme.blueDeep : .white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(
                        Capsule().fill(following ? Color.white : DreamTheme.blue)
                    )
                    .overlay(
                        Capsule().strokeBorder(DreamTheme.blue, lineWidth: 1.5)
                    )
            }
            .buttonStyle(.plain)
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
            statCell("\(dream.supporters)", "Supporters")
            statCell("\(dream.offers)", "Offers")
            statCell(dream.viewsLabel, "Views")
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

    // MARK: - CTA

    private var stickyCTA: some View {
        VStack(spacing: 0) {
            Rectangle().fill(DreamTheme.line).frame(height: 1)
            PrimaryButton(title: "I can help", icon: "heart.fill", background: dream.category.palette.fg, action: onHelp)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 32)
        }
        .background(DreamTheme.paper)
    }

    private func eyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .font(DreamTheme.Font.text(11, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(DreamTheme.ink2)
    }
}
