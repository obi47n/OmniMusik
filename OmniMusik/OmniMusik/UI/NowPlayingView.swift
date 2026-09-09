//
//  NowPlayingView.swift
//  OmniMusik
//

import SwiftUI

struct NowPlayingView: View {
    @Environment(PlaybackCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss

    /// While the user drags, the slider is driven by local state instead of the
    /// coordinator — otherwise the 200ms position poll fights the gesture and the
    /// thumb jumps backward under the thumb.
    @State private var scrubPosition: TimeInterval = 0
    @State private var isScrubbing = false
    @State private var showingQueue = false
    @State private var addToPlaylistTarget: Track?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer(minLength: 0)

                ArtworkView(
                    data: coordinator.currentTrack?.artworkData,
                    url: coordinator.currentTrack?.artworkURL,
                    cornerRadius: 12
                )
                    .frame(maxWidth: 320)
                    .aspectRatio(1, contentMode: .fit)
                    .shadow(radius: 16, y: 8)

                trackInfo

                #if DEBUG
                if let note = coordinator.spotifyDiagnostic {
                    Text("Spotify: \(note)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                #endif

                scrubber
                transportControls

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 32)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                }

                // The queue is a primary control in a player, not an overflow
                // item, so it gets its own button rather than living in the menu.
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingQueue = true
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .disabled(coordinator.queue.isEmpty)
                    .accessibilityIdentifier("NowPlayingQueue")
                    .accessibilityLabel("Queue")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if let track = coordinator.currentTrack {
                            Button {
                                addToPlaylistTarget = track
                            } label: {
                                Label("Add to Playlist", systemImage: "text.badge.plus")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .disabled(coordinator.currentTrack == nil)
                    // SwiftUI labels a Menu "More" by default and puts the image
                    // identifier on the child, so name the control explicitly
                    // rather than depending on either.
                    .accessibilityIdentifier("NowPlayingMenu")
                    .accessibilityLabel("More options")
                }
            }
            .sheet(isPresented: $showingQueue) { QueueView() }
            .sheet(item: $addToPlaylistTarget) { track in
                AddToPlaylistView(track: track)
            }
        }
    }

    private var trackInfo: some View {
        VStack(spacing: 6) {
            Text(coordinator.currentTrack?.title ?? "Nothing Playing")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text(coordinator.currentTrack?.displaySubtitle ?? "")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let source = coordinator.currentTrack?.source {
                SourceBadge(source: source).padding(.top, 2)
            }
        }
    }

    private var scrubber: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { isScrubbing ? scrubPosition : coordinator.currentTime },
                    set: { scrubPosition = $0 }
                ),
                in: 0...max(coordinator.duration, 0.01)
            ) { editing in
                if editing {
                    scrubPosition = coordinator.currentTime
                    isScrubbing = true
                } else {
                    let target = scrubPosition
                    Task {
                        await coordinator.seek(to: target)
                        isScrubbing = false
                    }
                }
            }

            HStack {
                Text(Track.timeFormatter(isScrubbing ? scrubPosition : coordinator.currentTime))
                Spacer()
                Text(Track.timeFormatter(coordinator.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private var transportControls: some View {
        HStack(spacing: 44) {
            Button {
                Task { await coordinator.previous() }
            } label: {
                Image(systemName: "backward.fill").font(.title)
            }

            Button {
                Task { await coordinator.togglePlayPause() }
            } label: {
                Image(systemName: coordinator.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64))
            }

            Button {
                Task { await coordinator.next() }
            } label: {
                Image(systemName: "forward.fill").font(.title)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }
}
