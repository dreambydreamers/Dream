#if DEBUG
import SwiftUI

/// Every design-system component on one scrolling page, in the current color
/// scheme. The counterpart to the Design System pane in the Claude Design project.
///
/// Debug builds only. Reach it by setting `ContentView.showsDesignGallery`, or via
/// the previews at the bottom of this file. Keeping it around means a token or
/// component change can be eyeballed in both schemes without signing in or
/// navigating to whichever screen happens to use the thing you changed.
struct DesignSystemGallery: View {
    @State private var segment = 0
    @State private var chips: Set<String> = ["funding"]
    @State private var text = ""
    @State private var note = ""
    @State private var search = ""
    @State private var isFollowing = false
    @State private var isLiked = false

    /// Section to jump to on appear, so a screenshot script can address a specific
    /// part of the page: `xcrun simctl launch <sim> ig.Dream --gallery-section=Forms`.
    private var requestedSection: String? {
        ProcessInfo.processInfo.arguments
            .first { $0.hasPrefix("--gallery-section=") }
            .map { String($0.dropFirst("--gallery-section=".count)) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            scrollBody
                .onAppear {
                    guard let requestedSection else { return }
                    proxy.scrollTo(requestedSection, anchor: .top)
                }
        }
    }

    private var scrollBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DreamSpace.s13) {
                section("Type") {
                    DreamHeadline("Where dreams meet", accent: "opportunity", size: 30)
                    DreamHeadline("What's", accent: "happening", size: 26)
                    EyebrowLabel(text: "The Journey")
                    Text("Body copy at 15pt. Plain and honest beats polished — this is the size used for descriptions and any paragraph a reader is expected to actually read.")
                        .dreamStyle(.body(15, relaxed: true))
                        .foregroundStyle(DreamTheme.Text.secondary)
                    DreamWordmark(size: 26)
                }

                section("Buttons") {
                    DreamButton(title: "I can help", icon: "heart", fullWidth: true) {}
                    HStack(spacing: DreamSpace.s5) {
                        DreamButton(title: "Continue", size: .md, trailingIcon: "arrow.right") {}
                        DreamButton(title: "Edit profile", variant: .secondary, size: .md) {}
                    }
                    HStack(spacing: DreamSpace.s5) {
                        DreamButton(title: "Ghost", variant: .ghost, size: .sm) {}
                        DreamButton(title: "Delete", variant: .danger, size: .sm) {}
                        DreamButton(title: "Publishing", size: .sm, isBusy: true) {}
                        DreamButton(title: "Disabled", size: .sm, isEnabled: false) {}
                    }
                }

                section("Badges") {
                    HStack(spacing: DreamSpace.s4) {
                        CategoryBadge(category: .tech)
                        StagePill(stage: .needs)
                    }
                    HStack(spacing: DreamSpace.s4) {
                        CategoryBadge(category: .music)
                        StagePill(stage: .almost)
                    }
                    HStack(spacing: DreamSpace.s4) {
                        FollowButton(isFollowing: isFollowing, style: .detail) { isFollowing.toggle() }
                        FollowButton(isFollowing: !isFollowing, style: .compact) {}
                    }
                }

                section("Navigation") {
                    SegmentedControl(
                        options: [.init(0, "All"), .init(1, "Messages"), .init(2, "Offers")],
                        selection: $segment,
                        fullWidth: true
                    )
                }

                section("Forms") {
                    SearchField(text: $search)
                    DreamTextField(label: "Dream title", placeholder: "What are you building?",
                                   text: $text, characterLimit: 60,
                                   hint: "\(60 - text.count) characters left")
                    DreamTextField(label: "Description", placeholder: "One or two sentences.",
                                   text: $note, lineLimit: 4)
                    DreamTextField(label: "Email", placeholder: "you@example.com", text: .constant("nope"),
                                   icon: "envelope", error: "That address doesn't look right")
                    ChipSelect(
                        options: [.init("funding", "Funding", icon: "dollarsign.circle"),
                                  .init("mentor", "Mentorship", icon: "cup.and.saucer"),
                                  .init("design", "Design", icon: "pencil.and.outline"),
                                  .init("network", "Intros", icon: "arrow.triangle.branch")],
                        selection: $chips,
                        allowsMultiple: true
                    )
                }

                section("Surfaces") {
                    DreamSurface {
                        StatRow(stats: [.init("3", "Dreams"), .init("24", "Followers"), .init("18", "Following")])
                    }
                    DreamNote(icon: "info.circle",
                              text: "Dreams that name what they need get roughly three times more offers. You can change this any time.")
                    OptionRow(icon: "dollarsign.circle", title: "Funding",
                              subtitle: "Back it with money, however much",
                              isSelected: true, isRecommended: true)
                    OptionRow(icon: "cup.and.saucer", title: "Mentorship",
                              subtitle: "Share what you've learned")
                }

                section("Feedback") {
                    Toast(message: "Saved to your collection", tone: .success)
                    Toast(message: "Couldn't send that offer", tone: .error)
                    SkeletonFeedCard(mediaHeight: 120)
                    SkeletonRow()
                }

                section("Empty states") {
                    EmptyState(icon: "bookmark", title: "Nothing saved", accent: "yet",
                               message: "Tap the bookmark on any dream to keep it here for later.")
                    EmptyState(icon: "wifi.slash", title: "Can't reach", accent: "Dream",
                               message: "This dream didn't load. Check your connection and try again.",
                               tone: .error, actionTitle: "Try again", action: {},
                               secondaryTitle: "Go back", secondaryAction: {})
                }

                section("Over media") {
                    ZStack {
                        LinearGradient(colors: [Color(hex: 0x2A3540), Color(hex: 0x11161B)],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: 320)
                            .clipShape(DreamShape.lg)

                        VStack(spacing: DreamSpace.s8) {
                            HStack(spacing: DreamSpace.s4) {
                                CategoryBadge(category: .food, dark: true)
                                StagePill(stage: .early, onMedia: true)
                            }
                            SegmentedControl(
                                options: [.init(0, "For you"), .init(1, "Following")],
                                selection: $segment, onMedia: true
                            )
                            HStack(spacing: DreamSpace.s5) {
                                IconButton(systemName: "arrow.left", accessibilityLabel: "Back")
                                IconButton(systemName: "bookmark", accessibilityLabel: "Save")
                                IconButton(systemName: "bell", accessibilityLabel: "Alerts", badge: 3)
                                FollowButton(isFollowing: false, style: .feed) {}
                            }
                            EngagementBar(orientation: .horizontal, onMedia: true,
                                          likeCount: 1240, commentCount: 38, saveCount: 96,
                                          isLiked: isLiked, onLike: { isLiked.toggle() })
                        }
                    }
                }

                section("On page") {
                    EngagementBar(orientation: .horizontal, likeCount: 1240,
                                  commentCount: 38, saveCount: 96)
                    HStack(spacing: DreamSpace.s5) {
                        IconButton(systemName: "gearshape", accessibilityLabel: "Settings", variant: .solid)
                        IconButton(systemName: "square.and.arrow.up", accessibilityLabel: "Share", variant: .solid)
                        IconButton(systemName: "plus", accessibilityLabel: "Add", variant: .accent)
                        IconButton(systemName: "ellipsis", accessibilityLabel: "More", variant: .plain)
                    }
                }
            }
            .padding(.horizontal, DreamSpace.screenGutter)
            .padding(.vertical, DreamSpace.s14)
        }
        .background(DreamTheme.Surface.page)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DreamSpace.s8) {
            Text(title)
                .dreamStyle(.label)
                .foregroundStyle(DreamTheme.Accent.deep)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(title)
    }
}

#Preview("Light") {
    DesignSystemGallery().preferredColorScheme(.light)
}

#Preview("Dark") {
    DesignSystemGallery().preferredColorScheme(.dark)
}
#endif
