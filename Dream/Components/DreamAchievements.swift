import SwiftUI

// MARK: - Achievement definition

struct DreamAchievement: Identifiable {
    let id: String
    let icon: String
    let emoji: String
    let title: String
    let subtitle: String
    let unlocked: Bool
    let accentColor: Color
}

extension DreamAchievement {
    /// Returns all badges locked — for a user who hasn't posted a dream yet.
    static var allLocked: [DreamAchievement] {
        let definitions: [(id: String, icon: String, emoji: String, title: String, subtitle: String, color: Color)] = [
            ("dreamer",    "moon.stars.fill",        "🌙", "Dreamer",       "Post your first dream",          DreamTheme.blue),
            ("storyteller","play.circle.fill",        "🎬", "Storyteller",   "Attach a video to your dream",   Color(hex: 0xE07B39)),
            ("first_spark","person.fill.checkmark",   "✨", "First Spark",   "Get your first supporter",       Color(hex: 0xF5C518)),
            ("hand_raised","hand.raised.fill",        "🤝", "Hand Raised",   "Receive a help offer",           Color(hex: 0x8AD3A7)),
            ("in_motion",  "figure.run",              "💪", "In Motion",     "Complete a journey step",        Color(hex: 0xFF6B6B)),
            ("rising_star","star.fill",               "⭐", "Rising Star",   "Reach 5 supporters",             Color(hex: 0xFFB800)),
            ("halfway",    "map.fill",                "🗺️", "Halfway There", "Half the journey completed",     Color(hex: 0x9B59B6)),
            ("almost",     "flag.fill",               "🎯", "Almost There",  "Reach the final stage",          Color(hex: 0x2ECC71)),
        ]
        return definitions.map { d in
            DreamAchievement(id: d.id, icon: d.icon, emoji: d.emoji,
                             title: d.title, subtitle: d.subtitle,
                             unlocked: false, accentColor: d.color)
        }
    }

    /// Derive achievements from a Dream's current data.
    static func achievements(for dream: Dream) -> [DreamAchievement] {
        let doneSteps = dream.journey.filter(\.done).count
        return [
            DreamAchievement(id: "dreamer",
                             icon: "moon.stars.fill", emoji: "🌙",
                             title: "Dreamer",
                             subtitle: "Started a dream",
                             unlocked: true,
                             accentColor: DreamTheme.blue),

            DreamAchievement(id: "storyteller",
                             icon: "play.circle.fill", emoji: "🎬",
                             title: "Storyteller",
                             subtitle: "Posted a video",
                             unlocked: dream.videoStoragePath != nil,
                             accentColor: Color(hex: 0xE07B39)),

            DreamAchievement(id: "first_spark",
                             icon: "person.fill.checkmark", emoji: "✨",
                             title: "First Spark",
                             subtitle: "Got your first supporter",
                             unlocked: dream.supporters > 0,
                             accentColor: Color(hex: 0xF5C518)),

            DreamAchievement(id: "hand_raised",
                             icon: "hand.raised.fill", emoji: "🤝",
                             title: "Hand Raised",
                             subtitle: "Received a help offer",
                             unlocked: dream.offers > 0,
                             accentColor: Color(hex: 0x8AD3A7)),

            DreamAchievement(id: "in_motion",
                             icon: "figure.run", emoji: "💪",
                             title: "In Motion",
                             subtitle: "Completed a journey step",
                             unlocked: doneSteps > 0,
                             accentColor: Color(hex: 0xFF6B6B)),

            DreamAchievement(id: "rising_star",
                             icon: "star.fill", emoji: "⭐",
                             title: "Rising Star",
                             subtitle: "5+ supporters",
                             unlocked: dream.supporters >= 5,
                             accentColor: Color(hex: 0xFFB800)),

            DreamAchievement(id: "halfway",
                             icon: "map.fill", emoji: "🗺️",
                             title: "Halfway There",
                             subtitle: "Half the journey done",
                             unlocked: dream.journey.count >= 2 && doneSteps >= dream.journey.count / 2,
                             accentColor: Color(hex: 0x9B59B6)),

            DreamAchievement(id: "almost",
                             icon: "flag.fill", emoji: "🎯",
                             title: "Almost There",
                             subtitle: "Reached the final stage",
                             unlocked: dream.stage == .almost,
                             accentColor: Color(hex: 0x2ECC71)),
        ]
    }
}

// MARK: - View

struct DreamAchievementsView: View {
    /// Pass `nil` when the user has no dream yet — all achievements show locked.
    let dream: Dream?

    private var achievements: [DreamAchievement] {
        guard let dream else { return DreamAchievement.allLocked }
        return DreamAchievement.achievements(for: dream)
    }
    private var unlockedCount: Int { achievements.filter(\.unlocked).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            progressBar
            achievementsGrid
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Milestones")
                .font(DreamTheme.Font.display(22, weight: .regular, italic: true))
                .foregroundStyle(DreamTheme.ink)
            Spacer()
            Text("\(unlockedCount)/\(achievements.count)")
                .font(DreamTheme.Font.text(14, weight: .semibold))
                .foregroundStyle(DreamTheme.blue)
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(DreamTheme.bg)
                    .frame(height: 6)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [DreamTheme.blue, Color(hex: 0x8AD3A7)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * CGFloat(unlockedCount) / CGFloat(achievements.count), height: 6)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: unlockedCount)
            }
        }
        .frame(height: 6)
    }

    private var achievementsGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 72, maximum: 88), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 16) {
            ForEach(achievements) { a in
                achievementBadge(a)
            }
        }
    }

    private func achievementBadge(_ a: DreamAchievement) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(a.unlocked ? a.accentColor.opacity(0.12) : DreamTheme.bg)
                    .frame(width: 60, height: 60)
                    .overlay(Circle().strokeBorder(
                        a.unlocked ? a.accentColor.opacity(0.35) : DreamTheme.line,
                        lineWidth: 1.5
                    ))

                if a.unlocked {
                    Text(a.emoji)
                        .font(.system(size: 26))
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(DreamTheme.ink3.opacity(0.4))
                }
            }
            Text(a.title)
                .font(DreamTheme.Font.text(11, weight: a.unlocked ? .semibold : .regular))
                .foregroundStyle(a.unlocked ? DreamTheme.ink : DreamTheme.ink3)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .opacity(a.unlocked ? 1 : 0.6)
        .scaleEffect(a.unlocked ? 1 : 0.92)
    }
}
