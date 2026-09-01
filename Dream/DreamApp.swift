//
//  DreamApp.swift
//  Dream
//
//  Created by Ivan Gabrilo on 24.05.2026..
//

import SwiftUI

@main
struct DreamApp: App {
    init() {
        // Synchronous, before any view is built, so nothing renders in SF first.
        DreamFonts.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // No `.preferredColorScheme` — every `DreamTheme` token is a
                // trait-resolving dynamic color, so the app follows the system
                // appearance. Chrome that sits over video (`Glass`, `OnMedia`)
                // is deliberately mode-invariant.
                .task {
                    await AuthService.shared.restoreSession()
                }
        }
    }
}
