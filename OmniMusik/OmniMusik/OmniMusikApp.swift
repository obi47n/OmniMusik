//
//  OmniMusikApp.swift
//  OmniMusik
//

import SwiftData
import SwiftUI

@main
struct OmniMusikApp: App {

    /// One coordinator for the app's lifetime. Playback outlives any individual
    /// view, so it's owned here and injected rather than created inside a view.
    @State private var coordinator = PlaybackCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(coordinator)
        }
        .modelContainer(for: LocalTrackEntity.self)
    }
}
