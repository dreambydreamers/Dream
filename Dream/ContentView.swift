//
//  ContentView.swift
//  Dream
//

import SwiftUI

struct ContentView: View {
    /// Debug escape hatch to the component gallery — see `DesignSystemGallery`.
    /// Lets a token or component change be checked in both color schemes without
    /// signing in first. Never enabled in a release build.
    static let showsDesignGallery = false

    var body: some View {
        #if DEBUG
        if Self.showsDesignGallery {
            DesignSystemGallery()
        } else {
            RootView()
        }
        #else
        RootView()
        #endif
    }
}

#Preview {
    ContentView()
}
