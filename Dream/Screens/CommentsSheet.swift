import SwiftUI

/// Comment thread for a feed card. Presented as a sheet from Discover; posts
/// as the signed-in user and lets authors (or the dream owner) delete.
struct CommentsSheet: View {
    let dream: Dream
    var onClose: () -> Void = {}
    /// Reports the new total so the feed badge can update immediately.
    var onCountChanged: (Int) -> Void = { _ in }

    @ObservedObject private var auth = AuthService.shared
    @State private var comments: [DreamComment] = []
    @State private var isLoading = true
    @State private var draft = ""
    @State private var isPosting = false
    @State private var errorMessage: String?
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header

            if isLoading {
                Spacer()
                ProgressView().tint(DreamTheme.blue)
                Spacer()
            } else if comments.isEmpty {
                emptyState
            } else {
                thread
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(DreamTheme.Font.text(12))
                    .foregroundStyle(DreamTheme.error)
                    .padding(.bottom, 6)
            }

            inputBar
        }
        .background(DreamTheme.paper)
        .keyboardDoneButton()
        .task {
            comments = await CommentRepository.shared.comments(forDream: dream.id)
            isLoading = false
        }
    }

    // MARK: - Pieces

    private var header: some View {
        ZStack {
            Text("Comments")
                .font(DreamTheme.Font.display(17, weight: .medium))
                .foregroundStyle(DreamTheme.ink)
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DreamTheme.ink2)
                        .padding(9)
                        .background(DreamTheme.cream, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close comments")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(DreamTheme.ink3)
            Text("No comments yet")
                .font(DreamTheme.Font.text(15, weight: .semibold))
                .foregroundStyle(DreamTheme.ink)
            Text("Say something encouraging — dreamers read these.")
                .font(DreamTheme.Font.text(13))
                .foregroundStyle(DreamTheme.ink2)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }

    private var thread: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(comments) { comment in
                        commentRow(comment)
                            .id(comment.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: comments.count) { _, _ in
                if let last = comments.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func commentRow(_ comment: DreamComment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Avatar(name: comment.name, seed: comment.avatarSeed, size: 32, url: comment.avatarURL)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("@\(comment.handle)")
                        .font(DreamTheme.Font.text(12, weight: .semibold))
                        .foregroundStyle(DreamTheme.ink2)
                    Text(relativeTime(comment.createdAt))
                        .font(DreamTheme.Font.text(11))
                        .foregroundStyle(DreamTheme.ink3)
                }
                Text(comment.body)
                    .font(DreamTheme.Font.text(14))
                    .foregroundStyle(DreamTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .contextMenu {
            if canDelete(comment) {
                Button(role: .destructive) {
                    delete(comment)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Add a comment…", text: $draft, axis: .vertical)
                .font(DreamTheme.Font.text(15))
                .foregroundStyle(DreamTheme.ink)
                .lineLimit(1...4)
                .focused($inputFocused)
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(DreamTheme.line, lineWidth: 1))

            Button(action: post) {
                if isPosting {
                    ProgressView().tint(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(DreamTheme.blue.opacity(0.6)))
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(canPost ? DreamTheme.blue : DreamTheme.ink3))
                }
            }
            .buttonStyle(.plain)
            .disabled(!canPost || isPosting)
            .accessibilityLabel("Post comment")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(DreamTheme.paper)
    }

    // MARK: - Actions

    private var canPost: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func canDelete(_ comment: DreamComment) -> Bool {
        comment.userId == auth.userId || dream.ownerId == auth.userId
    }

    private func post() {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !isPosting else { return }
        isPosting = true
        errorMessage = nil
        Task {
            defer { isPosting = false }
            do {
                let posted = try await CommentRepository.shared.post(
                    dreamId: dream.id, videoId: dream.videoId, body: body)
                comments.append(posted)
                draft = ""
                onCountChanged(comments.count)
            } catch {
                print("[CommentsSheet] post failed: \(error)")
                errorMessage = "Couldn't post your comment. Please try again."
            }
        }
    }

    private func delete(_ comment: DreamComment) {
        Task {
            do {
                try await CommentRepository.shared.delete(comment.id)
                comments.removeAll { $0.id == comment.id }
                onCountChanged(comments.count)
            } catch {
                print("[CommentsSheet] delete failed: \(error)")
                errorMessage = "Couldn't delete that comment."
            }
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
