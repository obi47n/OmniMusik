//
//  HandoffView.swift
//  OmniMusik
//
//  The moment before iOS hands the screen to Spotify.
//
//  Spotify has to be woken to play its own audio, and waking an app foregrounds it —
//  see DECISIONS.md. That switch cannot be avoided, so the goal here is narrower and
//  achievable: make it read as something OmniMusik is doing rather than something
//  that happened to it.
//
//  Two tiles and an arrow, because that is the shape of the actual event: playback is
//  moving from this app to that one. The left tile carries OmniMusik's own mark — the
//  level meter used on the launch screen and in the Studio — so the two moments
//  belong to one product.
//
//  The right tile is deliberately *not* a reproduction of Spotify's logo. Redrawing
//  another company's mark by hand is worse than not showing it: their brand
//  guidelines require official assets, and an approximation is both a trademark
//  problem and visibly wrong to anyone who knows it. Their green plus a neutral glyph
//  communicates the destination without pretending to be their asset.
//

import SwiftUI

struct HandoffView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var moved = false

    private let tile: CGFloat = 64

    var body: some View {
        ZStack {
            Theme.studioBackground.opacity(0.96).ignoresSafeArea()

            VStack(spacing: 24) {
                HStack(spacing: 18) {
                    omniMusikTile
                    arrow
                    destinationTile
                }

                Text("Handing off to Spotify")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.studioSecondaryText)
                    .opacity(moved ? 1 : 0)
                    .animation(.smooth(duration: 0.3).delay(0.1), value: moved)
            }
            .padding(32)
        }
        .task {
            guard !reduceMotion else { moved = true; return }
            withAnimation(.smooth(duration: 0.34)) { moved = true }
        }
    }

    /// OmniMusik: the level meter, at tile scale.
    private var omniMusikTile: some View {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
            .fill(Theme.accentOnDark)
            .frame(width: tile, height: tile)
            .overlay {
                HStack(alignment: .center, spacing: 3.5) {
                    ForEach([12, 22, 30, 20].indices, id: \.self) { index in
                        Capsule()
                            .fill(Color.white.opacity(0.95))
                            .frame(width: 4, height: [12, 22, 30, 20][index])
                    }
                }
            }
            // Recedes as playback leaves: still present, no longer the subject.
            .scaleEffect(moved ? 0.88 : 1)
            .opacity(moved ? 0.55 : 1)
            .animation(reduceMotion ? nil : .smooth(duration: 0.34), value: moved)
    }

    private var arrow: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Theme.studioSecondaryText)
            .opacity(moved ? 1 : 0)
            .offset(x: moved ? 0 : -10)
            .animation(reduceMotion ? nil : .smooth(duration: 0.3).delay(0.06), value: moved)
    }

    /// Destination: Spotify's green with a neutral glyph, not their logo.
    private var destinationTile: some View {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
            .fill(Color.green)
            .frame(width: tile, height: tile)
            .overlay {
                Image(systemName: "waveform")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .scaleEffect(moved ? 1 : 0.66)
            .opacity(moved ? 1 : 0)
            .animation(reduceMotion ? nil : .smooth(duration: 0.36).delay(0.1), value: moved)
    }
}
