import SwiftUI
import UIKit

private enum CreateStep { case source, details }

struct CreateDreamScreen: View {
    var onClose: () -> Void = {}
    var onPublish: () -> Void = {}

    @State private var step: CreateStep = .source
    @State private var title: String = ""
    @State private var category: DreamCategory?
    @State private var stage: DreamStage?
    @State private var helpNeeded: Set<String> = []
    @State private var desc: String = ""
    @State private var hasMedia: Bool = false
    /// File URL of a picked/recorded video, uploaded on publish.
    @State private var selectedVideoURL: URL?
    @State private var videoThumbnail: UIImage?
    @State private var showCamera: Bool = false
    @State private var showLibrary: Bool = false
    @State private var isPublishing: Bool = false
    @State private var publishError: String?
    @StateObject private var videoActions = VideoActionsModel()

    private let helps = ["Coding", "Design", "Funding", "Mentorship", "Marketing", "Legal"]

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
            .navigationTitle(step == .source ? "Share your dream" : "Dream details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if step == .details {
                        Button { step = .source } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(DreamTheme.ink)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(DreamTheme.ink2)
                        }
                }
            }
            .videoSourcePicker(showCamera: $showCamera, showLibrary: $showLibrary, onPick: handlePicked)
        }
        .videoActions(videoActions)
    }

    private func handlePicked(_ url: URL) {
        selectedVideoURL = url
        hasMedia = true
        step = .details
        Task { videoThumbnail = await loadVideoThumbnail(from: url) }
    }

    // MARK: - Source step

    private var sourceStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("What's your dream?")
                .font(DreamTheme.Font.display(32, weight: .regular))
                .tracking(-0.7)
                .foregroundStyle(DreamTheme.ink)
                .padding(.top, 16)
                .padding(.bottom, 8)

            Text("A short video is the best way to share it. Speak from the heart — supporters listen.")
                .font(DreamTheme.Font.text(15))
                .foregroundStyle(DreamTheme.ink2)
                .lineSpacing(3)
                .padding(.bottom, 28)

            VideoSourceCard(
                icon: "video.fill",
                title: "Record video",
                sub: "Up to 60 seconds · Vertical",
                tinted: true
            ) {
                showCamera = true
            }
            .padding(.bottom, 12)

            VideoSourceCard(
                icon: "photo.on.rectangle",
                title: "Choose from library",
                sub: "Pick an existing video"
            ) {
                showLibrary = true
            }

            Spacer()

            HStack(alignment: .top, spacing: 10) {
                Text("💡")
                VStack(alignment: .leading, spacing: 4) {
                    Text("Simon's advice")
                        .font(DreamTheme.Font.text(13, weight: .bold))
                        .foregroundStyle(Color(hex: 0x7A5F3E))
                    Text("Start with why. What would this dream mean to you if it came true?")
                        .font(DreamTheme.Font.text(13))
                        .foregroundStyle(Color(hex: 0x7A5F3E))
                        .lineSpacing(2)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(DreamTheme.warm))
            .padding(.top, 16)
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

                    field("Title") {
                        TextField("e.g. A quiet café for writers", text: $title)
                            .font(DreamTheme.Font.text(15))
                            .foregroundStyle(Color.black)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(DreamTheme.bg))
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(DreamTheme.line, lineWidth: 1))
                    }

                    field("Category") {
                        FlowLayout(spacing: 8, lineSpacing: 8) {
                            ForEach(DreamCategory.allCases, id: \.self) { c in
                                chip(label: c.rawValue, selected: category == c) {
                                    category = (category == c) ? nil : c
                                }
                            }
                        }
                    }

                    field("Stage") {
                        FlowLayout(spacing: 8, lineSpacing: 8) {
                            ForEach([DreamStage.idea, .early, .needs, .almost], id: \.rawValue) { s in
                                chip(label: s.rawValue, selected: stage == s) {
                                    stage = (stage == s) ? nil : s
                                }
                            }
                        }
                    }

                    field("Help needed") {
                        FlowLayout(spacing: 8, lineSpacing: 8) {
                            ForEach(helps, id: \.self) { h in
                                chip(label: h, selected: helpNeeded.contains(h)) {
                                    if helpNeeded.contains(h) { helpNeeded.remove(h) } else { helpNeeded.insert(h) }
                                }
                            }
                        }
                    }

                    field("Description (optional)") {
                        TextField("Share more about your dream...", text: $desc, axis: .vertical)
                            .font(DreamTheme.Font.text(15))
                            .foregroundStyle(Color.black)
                            .lineLimit(4...10)
                            .padding(14)
                            .frame(minHeight: 100, alignment: .topLeading)
                            .background(RoundedRectangle(cornerRadius: 14).fill(DreamTheme.bg))
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(DreamTheme.line, lineWidth: 1))
                    }
                }
                .padding(20)
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)

            Divider().background(DreamTheme.line)
            VStack(spacing: 10) {
                if let publishError {
                    Text(publishError)
                        .font(DreamTheme.Font.text(13))
                        .foregroundStyle(Color(hex: 0xB83D45))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                PrimaryButton(
                    title: isPublishing ? "Publishing…" : "Publish dream",
                    background: (canPublish && !isPublishing) ? (category?.palette.fg ?? DreamTheme.blue) : DreamTheme.ink3,
                    action: { Task { await publish() } }
                )
                .disabled(!canPublish || isPublishing)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 24)
            .background(Color.white)
        }
    }

    private var canPublish: Bool {
        !title.isEmpty && category != nil && stage != nil && !helpNeeded.isEmpty
    }

    @MainActor
    private func publish() async {
        guard canPublish, !isPublishing, let category, let stage else { return }
        isPublishing = true
        publishError = nil
        defer { isPublishing = false }

        do {
            let dreamId = try await DreamRepository.shared.createDream(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                description: desc.trimmingCharacters(in: .whitespacesAndNewlines),
                category: category,
                stage: stage,
                location: nil,
                helpTags: helpNeeded.sorted()
            )

            if let selectedVideoURL {
                _ = try await VideoUploader.shared.upload(localVideoURL: selectedVideoURL, dreamId: dreamId)
            }

            // Refresh the shared feed so the new dream shows up in Discover.
            await DreamRepository.shared.loadFeed()
            onPublish()
        } catch {
            publishError = "Couldn't publish. Please try again."
            print("[CreateDreamScreen] publish failed: \(error)")
        }
    }

    private var videoPreview: some View {
        VideoPreviewCard(
            thumbnail: videoThumbnail,
            category: category ?? .tech,
            rePickLabel: "Re-record",
            onRePick: { step = .source },
            onSave: selectedVideoURL.map { url in { videoActions.save(localURL: url) } }
        )
    }

    @ViewBuilder
    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label.uppercased())
                .font(DreamTheme.Font.text(11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(DreamTheme.ink2)
            content()
        }
    }

    private func chip(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(DreamTheme.Font.text(13, weight: .semibold))
                .foregroundStyle(selected ? .white : DreamTheme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Capsule().fill(selected ? DreamTheme.blue : Color.white))
                .overlay(Capsule().strokeBorder(selected ? DreamTheme.blue : DreamTheme.line, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    CreateDreamScreen()
}
