import SwiftUI
import UIKit

/// Thin wrapper around `UIActivityViewController` so a prepared file (a video on
/// disk) can be shared through the native share sheet — AirDrop, Messages, Save
/// to Files, Save Video, etc. Present via `.sheet(item:)` with a `ShareItem`.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Wraps a file URL so it can drive `.sheet(item:)` (which needs `Identifiable`).
struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}
