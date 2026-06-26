import SwiftUI

/// A live 1:1 conversation: message history, composer, typing indicator, online
/// status and "Seen" read receipts. Presented as a full-screen cover from the
/// Activity tab. All realtime wiring lives in `ChatRepository`.
struct ChatScreen: View {
    let me: UUID
    let otherName: String
    let otherSeed: Int
    let otherAvatarURL: URL?
    var onOpenProfile: (UUID) -> Void = { _ in }
    var onBack: () -> Void

    @StateObject private var model: ChatRepository
    @FocusState private var composerFocused: Bool

    init(conversationId: UUID, me: UUID, otherUserId: UUID, otherName: String, otherSeed: Int,
         otherAvatarURL: URL? = nil,
         onOpenProfile: @escaping (UUID) -> Void = { _ in }, onBack: @escaping () -> Void) {
        self.me = me
        self.otherName = otherName
        self.otherSeed = otherSeed
        self.otherAvatarURL = otherAvatarURL
        self.onOpenProfile = onOpenProfile
        self.onBack = onBack
        _model = StateObject(wrappedValue: ChatRepository(
            conversationId: conversationId, me: me, otherUserId: otherUserId))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(DreamTheme.line)
            messageList
            composer
        }
        .background(DreamTheme.paper.ignoresSafeArea())
        .task { await model.start() }
        .onDisappear { Task { await model.stop() } }
        .pausesDiscoverFeed()
        .interactiveBackSwipe { onBack() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DreamTheme.ink)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            Button { onOpenProfile(model.otherUserId) } label: {
                HStack(spacing: 10) {
                    ZStack(alignment: .bottomTrailing) {
                        Avatar(name: otherName, seed: otherSeed, size: 38, url: otherAvatarURL)
                        OnlineDot(online: model.isOtherOnline)
                            .offset(x: 1, y: 1)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(otherName)
                            .font(DreamTheme.Font.text(16, weight: .semibold))
                            .foregroundStyle(DreamTheme.ink)
                        Text(model.isOtherTyping ? "typing…" : (model.isOtherOnline ? "Online" : "Offline"))
                            .font(DreamTheme.Font.text(12))
                            .foregroundStyle(model.isOtherTyping ? DreamTheme.blue : DreamTheme.ink3)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 60)
        .padding(.bottom, 12)
        .background(Color.white.ignoresSafeArea(edges: .top))
    }

    // MARK: - Messages

    private var lastMineSeenId: UUID? {
        guard let read = model.otherLastReadAt else { return nil }
        return model.messages.last(where: { $0.senderId == me && !$0.isSystem && $0.createdAt <= read })?.id
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.messages) { msg in
                        MessageBubble(message: msg, isMine: msg.senderId == me,
                                      showSeen: msg.id == lastMineSeenId,
                                      sharePreview: sharePreview(for: msg))
                            .id(msg.id)
                    }
                    if model.isOtherTyping {
                        HStack { TypingIndicator(); Spacer() }
                            .id("typing")
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: model.isOtherTyping) { _, typing in
                if typing { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
            .task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private func sharePreview(for message: MessageDTO) -> SharedVideoPreview? {
        guard message.isDreamShare, let key = message.sharedVideoId ?? message.sharedDreamId else { return nil }
        return model.sharedPreviews[key]
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Message…", text: $model.draft, axis: .vertical)
                .font(DreamTheme.Font.text(15))
                .foregroundStyle(DreamTheme.ink)
                .lineLimit(1...5)
                .focused($composerFocused)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 20).fill(DreamTheme.bg))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(DreamTheme.line, lineWidth: 1))
                .onChange(of: model.draft) { _, _ in model.notifyTyping() }

            Button { Task { await model.send() } } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(model.draft.trimmingCharacters(in: .whitespaces).isEmpty
                                              ? DreamTheme.ink3 : DreamTheme.blue))
            }
            .buttonStyle(.plain)
            .disabled(model.draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 28)
        .background(Color.white.ignoresSafeArea(edges: .bottom))
    }
}
