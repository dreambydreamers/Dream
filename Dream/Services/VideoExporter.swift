import Combine
import Photos
import SwiftUI

/// Downloads a private dream video to a local file and saves it to the Photos
/// library. The share path reuses the same local copy through the native share
/// sheet (AirDrop / Messages / Save to Files / Save Video). Stateless helpers;
/// per-screen state lives in `VideoActionsModel`.
enum VideoExporter {
    enum ExportError: LocalizedError {
        case prepareFailed
        case photosDenied
        case saveFailed

        var errorDescription: String? {
            switch self {
            case .prepareFailed: return "Couldn't prepare the video. Check your connection and try again."
            case .photosDenied:  return "Allow Photos access in Settings to save videos."
            case .saveFailed:    return "Couldn't save the video to Photos."
            }
        }
    }

    /// Signs the private storage URL, downloads the clip, and returns a local
    /// `.mp4` file URL (named so the share sheet shows a sensible filename).
    static func prepareLocalCopy(storagePath: String) async throws -> URL {
        let signed = try await VideoUploader.shared.signedVideoURL(storagePath: storagePath)
        do {
            let (tempURL, _) = try await URLSession.shared.download(from: signed)
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("Dream-\(UUID().uuidString.prefix(8))")
                .appendingPathExtension("mp4")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tempURL, to: dest)
            return dest
        } catch {
            throw ExportError.prepareFailed
        }
    }

    /// Saves a local video file to the user's Photos library, requesting
    /// add-only permission first.
    static func saveToPhotos(localURL: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw ExportError.photosDenied
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: localURL)
            }
        } catch {
            throw ExportError.saveFailed
        }
    }
}

/// Drives the share/save UI for one screen. Create one per screen, attach
/// `.videoActions(model)`, and call `share`/`save` from buttons.
@MainActor
final class VideoActionsModel: ObservableObject {
    @Published var isPreparing = false
    @Published var shareItem: ShareItem?
    @Published var errorMessage: String?
    @Published var toast: String?

    private var toastTask: Task<Void, Never>?

    /// Shares the video at a private storage path through the native share sheet.
    func share(storagePath: String?) {
        guard let storagePath, !isPreparing else { return }
        isPreparing = true
        Task {
            defer { isPreparing = false }
            do {
                let url = try await VideoExporter.prepareLocalCopy(storagePath: storagePath)
                shareItem = ShareItem(url: url)
            } catch {
                show(error: error)
            }
        }
    }

    /// Downloads the video at a private storage path and saves it to Photos.
    func save(storagePath: String?) {
        guard let storagePath, !isPreparing else { return }
        isPreparing = true
        Task {
            defer { isPreparing = false }
            do {
                let url = try await VideoExporter.prepareLocalCopy(storagePath: storagePath)
                try await VideoExporter.saveToPhotos(localURL: url)
                flash("Saved to Photos")
            } catch {
                show(error: error)
            }
        }
    }

    /// Saves an already-local clip (e.g. a freshly recorded compose preview) to
    /// Photos — no download needed.
    func save(localURL: URL) {
        guard !isPreparing else { return }
        isPreparing = true
        Task {
            defer { isPreparing = false }
            do {
                try await VideoExporter.saveToPhotos(localURL: localURL)
                flash("Saved to Photos")
            } catch {
                show(error: error)
            }
        }
    }

    private func show(error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
    }

    private func flash(_ message: String) {
        toastTask?.cancel()
        toast = message
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
}

// MARK: - View attachment

private struct VideoActionsModifier: ViewModifier {
    @ObservedObject var model: VideoActionsModel

    func body(content: Content) -> some View {
        content
            .sheet(item: $model.shareItem) { item in
                ShareSheet(items: [item.url])
            }
            .alert(
                "Something went wrong",
                isPresented: Binding(
                    get: { model.errorMessage != nil },
                    set: { if !$0 { model.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
            .overlay(alignment: .bottom) {
                if let toast = model.toast {
                    actionToast(toast)
                        .padding(.bottom, 120)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .overlay {
                if model.isPreparing {
                    preparingHUD
                        .transition(.opacity)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.toast)
            .animation(.easeOut(duration: 0.2), value: model.isPreparing)
    }

    private func actionToast(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .bold))
            Text(message)
                .font(DreamTheme.Font.text(14, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(DreamTheme.ink, in: Capsule())
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
    }

    private var preparingHUD: some View {
        VStack(spacing: 12) {
            ProgressView().tint(.white)
            Text("Preparing…")
                .font(DreamTheme.Font.text(13, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(22)
        .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

extension View {
    /// Attaches the share sheet, error alert, success toast and "Preparing…" HUD
    /// driven by a `VideoActionsModel`. Pair with `model.share`/`model.save`.
    func videoActions(_ model: VideoActionsModel) -> some View {
        modifier(VideoActionsModifier(model: model))
    }
}
