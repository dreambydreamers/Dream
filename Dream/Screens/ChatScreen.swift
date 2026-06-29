import SwiftUI

/// A live 1:1 conversation: message history, composer, typing indicator, online
/// status and "Seen" read receipts. Works inside a NavigationStack (standard back
/// swipe) or as a standalone fullScreenCover.
struct ChatScreen: View {
    let me: UUID
    let otherName: String
    let otherSeed: Int
    let otherAvatarURL: URL?
    var onOpenProfile: (UUID) -> Void = { _ in }
    var onBack: () -> Void = {}

    @StateObject private var model: ChatRepository
    @FocusState private var composerFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(conversationId: UUID, me: UUID, otherUserId: UUID, otherName: String, otherSeed: Int,
         otherAvatarURL: URL? = nil,
         onOpenProfile: @escaping (UUID) -> Void = { _ in },
         onBack: @escaping () -> Void = {}) {
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
            messageList
            composer
        }
        .background(DreamTheme.paper.ignoresSafeArea())
        .navigationBarHidden(true)
        .task { await model.start() }
        .onDisappear { Task { await model.stop() } }
        .pausesDiscoverFeed()
        .interactiveBackSwipe { dismiss(); onBack() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DreamTheme.ink)
                    .frame(width: 36, height: 36)
                    .background(DreamTheme.bg, in: Circle())
            }
            .buttonStyle(.plain)

            Button { onOpenProfile(model.otherUserId) } label: {
                HStack(spacing: 10) {
                    ZStack(alignment: .bottomTrailing) {
                        Avatar(name: otherName, seed: otherSeed, size: 40, url: otherAvatarURL)
                        OnlineDot(online: model.isOtherOnline)
                            .offset(x: 1, y: 1)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(otherName)
                            .font(DreamTheme.Font.text(16, weight: .semibold))
                            .foregroundStyle(DreamTheme.ink)
                        Text(model.isOtherTyping ? "typing…" : (model.isOtherOnline ? "Online" : "Offline"))
                            .font(DreamTheme.Font.text(12))
                            .foregroundStyle(model.isOtherTyping ? DreamTheme.blue : DreamTheme.ink3)
                            .animation(.easeInOut(duration: 0.2), value: model.isOtherTyping)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Color.white
                .ignoresSafeArea(edges: .top)
                .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
        )
    }

    // MARK: - Messages

    private var lastMineSeenId: UUID? {
        guard let read = model.otherLastReadAt else { return nil }
        return model.messages.last(where: { $0.senderId == me && !$0.isSystem && $0.createdAt <= read })?.id
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(model.messages) { msg in
                        MessageBubble(
                            message: msg,
                            isMine: msg.senderId == me,
                            showSeen: msg.id == lastMineSeenId,
                            sharePreview: sharePreview(for: msg)
                        )
                        .id(msg.id)
                    }
                    if model.isOtherTyping {
                        HStack { TypingIndicator(); Spacer() }
                            .padding(.horizontal, 16)
                            .id("typing")
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: model.isOtherTyping) { _, typing in
                if typing { withAnimation { proxy.scrollTo("typing", anchor: .bottom) } }
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
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message…", text: $model.draft, axis: .vertical)
                .font(DreamTheme.Font.text(15))
                .foregroundStyle(DreamTheme.ink)
                .lineLimit(1...5)
                .focused($composerFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(DreamTheme.bg)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(composerFocused ? DreamTheme.blue.opacity(0.4) : DreamTheme.line, lineWidth: 1)
                        )
                )
                .animation(.easeInOut(duration: 0.18), value: composerFocused)
                .onChange(of: model.draft) { _, _ in model.notifyTyping() }

            let canSend = !model.draft.trimmingCharacters(in: .whitespaces).isEmpty
            Button { Task { await model.send() } } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(canSend ? DreamTheme.blue : DreamTheme.ink3))
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: canSend)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 24)
        .background(
            Color.white
                .ignoresSafeArea(edges: .bottom)
                .shadow(color: .black.opacity(0.05), radius: 8, y: -2)
        )
    }
}
