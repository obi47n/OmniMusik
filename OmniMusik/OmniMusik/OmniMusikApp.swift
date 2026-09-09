//
//  OmniMusikApp.swift
//  OmniMusik
//

import SwiftData
import SwiftUI

@main
struct OmniMusikApp: App {

    /// Playback outlives any view, so the coordinator is owned here and injected.
    @State private var coordinator = PlaybackCoordinator()
    @State private var searchService: SearchService
    @State private var libraryStore: LibraryStore

    /// Built explicitly rather than via `.modelContainer(for:)` so the same
    /// container can be handed to `LocalMusicSource`, which needs its own context.
    private let container: ModelContainer

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: LocalTrackEntity.self)
        } catch {
            // Nothing in the app works without a store, and there is no meaningful
            // recovery: a corrupt container needs a reinstall, not a retry.
            fatalError("Could not create the model container: \(error)")
        }
        self.container = container

        // One source list feeds both search and the library, so a source added
        // later appears in both without being registered twice.
        let sources: [any MusicSource] = [
            LocalMusicSource(container: container),
            AppleMusicSource()
        ]

        _searchService = State(initialValue: SearchService(sources: sources))
        _libraryStore = State(initialValue: LibraryStore(sources: sources))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(coordinator)
                .environment(searchService)
                .environment(libraryStore)
        }
        .modelContainer(container)
    }
}
