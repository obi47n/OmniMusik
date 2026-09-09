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
                docked { NavigationStack { LibraryView() } }
            }

            // Distinct from Library's icon: two tabs sharing music.note.list
            // gave the tab bar two identical glyphs.
            Tab("Playlists", systemImage: "list.bullet.rectangle") {
                docked { NavigationStack { PlaylistsView() } }
            }

            Tab("Search", systemImage: "magnifyingglass") {
                docked { NavigationStack { SearchView() } }
            }

            Tab("Account", systemImage: "person.crop.circle") {
                docked { NavigationStack { AccountView() } }
            }
        }
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

    /// Docks the mini player above the tab bar for one tab's content.
    ///
    /// The inset goes on the tab's *content*, not on the `TabView`. Applied to the
    /// TabView it inserts into the tab bar's own space and draws the player straight
    /// over the tab buttons, which is a real bug this had: the player rendered inside
    /// the tab bar's frame and covered it whenever anything was playing.
    ///
    /// Per-tab means four instances rather than one, which is the accepted cost.
    /// `MiniPlayerView` is stateless and reads everything from the coordinator, so
    /// they cannot disagree, and only the selected tab's is ever on screen.
    ///
    /// iOS 26's `.tabViewBottomAccessory` does this natively, but the deployment
    /// target is iOS 18 and this needs no availability fork.
    private func docked<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            // Above the player rather than as an alert: the app is about to be sent to
        // the background, so a modal would be dismissed unseen. A banner is still
        // here on the way back, which is when the explanation is actually wanted.
        .safeAreaInset(edge: .top, spacing: 0) {
            if let notice = coordinator.handoffNotice {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "arrow.up.forward.app")
                    Text(notice).font(.caption)
                    Spacer(minLength: 0)
                    Button {
                        coordinator.clearHandoffNotice()
                    } label: {
                        Image(systemName: "xmark").font(.caption2)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.thinMaterial)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task {
                    // Long enough to read on return from Spotify, short enough not
                    // to become furniture.
                    try? await Task.sleep(for: .seconds(8))
                    coordinator.clearHandoffNotice()
                }
            }
        }
        .animation(.snappy(duration: 0.25), value: coordinator.handoffNotice)
        .safeAreaInset(edge: .bottom, spacing: 0) {
                if coordinator.currentTrack != nil {
                    MiniPlayerView(onTap: { showingNowPlaying = true })
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.25), value: coordinator.currentTrack)
    }
}
