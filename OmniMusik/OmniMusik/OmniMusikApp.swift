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
    @State private var auth: AuthController
    @State private var playlistStore: PlaylistStore
    @State private var syncService: PlaylistSyncService
    @State private var connections: SourceConnectionCenter
    @State private var registry: MusicSourceRegistry
    private let spotify: SpotifySource
    @State private var spotifyProvider: SpotifyPlaybackProvider?
    @Environment(\.scenePhase) private var scenePhase
    /// Skipped under UI tests: the overlay covers the tab bar, so a tap lands on it
    /// rather than on the app, and every test would race a decorative animation.
    @State private var isLaunching = !ProcessInfo.processInfo.arguments.contains("-disableLaunchAnimation")

    /// Built explicitly rather than via `.modelContainer(for:)` so the same
    /// container can be handed to `LocalMusicSource`, which needs its own context.
    private let container: ModelContainer

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: LocalTrackEntity.self, PlaylistEntity.self)
        } catch {
            // Nothing in the app works without a store, and there is no meaningful
            // recovery: a corrupt container needs a reinstall, not a retry.
            fatalError("Could not create the model container: \(error)")
        }
        self.container = container

        // One source list feeds both search and the library, so a source added
        // later appears in both without being registered twice.
        let appleMusic = AppleMusicSource()
        let spotify = SpotifySource()
        self.spotify = spotify
        let sources: [any MusicSource] = [
            LocalMusicSource(container: container),
            appleMusic,
            spotify
        ]

        // Only sources that need an account appear here; local files have none.
        // A source added later joins both lists and shows up in the account screen
        // without that screen changing.
        _connections = State(initialValue: SourceConnectionCenter(sources: [appleMusic, spotify]))

        // Playlists resolve their entries against the same source list, so a
        // source added later becomes playable inside existing playlists too.
        _playlistStore = State(initialValue: PlaylistStore(container: container, sources: sources))

        _registry = State(initialValue: MusicSourceRegistry(sources: sources))
        _searchService = State(initialValue: SearchService(sources: sources))
        _libraryStore = State(initialValue: LibraryStore(sources: sources))

        // The provider is the only Cognito-aware object in the app; everything
        // else sees `AuthController` and the vendor-neutral types behind it.
        let auth = AuthController(provider: CognitoAuthProvider(configuration: .deployed))
        _auth = State(initialValue: auth)

        // The API takes a token provider rather than the controller itself, so the
        // refresh rule stays in one place and the client holds no session state.
        let api = OmniMusikAPI(baseURL: APIConfiguration.baseURL) {
            try await auth.validAccessToken()
        }
        _syncService = State(initialValue: PlaylistSyncService(container: container, api: api))
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                .environment(coordinator)
                .environment(searchService)
                .environment(libraryStore)
                .environment(auth)
                .environment(playlistStore)
                .environment(syncService)
                .environment(connections)
                .environment(registry)
                .task {
                    // Spotify playback needs a token from the connected source. Done
                    // here rather than in the coordinator so the coordinator keeps no
                    // knowledge of how a token is obtained.
                    let provider = SpotifyPlaybackProvider {
                        try await spotify.accessTokenForPlayback()
                    }
                    coordinator.attachSpotifyProvider(provider)
                    spotifyProvider = provider
                    await provider.connectIfPossible()
                }
                .onChange(of: scenePhase) { _, phase in
                    HandoffLog.note("scenePhase -> \(phase)")
                    guard phase == .active else {
                        // Backgrounding means the switch happened and the transition
                        // has served its purpose. Clearing it here rather than on a
                        // timer matters: a Task scheduled before the switch is
                        // suspended along with the app, so the flag could still be
                        // set on return and the next handoff would find it already
                        // true -- no state change, no animation.
                        coordinator.endHandoffTransition()
                        return
                    }
                    // SPTAppRemote drops its connection when the app backgrounds.
                    // Re-establishing it on return means the first track someone taps
                    // plays in place rather than bouncing them into Spotify.
                    Task { await spotifyProvider?.connectIfPossible() }
                }

                if isLaunching {
                    LaunchView { withAnimation(.smooth(duration: 0.28)) { isLaunching = false } }
                        .transition(.opacity)
                        // The app underneath is already live; this only covers it.
                        // Nothing waits on the animation, so a slow launch is never
                        // made slower by it.
                        .zIndex(1)
                }
            }
        }
        .modelContainer(container)
    }
}
