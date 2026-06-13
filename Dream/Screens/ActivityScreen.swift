import SwiftUI

/// Identifies a conversation to open in a full-screen `ChatScreen`.
struct ChatRoute: Identifiable, Hashable {
    let id: UUID            // conversation id
    let otherUserId: UUID
    let otherName: String
    let otherSeed: Int
}

/// The Activity tab: notifications, live chats, and help offers (received &
/// made) with their lifecycle status. Backed by the app-wide `ActivityRepository`
/// so the data — and the tab-bar badge — stay live over Realtime.
struct ActivityScreen: View {
    @ObservedObject private var repo = ActivityRepository.shared
    @ObservedObject private var auth = AuthService.shared

    @State private var section: Section = .notifications
    @State private var chat: ChatRoute?
    @State private var profileForUser: UUID?

    enum Section: String, CaseIterable, Identifiable {
        case notifications = "Activity"
        case messages = "Messages"
        case offers = "Offers"
        var id: String { rawValue }
    }

    var body: some View {
        ZStack(alignment: .top) {
            DreamTheme.paper.ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar
                picker
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        switch section {
                        case .notifications: notificationsContent
                        case .messages:      messagesContent
                        case .offers:        offersContent
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 130)
                }
            }
        }
        .task { await repo.start() }
        .fullScreenCover(item: $chat) { route in
            if let me = auth.userId {
                ChatScreen(
                    conversationId: route.id, me: me, otherUserId: route.otherUserId,
                    otherName: route.otherName, otherSeed: route.otherSeed,
                    onOpenProfile: { uid in chat = nil; profileForUser = uid },
                    onBack: { chat = nil })
            }
        }
        .fullScreenCover(item: $profileForUser) { uid in
            ProfileScreen(userId: uid, onBack: { profileForUser = nil })
        }
    }

    // MARK: - Header & picker

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
        .padding(.bottom, 8)
    }

    private var picker: some View {
        Picker("", selection: $section) {
            ForEach(Section.allCases) { s in Text(s.rawValue).tag(s) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    // MARK: - Notifications

    @ViewBuilder private var notificationsContent: some View {
        if repo.notifications.isEmpty {
            emptyState("No activity yet", "Offers, replies and updates will show up here.")
        } else {
            ForEach(repo.notifications) { n in
                Button { open(notification: n) } label: { notificationRow(n) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func notificationRow(_ n: ActivityNotification) -> some View {
        HStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                Avatar(name: n.actorName, seed: n.actorSeed, size: 44)
                Image(systemName: n.icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(DreamTheme.blue))
                    .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                    .offset(x: 6, y: -4)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(n.actorName)
                    .font(DreamTheme.Font.text(15, weight: .semibold))
                    .foregroundStyle(DreamTheme.ink)
                Text(n.preview)
                    .font(DreamTheme.Font.text(13))
                    .foregroundStyle(DreamTheme.ink2)
                    .lineLimit(2)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 6) {
                Text(relativeTimeLabel(n.createdAt))
                    .font(DreamTheme.Font.text(11))
                    .foregroundStyle(DreamTheme.ink3)
                if !n.isRead { Circle().fill(DreamTheme.blue).frame(width: 8, height: 8) }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(n.isRead ? Color.white : DreamTheme.blueTint))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(DreamTheme.line, lineWidth: 1))
    }

    // MARK: - Messages

    @ViewBuilder private var messagesContent: some View {
        if repo.conversations.isEmpty {
            emptyState("No conversations", "When you offer help or get an offer, your chat opens here.")
        } else {
            ForEach(repo.conversations) { c in
                Button {
                    chat = ChatRoute(id: c.id, otherUserId: c.otherUserId,
                                     otherName: c.otherName, otherSeed: c.otherSeed)
                } label: { conversationRow(c) }
                .buttonStyle(.plain)
            }
        }
    }

    private func conversationRow(_ c: ConversationSummary) -> some View {
        HStack(spacing: 12) {
            Avatar(name: c.otherName, seed: c.otherSeed, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.otherName)
                    .font(DreamTheme.Font.text(15, weight: .semibold))
                    .foregroundStyle(DreamTheme.ink)
                Text(c.preview)
                    .font(DreamTheme.Font.text(13, weight: c.unread ? .semibold : .regular))
                    .foregroundStyle(c.unread ? DreamTheme.ink : DreamTheme.ink2)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 6) {
                if let at = c.lastMessageAt {
                    Text(relativeTimeLabel(at))
                        .font(DreamTheme.Font.text(11))
                        .foregroundStyle(DreamTheme.ink3)
                }
                if c.unread { Circle().fill(DreamTheme.blue).frame(width: 9, height: 9) }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(DreamTheme.line, lineWidth: 1))
    }

    // MARK: - Offers

    @ViewBuilder private var offersContent: some View {
        if repo.offersReceived.isEmpty && repo.offersMade.isEmpty {
            emptyState("No offers yet", "Tap “I can help” on a dream to start, or wait for offers on yours.")
        } else {
            if !repo.offersReceived.isEmpty {
                sectionHeader("Offers on your dreams")
                ForEach(repo.offersReceived) { offerRow($0) }
            }
            if !repo.offersMade.isEmpty {
                sectionHeader("Offers you made").padding(.top, repo.offersReceived.isEmpty ? 0 : 10)
                ForEach(repo.offersMade) { offerRow($0) }
            }
        }
    }

    private func offerRow(_ o: OfferSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Avatar(name: o.counterpartName, seed: o.counterpartSeed, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(o.incoming ? "\(o.counterpartName) offered \(o.skill)" : "You offered \(o.skill)")
                        .font(DreamTheme.Font.text(14, weight: .semibold))
                        .foregroundStyle(DreamTheme.ink)
                        .lineLimit(2)
                    Text("on “\(o.dreamTitle)”")
                        .font(DreamTheme.Font.text(12))
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
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(DreamTheme.line, lineWidth: 1))
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
                    chat = ChatRoute(id: cid, otherUserId: o.counterpartId,
                                     otherName: o.counterpartName, otherSeed: o.counterpartSeed)
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
            .padding(.bottom, 2)
    }

    private func emptyState(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(DreamTheme.Font.display(22, weight: .regular, italic: true))
                .foregroundStyle(DreamTheme.ink)
            Text(subtitle)
                .font(DreamTheme.Font.text(14))
                .foregroundStyle(DreamTheme.ink2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .padding(.horizontal, 30)
    }

    // MARK: - Actions

    private func open(notification n: ActivityNotification) {
        guard let cid = n.conversationId, let actor = n.actorId else { return }
        chat = ChatRoute(id: cid, otherUserId: actor, otherName: n.actorName, otherSeed: n.actorSeed)
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
