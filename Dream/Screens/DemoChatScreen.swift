import SwiftUI

/// A static preview of the chat UI — lets you see message bubbles, the shared
/// video card and the composer without needing real Supabase data.
/// Accessible from the empty Messages state in ActivityScreen.
struct DemoChatScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @FocusState private var focused: Bool

    private let me = UUID()
    private let other = UUID()

    private var messages: [DemoMessage] {[
        DemoMessage(id: UUID(), text: "Hey! Vidio sam tvoj dream o climate risk APIju, stvarno cool 🌍", isMine: false, minutesAgo: 12),
        DemoMessage(id: UUID(), text: "Hvala! Zapravo tražimo backend engineera", isMine: true, minutesAgo: 11),
        DemoMessage(id: UUID(), text: "Radio sam s Rustom i Pythonom 4 godine. Mogao bih definitivno pomoći s dizajnom APija", isMine: false, minutesAgo: 11),
        DemoMessage(id: UUID(), text: "Savršeno. Jesi li slobodan za brzi call ovaj tjedan?", isMine: true, minutesAgo: 10),
        DemoMessage(id: UUID(), text: "Da, četvrtak mi odgovara 👍", isMine: false, minutesAgo: 2),
    ]}

    var body: some View {
        VStack(spacing: 0) {
            header
            messageList
            composerArea
        }
        .background(DreamTheme.paper.ignoresSafeArea())
        .navigationBarHidden(true)
        .interactiveBackSwipe { dismiss() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DreamTheme.ink)
                    .frame(width: 36, height: 36)
                    .background(DreamTheme.bg, in: Circle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                ZStack(alignment: .bottomTrailing) {
                    Avatar(name: "Ana Marić", seed: 42, size: 40)
                    OnlineDot(online: true).offset(x: 1, y: 1)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ana Marić")
                        .font(DreamTheme.Font.text(16, weight: .semibold))
                        .foregroundStyle(DreamTheme.ink)
                    Text("Online")
                        .font(DreamTheme.Font.text(12))
                        .foregroundStyle(DreamTheme.ink3)
                }
            }

            Spacer()

            // Demo badge
            Text("DEMO")
                .font(DreamTheme.Font.text(10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(DreamTheme.blue.opacity(0.7)))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Color.white
                .ignoresSafeArea(edges: .top)
                .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
        )
    }

    private var messageList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                // System message
                Text("You offered Design help on \"Climate Risk API\"")
                    .font(DreamTheme.Font.text(12))
                    .foregroundStyle(DreamTheme.ink2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(DreamTheme.cream))
                    .padding(.vertical, 6)

                ForEach(messages) { msg in
                    demoBubble(msg)
                }

                // Typing indicator
                HStack { TypingIndicator(); Spacer() }
                    .padding(.horizontal, 16)

                Color.clear.frame(height: 1)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
    }

    private func demoBubble(_ msg: DemoMessage) -> some View {
        VStack(alignment: msg.isMine ? .trailing : .leading, spacing: 3) {
            Text(msg.text)
                .font(DreamTheme.Font.text(15))
                .foregroundStyle(msg.isMine ? .white : DreamTheme.ink)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(msg.isMine ? DreamTheme.blue : DreamTheme.bg)
                )
            if msg.isMine && msg.minutesAgo <= 3 {
                Text("Seen")
                    .font(DreamTheme.Font.text(10, weight: .medium))
                    .foregroundStyle(DreamTheme.ink3)
                    .padding(.trailing, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: msg.isMine ? .trailing : .leading)
        .padding(.vertical, 2)
    }

    private var composerArea: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Poruka…", text: $draft, axis: .vertical)
                .font(DreamTheme.Font.text(15))
                .foregroundStyle(DreamTheme.ink)
                .lineLimit(1...5)
                .focused($focused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(DreamTheme.bg)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(focused ? DreamTheme.blue.opacity(0.4) : DreamTheme.line, lineWidth: 1)
                        )
                )
                .animation(.easeInOut(duration: 0.18), value: focused)

            let canSend = !draft.trimmingCharacters(in: .whitespaces).isEmpty
            Button {} label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(canSend ? DreamTheme.blue : DreamTheme.ink3))
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: canSend)
            }
            .buttonStyle(.plain)
            .disabled(true)
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

private struct DemoMessage: Identifiable {
    let id: UUID
    let text: String
    let isMine: Bool
    let minutesAgo: Int
}

// Also preview the shared video card style
struct DemoSharedVideoCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .center) {
                LinearGradient(
                    colors: [Color(hex: 0x1E3A5F), Color(hex: 0x2D6A4F)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                Circle()
                    .fill(Color.black.opacity(0.35))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .offset(x: 2)
                    )
            }
            .frame(width: 200, height: 260)
            .clipped()

            Text("Climate Risk API")
                .font(DreamTheme.Font.text(13, weight: .semibold))
                .foregroundStyle(DreamTheme.ink)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 10)
                .frame(width: 200, alignment: .leading)
                .background(Color.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
    }
}
