import CoreText
import Foundation
import UIKit

/// Registers the bundled Instrument faces with Core Text at launch.
///
/// The target uses `GENERATE_INFOPLIST_FILE = YES`, and `UIAppFonts` is an array —
/// which build settings can't express — so the usual plist route isn't available.
/// Registering at runtime works with the synchronized-group file layout and keeps
/// font onboarding to "drop a `.ttf` in `Resources/Fonts`".
///
/// A silent failure here is expensive: `Font.custom` falls back to the system face
/// without complaint, so the app looks *almost* right and the cause is invisible.
/// `register()` therefore verifies every expected face afterwards and logs loudly.
enum DreamFonts {
    private static let expectedFaces = [
        DreamFontFace.sansRegular,
        DreamFontFace.sansMedium,
        DreamFontFace.sansSemiBold,
        DreamFontFace.sansBold,
        DreamFontFace.sansItalic,
        DreamFontFace.serifRegular,
        DreamFontFace.serifItalic,
    ]

    static func register() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        guard !urls.isEmpty else {
            assertionFailure("No .ttf files in the bundle — is Resources/Fonts included in the target?")
            return
        }

        // Deliberately the per-URL call: `CTFontManagerRegisterFontURLs` is always
        // asynchronous, which would let the first frame render in the system face
        // and flash. This one is synchronous, so the faces are live before any view
        // is built.
        for url in urls {
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                // Already-registered is benign (e.g. a SwiftUI preview reloading).
                let cfError = error?.takeRetainedValue()
                if CFErrorGetCode(cfError) != CTFontManagerError.alreadyRegistered.rawValue {
                    print("⚠️ [DreamFonts] Failed to register \(url.lastPathComponent): \(String(describing: cfError))")
                }
            }
        }

        verify()
    }

    /// Fails the build's own smoke test in debug and leaves a breadcrumb in release.
    private static func verify() {
        let missing = expectedFaces.filter { UIFont(name: $0, size: 12) == nil }
        guard !missing.isEmpty else { return }

        let message = "Font registration incomplete — falling back to system for: \(missing.joined(separator: ", "))"
        print("⚠️ [DreamFonts] \(message)")
        assertionFailure(message)
    }
}
