//
//  ContentView.swift
//  OmniMusik
//
//  Root shell: the library, with a persistent mini player docked above the tab bar
//  that expands into the full Now Playing view.
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

            Tab("Search", systemImage: "magnifyingglass") {
                NavigationStack {
                    ComingSoonView(
                        title: "Universal Search",
                        message: "Search across Apple Music and your local files from one place.",
                        systemImage: "magnifyingglass"
                    )
                    .navigationTitle("Search")
                }
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

/// Placeholder for surfaces arriving in later weeks. Present from the start so the
/// shell's navigation is real rather than being restructured later.
struct ComingSoonView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        }
    }
}
