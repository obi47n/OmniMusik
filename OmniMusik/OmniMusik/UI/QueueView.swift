//
//  QueueView.swift
//  OmniMusik
//
//  What is playing and what follows.
//
//  Reads the coordinator's queue directly. The queue is not a playlist and is not
//  persisted: it is whatever context playback was started from, which may be the
//  library, a search result, or a playlist. Keeping those separate matters —
//  reordering the queue should not silently rewrite a saved playlist.
//

import SwiftUI

struct QueueView: View {
    @Environment(PlaybackCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if coordinator.queue.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing Queued", systemImage: "list.bullet")
                    } description: {
                        Text("Play something to build a queue.")
                    }
                } else {
                    list
                }
            }
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var list: some View {
        List {
            Section("Now Playing") {
                if let current = coordinator.currentTrack {
                    TrackRow(track: current, isCurrent: true, isPlaying: coordinator.isPlaying)
                }
            }

            if !upNext.isEmpty {
                Section("Up Next") {
                    ForEach(upNext) { track in
                        TrackRow(track: track, isCurrent: false, isPlaying: false)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    /// Everything after the current index. Deliberately not the whole queue:
    /// tracks already played are not "up next" and showing them would make the
    /// list grow downward as playback advances.
    private var upNext: [Track] {
        let next = coordinator.queueIndex + 1
        guard next < coordinator.queue.count else { return [] }
        return Array(coordinator.queue[next...])
    }
}
