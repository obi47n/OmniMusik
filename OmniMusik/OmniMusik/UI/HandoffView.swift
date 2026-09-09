//
//  HandoffView.swift
//  OmniMusik
//
//  The moment before iOS hands the screen to Spotify.
//
//  Spotify has to be woken to play its own audio, and waking an app foregrounds it —
//  see DECISIONS.md. That switch cannot be avoided, so the goal here is narrower and
//  achievable: make it read as something OmniMusik is doing, rather than something
//  that happened to it.
//
//  Reuses the launch screen's level meter and slides it toward Spotify's green. The
//  same motif that opens the app carries you out of it, so the two moments belong to
//  one product rather than being separately decorated.
//

import SwiftUI

struct HandoffView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var moved = false

    private let heights: [CGFloat] = [16, 30, 46, 30, 20]

    var body: some View {
        ZStack {
            Theme.studioBackground.opacity(0.96).ignoresSafeArea()

            VStack(spacing: 22) {
                HStack(spacing: 14) {
                    meter
                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.studioSecondaryText)
                        .opacity(moved ? 1 : 0)
                    Circle()
                        .fill(Color.green)
                        .frame(width: 26, height: 26)
                        .scaleEffect(moved ? 1 : 0.5)
                        .opacity(moved ? 1 : 0)
                }

                VStack(spacing: 5) {
                    Text("Handing off to Spotify")
                        .font(.headline)
                        .foregroundStyle(Theme.studioPrimaryText)
                    Text("Spotify plays its own audio, so it has to be open.")
                        .font(.caption)
                        .foregroundStyle(Theme.studioSecondaryText)
                        .multilineTextAlignment(.center)
                }
                .opacity(moved ? 1 : 0)
            }
            .padding(32)
        }
        .task {
            guard !reduceMotion else { moved = true; return }
            withAnimation(.smooth(duration: 0.38)) { moved = true }
        }
    }

    private var meter: some View {
        HStack(alignment: .center, spacing: 5) {
            ForEach(heights.indices, id: \.self) { index in
                Capsule()
                    .fill(Theme.accentOnDark)
                    .frame(width: 5, height: heights[index])
                    // Bars collapse left to right as playback leaves this app.
                    .scaleEffect(y: moved ? 0.35 : 1, anchor: .center)
                    .opacity(moved ? 0.45 : 1)
                    .animation(
                        reduceMotion ? nil : .smooth(duration: 0.34).delay(Double(index) * 0.05),
                        value: moved
                    )
            }
        }
        .frame(height: 52)
    }
}
