import SwiftUI

/// Instagram-style in-app share picker. Recipients are profiles the current user
/// follows; sending creates/reuses a direct chat and posts a structured video
/// share message there.
struct InAppShareSheet: View {
    let dream: Dream
    var onClose: () -> Void = {}
    var onSent: (String) -> Void = { _ in }

    @State private var recipients: [ProfileDTO] = []
    @State private var note = ""
    @State private var isLoading = true
    @State private var sending: Set<UUID> = []
    @State private var sent: Set<UUID> = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                preview
                Divider().background(DreamTheme.line)
                content
            }
            .background(DreamTheme.paper.ignoresSafeArea())
            .navigationTitle("Send to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onClose)
                        .font(DreamTheme.Font.text(15, weight: .semibold))
                        .foregroundStyle(DreamTheme.blue)
                }
            }
            .task { await loadRecipients() }
        }
    }

    private var preview: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                if let poster = dream.posterURL {
                    AsyncImage(url: poster) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            ScenePoster(category: dream.category)
                        }
                    }
                } else {
                    ScenePoster(category: dream.category)
                }
                Image(systemName: "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(7)
                    .background(Color.black.opacity(0.42), in: Circle())
                    .padding(8)
            }
            .frame(width: 72, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(dream.displayTitle)
                    .font(DreamTheme.Font.text(16, weight: .semibold))
                    .foregroundStyle(DreamTheme.ink)
                    .lineLimit(2)
                Text("@\(dream.handle)")
                    .font(DreamTheme.Font.text(13))
                    .foregroundStyle(DreamTheme.ink2)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(16)
        .background(Color.white)
    }

    @ViewBuilder private var content: some View {
        if isLoading {
            VStack(spacing: 10) {
                ProgressView().tint(DreamTheme.blue)
                Text("Finding friends…")
                    .font(DreamTheme.Font.text(13))
                    .foregroundStyle(DreamTheme.ink2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if recipients.isEmpty {
            VStack(spacing: 9) {
                Image(systemName: "person.2")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(DreamTheme.ink3)
                Text("No friends yet")
                    .font(DreamTheme.Font.display(22, weight: .regular, italic: true))
                    .foregroundStyle(DreamTheme.ink)
                Text("Follow people first, then you can send dream videos to their chats.")
                    .font(DreamTheme.Font.text(14))
                    .foregroundStyle(DreamTheme.ink2)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 34)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                noteField
                if let errorMessage {
                    Text(errorMessage)
                        .font(DreamTheme.Font.text(12))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(recipients, id: \.id) { profile in
                            recipientRow(profile)
                            Divider().padding(.leading, 72)
                        }
                    }
                    .background(Color.white)
                }
            }
        }
    }

    private var noteField: some View {
        TextField("Add a message…", text: $note, axis: .vertical)
            .font(DreamTheme.Font.text(15))
            .foregroundStyle(DreamTheme.ink)
            .lineLimit(1...3)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(DreamTheme.line, lineWidth: 1))
            .padding(16)
    }

    private func recipientRow(_ profile: ProfileDTO) -> some View {
        HStack(spacing: 12) {
            Avatar(name: profile.name ?? "Dreamer", seed: profile.avatarSeed, size: 44,
                   url: profile.avatarURL.flatMap(URL.init(string:)))
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name ?? "Dreamer")
                    .font(DreamTheme.Font.text(15, weight: .semibold))
                    .foregroundStyle(DreamTheme.ink)
                    .lineLimit(1)
                Text("@\(profile.handle ?? "anon")")
                    .font(DreamTheme.Font.text(12))
                    .foregroundStyle(DreamTheme.ink2)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button { send(to: profile) } label: {
                if sending.contains(profile.id) {
                    ProgressView().tint(.white)
                        .frame(width: 60, height: 32)
                } else {
                    Text(sent.contains(profile.id) ? "Sent" : "Send")
                        .font(DreamTheme.Font.text(13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 60, height: 32)
                }
            }
            .background(Capsule().fill(sent.contains(profile.id) ? DreamTheme.ink3 : DreamTheme.blue))
            .buttonStyle(.plain)
            .disabled(sending.contains(profile.id) || sent.contains(profile.id))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func loadRecipients() async {
        isLoading = true
        recipients = await ProfileRepository.shared.followingProfiles()
            .sorted { ($0.name ?? $0.handle ?? "") < ($1.name ?? $1.handle ?? "") }
        isLoading = false
    }

    private func send(to profile: ProfileDTO) {
        errorMessage = nil
        sending.insert(profile.id)
        Task {
            do {
                try await VideoShareRepository.shared.share(
                    dream: dream,
                    recipientId: profile.id,
                    note: note.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                sent.insert(profile.id)
                onSent(profile.name ?? profile.handle ?? "friend")
                await ActivityRepository.shared.load()
            } catch {
                errorMessage = "Couldn't send that video. Please try again."
                print("[InAppShareSheet] send failed: \(error)")
            }
            sending.remove(profile.id)
        }
    }
}
