import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Photo-library video picker. Copies the chosen video to a stable temp file and
/// hands its URL back via `onPick` (the URL PHPicker provides is removed as soon
/// as the load closure returns, so we copy it first).
struct VideoLibraryPicker: UIViewControllerRepresentable {
    var onPick: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: VideoLibraryPicker
        init(_ parent: VideoLibraryPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            let movieType = UTType.movie.identifier
            guard let provider = results.first?.itemProvider,
                  provider.hasItemConformingToTypeIdentifier(movieType) else { return }

            provider.loadFileRepresentation(forTypeIdentifier: movieType) { url, error in
                guard let url, let dest = copyToTemp(url) else {
                    if let error { print("[VideoLibraryPicker] load failed: \(error)") }
                    return
                }
                DispatchQueue.main.async { self.parent.onPick(dest) }
            }
        }
    }
}

/// Camera video recorder. Falls back to the photo library when no camera is
/// available (e.g. the simulator).
struct VideoRecorder: UIViewControllerRepresentable {
    var onRecord: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        let movieType = UTType.movie.identifier
        let cameraSupportsVideo = UIImagePickerController.isSourceTypeAvailable(.camera)
            && (UIImagePickerController.availableMediaTypes(for: .camera) ?? []).contains(movieType)
        if cameraSupportsVideo {
            // sourceType must be set before mediaTypes; changing sourceType resets
            // mediaTypes to its defaults, clearing the movie type and causing
            // "cameraCaptureMode not available".
            picker.sourceType = .camera
            picker.mediaTypes = [movieType]
            picker.cameraCaptureMode = .video
            picker.videoQuality = .typeHigh
        } else {
            picker.sourceType = .photoLibrary
            picker.mediaTypes = [movieType]
        }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: VideoRecorder
        init(_ parent: VideoRecorder) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            parent.dismiss()
            guard let url = info[.mediaURL] as? URL, let dest = copyToTemp(url) else { return }
            parent.onRecord(dest)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

/// Copies a video at `url` into the temp directory under a fresh name so it
/// outlives the picker callback. Returns the new URL, or nil on failure.
private func copyToTemp(_ url: URL) -> URL? {
    let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
    let dest = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension(ext)
    do {
        try FileManager.default.copyItem(at: url, to: dest)
        return dest
    } catch {
        print("[VideoPicker] copy failed: \(error)")
        return nil
    }
}
