import SwiftUI

/// Identifies a conversation to open in a full-screen `ChatScreen`.
struct ChatRoute: Identifiable, Hashable {
    let id: UUID            // conversation id
    let otherUserId: UUID
    let otherName: String
    let otherSeed: Int
    var otherAvatarURL: URL? = nil
}

/// Wraps a dream id for NavigationPath destinations so it doesn't clash with UUID (profile).
struct DreamDetailRoute: Hashable {
    let dreamId: UUID
}

/// The Activity tab: notifications, live chats, and help offers (received &
/// made) with their lifecycle status. Backed by the app-wide `ActivityRepository`
/// so the data — and the tab-bar badge — stay live over Realtime.
struct ActivityScreen: View {
    @ObservedObject private var repo = ActivityRepository.shared
    @ObservedObject private var auth = AuthService.shared
    @Binding var isTabBarHidden: Bool

    @State private var section: Section = .messages
    @State private var navPath = NavigationPath()

    init(isTabBarHidden: Binding<Bool> = .constant(false)) {
        self._isTabBarHidden = isTabBarHidden
    }

    enum Section: String, CaseIterable, Identifiable {
        case messages = "Messages"
        case notifications = "Activity"
        case offers = "Offers"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            ZStack(alignment: .top) {
                DreamTheme.paper.ignoresSafeArea()

                VStack(spacing: 0) {
                    headerBar
                    tabPills
                    Divider().background(DreamTheme.line)
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            switch section {
                            case .notifications: notificationsContent
                            case .messages:      messagesContent
                            case .offers:        offersContent
                            }
                        }
                        .padding(.top, 4)
                        .padding(.bottom, 130)
                    }
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: Bool.self) { _ in DemoChatScreen() }
            .navigationDestination(for: ChatRoute.self) { route in
                if let me = auth.userId {
                    ChatScreen(
                        conversationId: route.id, me: me,
                        otherUserId: route.otherUserId,
                        otherName: route.otherName, otherSeed: route.otherSeed,
                        otherAvatarURL: route.otherAvatarURL,
                        onOpenProfile: { uid in navPath.append(uid) },
                        onOpenDream: { dreamId in navPath.append(DreamDetailRoute(dreamId: dreamId)) },
                        onBack: {
                            if !navPath.isEmpty {
                                navPath.removeLast()
                            }
                        }
                    )
                }
            }
            .navigationDestination(for: UUID.self) { uid in
                ProfileScreen(userId: uid, onBack: { navPath.removeLast() })
            }
            .navigationDestination(for: DreamDetailRoute.self) { route in
                DreamDetailFromIdView(dreamId: route.dreamId, onBack: { navPath.removeLast() })
            }
        }
        .task { await repo.start() }
        .onChange(of: navPath.isEmpty) { _, isEmpty in
            isTabBarHidden = !isEmpty
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Activity")
                .font(DreamTheme.Font.display(34, weight: .regular, italic: true))
                .foregroundStyle(DreamTheme.ink)
            Spacer()
            if section == .notifications, repo.unreadCount > 0 {
                Button("Mark all read") { Task { await repo.markAllRead() } }
                    .font(DreamTheme.Font.text(13, weight: .semibold))
                    .foregroundStyle(DreamTheme.blue)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 64)
        .padding(.bottom, 12)
    }

    private var tabPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Section.allCases) { s in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { section = s }
                    } label: {
                        HStack(spacing: 6) {
                            Text(s.rawValue)
                                .font(DreamTheme.Font.text(14, weight: section == s ? .semibold : .regular))
                                .foregroundStyle(section == s ? .white : DreamTheme.ink2)
                            if let badgeCount = badgeCount(for: s) {
                                Text("\(badgeCount)")
                                    .font(DreamTheme.Font.text(11, weight: .bold))
                                    .foregroundStyle(section == s ? DreamTheme.blue : .white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(section == s ? .white : DreamTheme.blue))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(section == s ? DreamTheme.blue : DreamTheme.bg))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
    }

    private func badgeCount(for section: Section) -> Int? {
        let count: Int
        switch section {
        case .messages:
            count = repo.conversations.filter(\.unread).count
        case .notifications:
            count = repo.unreadCount
        case .offers:
            count = 0
        }
        return count > 0 ? count : nil
    }

    // MARK: - Notifications

    @ViewBuilder private var notificationsContent: some View {
        if repo.notifications.isEmpty {
            emptyState(
                icon: "bell",
                title: "No activity yet",
                subtitle: "Offers, replies and updates will show up here."
            )
        } else {
            ForEach(Array(repo.notifications.enumerated()), id: \.element.id) { i, n in
                Button { open(notification: n) } label: { notificationRow(n) }
                    .buttonStyle(.plain)
                if i < repo.notifications.count - 1 {
                    Divider().padding(.leading, 76).background(DreamTheme.line)
                }
            }
        }
    }

    private func notificationRow(_ n: ActivityNotification) -> some View {
        HStack(spacing: 14) {
            ZStack(alignment: .topTrailing) {
                Avatar(name: n.actorName, seed: n.actorSeed, size: 48, url: n.actorAvatarURL)
                Image(systemName: n.icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(DreamTheme.blue))
                    .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                    .offset(x: 5, y: -3)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(n.actorName)
                    .font(DreamTheme.Font.text(15, weight: .semibold))
                    .foregroundStyle(DreamTheme.ink)
                Text(n.preview)
                    .font(DreamTheme.Font.text(14))
                    .foregroundStyle(DreamTheme.ink2)
                    .lineLimit(2)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 6) {
                Text(relativeTimeLabel(n.createdAt))
                    .font(DreamTheme.Font.text(12))
                    .foregroundStyle(DreamTheme.ink3)
                if !n.isRead {
                    Circle().fill(DreamTheme.blue).frame(width: 9, height: 9)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(n.isRead ? Color.clear : DreamTheme.blueTint.opacity(0.4))
    }

    // MARK: - Messages

    @ViewBuilder private var messagesContent: some View {
        if repo.conversations.isEmpty {
            VStack(spacing: 16) {
                emptyState(
                    icon: "bubble.left.and.bubble.right",
                    title: "No conversations",
                    subtitle: "Offer help on a dream to start chatting."
                )
                Button { navPath.append(true) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 13))
                        Text("Preview chat UI")
                            .font(DreamTheme.Font.text(14, weight: .semibold))
                    }
                    .foregroundStyle(DreamTheme.blue)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(DreamTheme.blue.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        } else {
            ForEach(Array(repo.conversations.enumerated()), id: \.element.id) { i, c in
                Button {
                    navPath.append(ChatRoute(
                        id: c.id, otherUserId: c.otherUserId,
                        otherName: c.otherName, otherSeed: c.otherSeed,
                        otherAvatarURL: c.otherAvatarURL
                    ))
                } label: { conversationRow(c) }
                .buttonStyle(.plain)
                if i < repo.conversations.count - 1 {
                    Divider().padding(.leading, 82).background(DreamTheme.line)
                }
            }
        }
    }

    private func conversationRow(_ c: ConversationSummary) -> some View {
        HStack(spacing: 14) {
            Avatar(name: c.otherName, seed: c.otherSeed, size: 52, url: c.otherAvatarURL)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(c.otherName)
                        .font(DreamTheme.Font.text(15, weight: .semibold))
                        .foregroundStyle(DreamTheme.ink)
                    Spacer()
                    if let at = c.lastMessageAt {
                        Text(relativeTimeLabel(at))
                            .font(DreamTheme.Font.text(12))
                            .foregroundStyle(DreamTheme.ink3)
                    }
                }
                HStack(spacing: 6) {
                    Text(c.preview)
                        .font(DreamTheme.Font.text(14, weight: c.unread ? .semibold : .regular))
                        .foregroundStyle(c.unread ? DreamTheme.ink : DreamTheme.ink2)
                        .lineLimit(1)
                    if c.unread {
                        Spacer(minLength: 4)
                        Circle().fill(DreamTheme.blue).frame(width: 9, height: 9)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Offers

    @ViewBuilder private var offersContent: some View {
        if repo.offersReceived.isEmpty && repo.offersMade.isEmpty {
            emptyState(
                icon: "hands.sparkles",
                title: "No offers yet",
                subtitle: "Tap 'I can help' on a dream to start, or wait for offers on yours."
            )
        } else {
            if !repo.offersReceived.isEmpty {
                sectionHeader("Offers on your dreams")
                ForEach(repo.offersReceived) { offerRow($0) }
            }
            if !repo.offersMade.isEmpty {
                sectionHeader("Offers you made")
                    .padding(.top, repo.offersReceived.isEmpty ? 0 : 16)
                ForEach(repo.offersMade) { offerRow($0) }
            }
        }
    }

    private func offerRow(_ o: OfferSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Avatar(name: o.counterpartName, seed: o.counterpartSeed, size: 42, url: o.counterpartAvatarURL)
                VStack(alignment: .leading, spacing: 3) {
                    Text(o.incoming ? "\(o.counterpartName) offered \(o.skill)" : "You offered \(o.skill)")
                        .font(DreamTheme.Font.text(14, weight: .semibold))
                        .foregroundStyle(DreamTheme.ink)
                        .lineLimit(2)
                    Text("on \"\(o.dreamTitle)\"")
                        .font(DreamTheme.Font.text(13))
                        .foregroundStyle(DreamTheme.ink2)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                OfferStatusPill(status: o.status)
            }
            if !o.message.isEmpty {
                Text(o.message)
                    .font(DreamTheme.Font.text(13))
                    .foregroundStyle(DreamTheme.ink2)
                    .lineLimit(3)
            }
            offerActions(o)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(DreamTheme.line, lineWidth: 1))
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    @ViewBuilder private func offerActions(_ o: OfferSummary) -> some View {
        HStack(spacing: 8) {
            if o.incoming {
                switch o.status {
                case .pending:
                    actionButton("Accept", filled: true) { respond(o, .accepted) }
                    actionButton("Decline") { respond(o, .rejected) }
                case .accepted:
                    actionButton("Start", filled: true) { respond(o, .inProgress) }
                    actionButton("Complete") { respond(o, .completed) }
                case .inProgress:
                    actionButton("Complete", filled: true) { respond(o, .completed) }
                default:
                    EmptyView()
                }
            } else if o.status.isActive {
                actionButton("Withdraw") { cancel(o) }
            }
            if let cid = o.conversationId {
                actionButton("Message") {
                    navPath.append(ChatRoute(
                        id: cid, otherUserId: o.counterpartId,
                        otherName: o.counterpartName, otherSeed: o.counterpartSeed,
                        otherAvatarURL: o.counterpartAvatarURL
                    ))
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func actionButton(_ title: String, filled: Bool = false, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(title)
                .font(DreamTheme.Font.text(13, weight: .semibold))
                .foregroundStyle(filled ? .white : DreamTheme.ink)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(filled ? DreamTheme.blue : Color.white)
                )
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(filled ? DreamTheme.blue : DreamTheme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shared bits

    private func sectionHeader(_ t: String) -> some View {
        Text(t.uppercased())
            .font(DreamTheme.Font.text(11, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(DreamTheme.ink3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 4)
            .padding(.top, 8)
    }

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(DreamTheme.ink3)
            Text(title)
                .font(DreamTheme.Font.display(20, weight: .regular, italic: true))
                .foregroundStyle(DreamTheme.ink)
            Text(subtitle)
                .font(DreamTheme.Font.text(14))
                .foregroundStyle(DreamTheme.ink2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .padding(.horizontal, 40)
    }

    // MARK: - Actions

    private func open(notification n: ActivityNotification) {
        guard let cid = n.conversationId, let actor = n.actorId else { return }
        navPath.append(ChatRoute(
            id: cid, otherUserId: actor,
            otherName: n.actorName, otherSeed: n.actorSeed,
            otherAvatarURL: n.actorAvatarURL
        ))
    }

    private func respond(_ o: OfferSummary, _ status: HelpOfferStatus) {
        Task {
            try? await HelpOfferRepository.shared.respond(offerId: o.id, status: status)
            await repo.load()
        }
    }

    private func cancel(_ o: OfferSummary) {
        Task {
            try? await HelpOfferRepository.shared.cancel(offerId: o.id)
            await repo.load()
        }
    }
}

// Resolves a dream ID to a Dream and shows DreamDetailScreen.
// Looks up the feed cache first; shows a spinner while loading if not found.
private struct DreamDetailFromIdView: View {
    let dreamId: UUID
    var onBack: () -> Void = {}

    @ObservedObject private var repo = DreamRepository.shared
    @State private var resolved: Dream? = nil
    @State private var failed = false

    var body: some View {
        Group {
            if let d = resolved {
                DreamDetailScreen(dream: d, onBack: onBack)
            } else if failed {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(DreamTheme.ink3)
                    Text("Dream not available")
                        .font(DreamTheme.Font.display(22, weight: .regular, italic: true))
                        .foregroundStyle(DreamTheme.ink)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DreamTheme.paper.ignoresSafeArea())
                .interactiveBackSwipe(onBack)
            } else {
                ProgressView()
                    .tint(DreamTheme.blue)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DreamTheme.paper.ignoresSafeArea())
                    .task { resolve() }
            }
        }
        // Hide the NavigationStack bar so it doesn't intercept touches on the
        // DreamDetailScreen overlay buttons (mute, save, share) at the top.
        .navigationBarHidden(true)
    }

    private func resolve() {
        // Try local feed cache first (no network needed)
        if let d = repo.dreams.first(where: { $0.id == dreamId || $0.feedID == dreamId }) {
            resolved = d
            return
        }
        // If the feed hasn't loaded yet, wait briefly then retry
        Task {
            if repo.dreams.isEmpty {
                await repo.loadFeed()
            }
            if let d = repo.dreams.first(where: { $0.id == dreamId || $0.feedID == dreamId }) {
                resolved = d
            } else {
                failed = true
            }
        }
    }
}
