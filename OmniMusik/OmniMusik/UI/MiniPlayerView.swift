//
//  MiniPlayerView.swift
//  OmniMusik
//

import SwiftUI

/// Compact transport docked above the tab bar whenever something is loaded.
struct MiniPlayerView: View {
    @Environment(PlaybackCoordinator.self) private var coordinator
    let onTap: () -> Void

    var body: some View {
        if let track = coordinator.currentTrack {
            VStack(spacing: 0) {
                progressHairline(for: track)

                HStack(spacing: 12) {
                    // A real Button rather than an onTapGesture on the enclosing
                    // stack. The gesture worked for touch but was invisible to
                    // VoiceOver -- a plain stack is not an accessibility element,
                    // so "expand to Now Playing" could not be activated at all.
                    // The Spacer lives inside so the whole left region stays
                    // tappable, which is what the gesture used to give.
                    Button(action: onTap) {
                        HStack(spacing: 12) {
                            ArtworkView(track: track, cornerRadius: 4)
                                .frame(width: 36, height: 36)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(track.title).font(.footnote.weight(.medium)).lineLimit(1)
                                Text(track.artist).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }

                            Spacer(minLength: 4)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("MiniPlayerExpand")
                    .accessibilityLabel("\(track.title), \(track.artist)")
                    .accessibilityHint("Opens Now Playing")

                    Button {
                        Task { await coordinator.togglePlayPause() }
                    } label: {
                        Image(systemName: coordinator.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    // The UI test's handle for "the player is docked". Note this
                    // must stay the only identifier in the mini player subtree:
                    // SwiftUI propagates accessibilityIdentifier to descendants,
                    // so one on the enclosing stack silently overwrites this.
                    .accessibilityIdentifier("MiniPlayerPlayPause")

                    Button {
                        Task { await coordinator.next() }
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.title3)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(.regularMaterial)
        }
    }

    /// Two-point progress line. Communicates position without spending the vertical
    /// space a real scrubber would need at this size.
    private func progressHairline(for track: Track) -> some View {
        GeometryReader { geometry in
            let total = max(coordinator.duration, 0.01)
            let fraction = min(max(coordinator.currentTime / total, 0), 1)
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: geometry.size.width * fraction)
        }
        .frame(height: 2)
        .background(.quaternary)
    }
}
