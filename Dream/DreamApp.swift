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
                // The entire design uses fixed light-mode colors (cream/white
                // backgrounds, dark `ink` text). Lock to light so nothing
                // adaptive (e.g. `.primary` text) flips to white on a device
                // running dark mode and becomes invisible on the light fields.
                .preferredColorScheme(.light)
                .task {
                    await AuthService.shared.restoreSession()
                }
        }
    }
}
