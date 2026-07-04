import SwiftUI
import UIKit

/// Posts an "update" clip to an existing dream: pick/record a video, give it its
/// own heading, and upload it as a non-primary `dream_videos` row. The clip then
/// surfaces in Discover (interleaved by recency) and on the owner's profile,
/// treated like the dream's cover video.
struct PostUpdateScreen: View {
    let dream: Dream
    var onClose: () -> Void = {}
    var onPosted: () -> Void = {}

    private enum Step { case source, details }

    @State private var step: Step = .source
    @State private var heading: String = ""
    @State private var selectedVideoURL: URL?
    @State private var videoThumbnail: UIImage?
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var isPosting = false
    @State private var postError: String?
    @StateObject private var videoActions = VideoActionsModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                switch step {
                case .source: sourceStep
                case .details: detailsStep
                }
            }
            .background(Color.white.ignoresSafeArea())
            .keyboardDoneButton()
            .navigationTitle(step == .source ? "Post an update" : "Update details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if step == .details {
                        Button { step = .source } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(DreamTheme.ink)
                        }
                        .accessibilityLabel("Back")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(DreamTheme.ink2)
                    }
                    .accessibilityLabel("Close")
                }
            }
            .videoSourcePicker(showCamera: $showCamera, showLibrary: $showLibrary, onPick: handlePicked)
        }
        .videoActions(videoActions)
    }

    private func handlePicked(_ url: URL) {
        selectedVideoURL = url
        step = .details
        Task { videoThumbnail = await loadVideoThumbnail(from: url) }
    }

    // MARK: - Source step

    private var sourceStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Share an update")
                .font(DreamTheme.Font.display(30, weight: .regular))
                .tracking(-0.7)
                .foregroundStyle(DreamTheme.ink)
                .padding(.top, 16)
                .padding(.bottom, 8)

            Text("A new clip about “\(dream.title)”. It shows up in Discover next to your main video.")
                .font(DreamTheme.Font.text(15))
                .foregroundStyle(DreamTheme.ink2)
                .lineSpacing(3)
                .padding(.bottom, 28)

            VideoSourceCard(icon: "video.fill", title: "Record video", sub: "Up to 60 seconds · Vertical", tinted: true) {
                showCamera = true
            }
            .padding(.bottom, 12)

            VideoSourceCard(icon: "photo.on.rectangle", title: "Choose from library", sub: "Pick an existing video") {
                showLibrary = true
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    // MARK: - Details step

    private var detailsStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    videoPreview

                    VStack(alignment: .leading, spacing: 10) {
                        Text("HEADING")
                            .font(DreamTheme.Font.text(11, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(DreamTheme.ink2)
                        TextField("e.g. We just hit our first milestone", text: $heading)
                            .font(DreamTheme.Font.text(15))
                            .foregroundStyle(Color.black)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(DreamTheme.bg))
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(DreamTheme.line, lineWidth: 1))
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)

            Divider().background(DreamTheme.line)
            VStack(spacing: 10) {
                if let postError {
                    Text(postError)
                        .font(DreamTheme.Font.text(13))
                        .foregroundStyle(DreamTheme.error)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                PrimaryButton(
                    title: isPosting ? "Posting…" : "Post update",
                    background: (canPost && !isPosting) ? DreamTheme.blue : DreamTheme.ink3,
                    action: { Task { await post() } }
                )
                .disabled(!canPost || isPosting)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 24)
            .background(Color.white)
        }
    }

    private var canPost: Bool {
        selectedVideoURL != nil && !heading.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @MainActor
    private func post() async {
        guard canPost, !isPosting, let selectedVideoURL else { return }
        isPosting = true
        postError = nil
        defer { isPosting = false }

        do {
            _ = try await VideoUploader.shared.upload(
                localVideoURL: selectedVideoURL,
                dreamId: dream.id,
                markPrimary: false,
                title: heading.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            await DreamRepository.shared.loadFeed()
            onPosted()
        } catch {
            postError = "Couldn't post your update. Please try again."
            print("[PostUpdateScreen] post failed: \(error)")
        }
    }

    private var videoPreview: some View {
        VideoPreviewCard(
            thumbnail: videoThumbnail,
            category: dream.category,
            rePickLabel: "Re-pick",
            onRePick: { step = .source },
            onSave: selectedVideoURL.map { url in { videoActions.save(localURL: url) } }
        )
    }
}
