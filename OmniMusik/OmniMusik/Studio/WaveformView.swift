//
//  WaveformView.swift
//  OmniMusik
//
//  The waveform, doubling as the trim editor.
//
//  Trim handles sit directly on the waveform rather than in a separate strip below
//  it. Trimming is an inherently visual judgement — you cut where the silence is,
//  and you can see where that is — so putting the handles anywhere other than on
//  the picture of the audio forces a translation step for no reason.
//
//  Drawn in a Canvas: a few hundred bars redrawn against a 200ms position poll is
//  more work than SwiftUI's view graph should be asked to do with individual shapes.
//

import SwiftUI

struct WaveformView: View {
    let peaks: [Float]

    /// Playback position as a fraction of the whole file, 0...1.
    let progress: Double

    /// Trim bounds as fractions of the whole file.
    @Binding var trimStart: Double
    @Binding var trimEnd: Double

    var isTrimmable = true
    var onScrub: ((Double) -> Void)?

    @State private var activeHandle: Handle?

    private enum Handle { case start, end }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack(alignment: .leading) {
                if peaks.isEmpty {
                    placeholder
                } else {
                    Canvas { context, size in
                        draw(in: &context, size: size)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 1, coordinateSpace: .local) { location in
                        onScrub?(min(max(0, location.x / width), 1))
                    }
                }

                if isTrimmable && !peaks.isEmpty {
                    handle(.start, at: trimStart * width, height: height, width: width)
                    handle(.end, at: trimEnd * width, height: height, width: width)
                }
            }
        }
    }

    // MARK: - Drawing

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let count = peaks.count
        guard count > 0 else { return }

        let slotWidth = size.width / CGFloat(count)
        let barWidth = max(1, slotWidth * 0.6)
        let midY = size.height / 2

        for (index, peak) in peaks.enumerated() {
            let fraction = Double(index) / Double(count)

            // A floor keeps silent passages visible as a thin line rather than
            // leaving gaps that read as rendering failure.
            let amplitude = max(CGFloat(peak), 0.02)
            let barHeight = amplitude * size.height * 0.92
            let x = CGFloat(index) * slotWidth + (slotWidth - barWidth) / 2

            let rect = CGRect(x: x, y: midY - barHeight / 2, width: barWidth, height: barHeight)
            let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)

            let outsideTrim = fraction < trimStart || fraction > trimEnd
            let played = fraction <= progress

            let color: Color = if outsideTrim {
                Theme.waveformInactive.opacity(0.25)
            } else if played {
                Theme.accentOnDark
            } else {
                Theme.waveformActive
            }

            context.fill(path, with: .color(color))
        }

        // Playhead
        if progress > 0, progress <= 1 {
            let x = size.width * progress
            let line = Path(CGRect(x: x - 1, y: 0, width: 2, height: size.height))
            context.fill(line, with: .color(.white))
        }
    }

    private var placeholder: some View {
        HStack(spacing: 3) {
            ForEach(0..<48, id: \.self) { index in
                Capsule()
                    .fill(Theme.studioCardRaised)
                    .frame(height: 6 + CGFloat((index * 37) % 28))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .redacted(reason: .placeholder)
    }

    // MARK: - Handles

    private func handle(_ which: Handle, at x: CGFloat, height: CGFloat, width: CGFloat) -> some View {
        let isActive = activeHandle == which

        return RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(Theme.accentOnDark)
            .frame(width: isActive ? 5 : 3, height: height)
            .overlay(
                Capsule()
                    .fill(Theme.accentOnDark)
                    .frame(width: 12, height: 28)
                    .overlay(
                        Capsule()
                            .fill(Theme.studioBackground.opacity(0.5))
                            .frame(width: 2, height: 12)
                    )
            )
            .offset(x: x - (isActive ? 2.5 : 1.5))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        activeHandle = which
                        let ratio = min(max(0, gesture.location.x / width), 1)
                        // Keep at least 2% of the file between the handles so the
                        // trimmed region can never collapse to nothing.
                        switch which {
                        case .start: trimStart = min(ratio, trimEnd - 0.02)
                        case .end:   trimEnd = max(ratio, trimStart + 0.02)
                        }
                    }
                    .onEnded { _ in activeHandle = nil }
            )
            .animation(.snappy(duration: 0.12), value: isActive)
    }
}
