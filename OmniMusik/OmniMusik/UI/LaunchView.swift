//
//  LaunchView.swift
//  OmniMusik
//
//  What the app shows while it comes up.
//
//  Built from the same material as the rest of the product rather than as decoration:
//  the bars are a level meter, which is what the Studio's waveform and the
//  signal-chain layout are already made of, and they resolve left to right in the
//  order the audio graph runs. A generic spinner would have said nothing about what
//  this app is.
//
//  Kept to roughly a second. A launch animation is a cost paid on every single
//  launch, and the second time somebody sees it they want it gone.
//

import SwiftUI

struct LaunchView: View {
    var onFinished: () -> Void

    /// Honoured rather than ignored: motion sensitivity is exactly the case where a
    /// decorative animation does harm, and there is nothing here worth that.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var animating = false
    @State private var settled = false

    /// The exit is a stage of its own, not an absence.
    ///
    /// Removing the view and cross-fading the layer underneath reads as a cut: the
    /// bars and wordmark are simply gone one frame later. Letting them leave first --
    /// meter opening outward, wordmark lifting away -- turns the disappearance into
    /// the end of the animation rather than an interruption of it.
    @State private var leaving = false

    /// Heights the bars settle to, mirroring the five nodes of the playback graph:
    /// player, timePitch, EQ, reverb, mixer.
    private let restingHeights: [CGFloat] = [18, 34, 52, 34, 22]

    var body: some View {
        ZStack {
            Theme.studioBackground.ignoresSafeArea()

            VStack(spacing: 26) {
                meter

                HStack(spacing: 0) {
                    Text("Omni").foregroundStyle(Theme.studioPrimaryText)
                    Text("Musik").foregroundStyle(Theme.accentOnDark)
                }
                .font(.system(size: 30, weight: .semibold, design: .default))
                .opacity(leaving ? 0 : (settled ? 1 : 0))
                .offset(y: leaving ? -10 : (settled ? 0 : 8))
                .animation(.smooth(duration: 0.45), value: settled)
                .animation(.smooth(duration: 0.3), value: leaving)
            }
        }
        .opacity(leaving ? 0 : 1)
        .scaleEffect(leaving ? 1.04 : 1)
        .animation(.smooth(duration: 0.34), value: leaving)
        .task { await run() }
    }

    private var meter: some View {
        HStack(alignment: .center, spacing: 7) {
            ForEach(restingHeights.indices, id: \.self) { index in
                Capsule()
                    .fill(Theme.accentOnDark)
                    .frame(width: 7, height: height(at: index))
                    // Staggered so the bars read as a signal moving through the
                    // chain rather than five things pulsing at once.
                    .animation(
                        .smooth(duration: 0.5).delay(Double(index) * 0.07),
                        value: settled
                    )
                    .animation(
                        reduceMotion ? nil :
                            .easeInOut(duration: 0.42)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.09),
                        value: animating
                    )
                    // Opening outward on the way out, so the meter releases rather
                    // than snapping shut.
                    .scaleEffect(y: leaving ? 0.2 : 1, anchor: .center)
                    .opacity(leaving ? 0 : 1)
                    .animation(
                        .smooth(duration: 0.3).delay(Double(index) * 0.035),
                        value: leaving
                    )
            }
        }
        .frame(height: 64)
    }

    private func height(at index: Int) -> CGFloat {
        if settled || reduceMotion { return restingHeights[index] }
        return animating ? restingHeights[index] : 8
    }

    private func run() async {
        if reduceMotion {
            // No bouncing and no staged exit: appear, hold briefly, fade.
            settled = true
            try? await Task.sleep(for: .milliseconds(900))
            leaving = true
            try? await Task.sleep(for: .milliseconds(220))
            onFinished()
            return
        }

        // Deliberately longer than the app needs. The launch screen is the one
        // moment the product introduces itself, and at a second it was over before
        // the meter had finished a cycle -- read as a flash rather than as motion.
        animating = true
        try? await Task.sleep(for: .milliseconds(1250))

        settled = true
        try? await Task.sleep(for: .milliseconds(700))

        // Let the content leave before the layer does, so the handover to the app
        // underneath is a continuation rather than a cut.
        leaving = true
        try? await Task.sleep(for: .milliseconds(300))
        onFinished()
    }
}
