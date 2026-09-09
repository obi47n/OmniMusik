//
//  ContentView.swift
//  OmniMusik
//
//  Root shell: library and search, with a persistent mini player docked above the
//  tab bar that expands into the full Now Playing view.
//

import SwiftUI

struct ContentView: View {
    @Environment(PlaybackCoordinator.self) private var coordinator
    @State private var showingNowPlaying = false

    var body: some View {
        TabView {
            Tab("Library", systemImage: "music.note.list") {
                NavigationStack { LibraryView() }
            }

            // Distinct from Library's icon: two tabs sharing music.note.list
            // gave the tab bar two identical glyphs.
            Tab("Playlists", systemImage: "list.bullet.rectangle") {
                NavigationStack { PlaylistsView() }
            }

            Tab("Search", systemImage: "magnifyingglass") {
                NavigationStack { SearchView() }
            }

            Tab("Account", systemImage: "person.crop.circle") {
                NavigationStack { AccountView() }
            }
        }
        // safeAreaInset rather than iOS 26's .tabViewBottomAccessory: the deployment
        // target is iOS 18, and this docks the player above the tab bar on every
        // version without an availability fork.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if coordinator.currentTrack != nil {
                MiniPlayerView(onTap: { showingNowPlaying = true })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: coordinator.currentTrack)
        .sheet(isPresented: $showingNowPlaying) {
            NowPlayingView()
        }
        .alert(
            "Playback Problem",
            isPresented: Binding(
                get: { coordinator.errorMessage != nil },
                set: { if !$0 { coordinator.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { coordinator.errorMessage = nil }
        } message: {
            Text(coordinator.errorMessage ?? "")
        }
    }
}
