import SwiftUI
import UIKit

/// Posts an update to an existing dream: record/pick a video or take/pick a
/// photo, add a title/caption, and publish it into the real media pipeline.
struct PostUpdateScreen: View {
    let dream: Dream
    var onClose: () -> Void = {}
    var onPosted: () -> Void = {}

    private enum Step { case source, details }
    private enum PickedKind { case video, photo }

    @State private var step: Step = .source
    @State private var title: String = ""
    @State private var caption: String = ""
    @State private var pickedKind: PickedKind?
    @State private var selectedVideoURL: URL?
    @State private var selectedPhoto: UIImage?
    @State private var videoThumbnail: UIImage?
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var showPhotoCamera = false
    @State private var showPhotoLibrary = false
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
            .fullScreenCover(isPresented: $showPhotoCamera) {
                PhotoCameraPicker { handlePickedPhoto($0) }.ignoresSafeArea()
            }
            .sheet(isPresented: $showPhotoLibrary) {
                PhotoLibraryPicker { handlePickedPhoto($0) }.ignoresSafeArea()
            }
        }
        .videoActions(videoActions)
    }

    private func handlePicked(_ url: URL) {
        pickedKind = .video
        selectedVideoURL = url
        selectedPhoto = nil
        step = .details
        Task { videoThumbnail = await loadVideoThumbnail(from: url) }
    }

    private func handlePickedPhoto(_ image: UIImage) {
        pickedKind = .photo
        selectedPhoto = image
        selectedVideoURL = nil
        videoThumbnail = nil
        step = .details
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

            Text("A new photo or video about “\(dream.title)”. Videos show up in Discover, and every update appears in Explore.")
                .font(DreamTheme.Font.text(15))
                .foregroundStyle(DreamTheme.ink2)
                .lineSpacing(3)
                .padding(.bottom, 28)

            VideoSourceCard(icon: "video.fill", title: "Record video", sub: "Up to 60 seconds · Vertical", tinted: true) {
                showCamera = true
            }
            .padding(.bottom, 12)

            VideoSourceCard(icon: "photo.on.rectangle", title: "Choose video", sub: "Pick an existing clip") {
                showLibrary = true
            }
            .padding(.bottom, 12)

            VideoSourceCard(icon: "camera.fill", title: "Take photo", sub: "Share a visual milestone") {
                showPhotoCamera = true
            }
            .padding(.bottom, 12)

            VideoSourceCard(icon: "photo.fill.on.rectangle.fill", title: "Choose photo", sub: "Pick an existing image") {
                showPhotoLibrary = true
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    // MARK: - Details step

    private var detailsStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                videoPreview

                VStack(alignment: .leading, spacing: 10) {
                    Text("TITLE")
                        .font(DreamTheme.Font.text(11, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(DreamTheme.ink2)
                    TextField("e.g. We just hit our first milestone", text: $title)
                        .font(DreamTheme.Font.text(15))
                        .foregroundStyle(Color.black)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(DreamTheme.bg))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(DreamTheme.line, lineWidth: 1))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("CAPTION")
                        .font(DreamTheme.Font.text(11, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(DreamTheme.ink2)
                    TextField("Add a little context...", text: $caption, axis: .vertical)
                        .font(DreamTheme.Font.text(15))
                        .foregroundStyle(Color.black)
                        .lineLimit(3...8)
                        .padding(14)
                        .frame(minHeight: 90, alignment: .topLeading)
                        .background(RoundedRectangle(cornerRadius: 14).fill(DreamTheme.bg))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(DreamTheme.line, lineWidth: 1))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            detailsFooter
        }
    }

    private var detailsFooter: some View {
        VStack(spacing: 0) {
            Divider().background(DreamTheme.line)
            VStack(spacing: 10) {
                if let postError {
                    Text(postError)
                        .font(DreamTheme.Font.text(13))
                        .foregroundStyle(DreamTheme.error)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                PrimaryButton(
                    title: isPosting ? "Posting..." : "Post update",
                    background: (canPost && !isPosting) ? DreamTheme.blue : DreamTheme.ink3,
                    action: { Task { await post() } }
                )
                .disabled(!canPost || isPosting)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .background(Color.white)
        }
    }

    private var canPost: Bool {
        pickedKind != nil && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @MainActor
    private func post() async {
        guard canPost, !isPosting else { return }
        isPosting = true
        postError = nil
        defer { isPosting = false }

        do {
            let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
            let captionValue = cleanCaption.isEmpty ? nil : cleanCaption
            switch pickedKind {
            case .video:
                guard let selectedVideoURL else { return }
                _ = try await VideoUploader.shared.upload(
                    localVideoURL: selectedVideoURL,
                    dreamId: dream.id,
                    markPrimary: false,
                    title: cleanTitle,
                    caption: captionValue
                )
                await DreamRepository.shared.loadFeed()
            case .photo:
                guard let selectedPhoto else { return }
                _ = try await DreamImageUploader.shared.upload(
                    image: selectedPhoto,
                    dreamId: dream.id,
                    title: cleanTitle,
                    caption: captionValue
                )
            case nil:
                return
            }
            await ExploreMediaRepository.shared.loadRecent()
            onPosted()
        } catch {
            postError = "Couldn't post your update. Please try again."
            print("[PostUpdateScreen] post failed: \(error)")
        }
    }

    @ViewBuilder
    private var videoPreview: some View {
        switch pickedKind {
        case .video:
            VideoPreviewCard(
                thumbnail: videoThumbnail,
                category: dream.category,
                rePickLabel: "Re-pick",
                onRePick: { step = .source },
                onSave: selectedVideoURL.map { url in { videoActions.save(localURL: url) } }
            )
        case .photo:
            PhotoPreviewCard(
                image: selectedPhoto,
                category: dream.category,
                rePickLabel: "Re-pick",
                onRePick: { step = .source }
            )
        case nil:
            EmptyView()
        }
    }
}
