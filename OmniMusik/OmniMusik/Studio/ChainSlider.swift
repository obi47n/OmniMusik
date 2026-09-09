//
//  ChainSlider.swift
//  OmniMusik
//
//  The Studio's parameter control.
//
//  Fills from a neutral origin rather than from the left edge. Effect parameters
//  are deviations from an unmodified signal — 1.0x speed, 0 semitones, flat EQ —
//  so what matters at a glance is direction and distance from neutral, not absolute
//  position on a track. A bipolar parameter fills left or right of center; a
//  unipolar one fills from its own resting point.
//
//  The result is that a glance down the chain shows exactly which parameters are
//  doing something and by how much, without reading a single number.
//

import SwiftUI

struct ChainSlider: View {
    let label: String
    @Binding var value: Float
    let range: ClosedRange<Float>

    /// The neutral value this parameter fills outward from.
    let origin: Float

    let display: String

    @State private var isDragging = false

    private var fraction: Double {
        let span = Double(range.upperBound - range.lowerBound)
        guard span > 0 else { return 0 }
        return (Double(value) - Double(range.lowerBound)) / span
    }

    private var originFraction: Double {
        let span = Double(range.upperBound - range.lowerBound)
        guard span > 0 else { return 0 }
        return (Double(origin) - Double(range.lowerBound)) / span
    }

    private var isNeutral: Bool { abs(value - origin) < 0.0001 }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(label)
                    .font(.studioLabel(13))
                    .foregroundStyle(Theme.studioSecondaryText)
                Spacer()
                Text(display)
                    .font(.studioValue(13))
                    .foregroundStyle(isNeutral ? Theme.studioTertiaryText : Theme.accentOnDark)
                    .contentTransition(.numericText())
            }

            GeometryReader { geometry in
                let width = geometry.size.width
                let thumbX = width * fraction
                let originX = width * originFraction

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.studioCardRaised)
                        .frame(height: 4)

                    // Fill spans origin → current, in whichever direction.
                    Capsule()
                        .fill(Theme.accentOnDark)
                        .frame(width: abs(thumbX - originX), height: 4)
                        .offset(x: min(thumbX, originX))

                    // Neutral tick, so the resting point is findable by eye.
                    Rectangle()
                        .fill(Theme.studioTertiaryText)
                        .frame(width: 1, height: 10)
                        .offset(x: originX - 0.5)

                    Circle()
                        .fill(Theme.accentOnDark)
                        .frame(width: isDragging ? 18 : 14, height: isDragging ? 18 : 14)
                        .shadow(color: Theme.accentOnDark.opacity(isDragging ? 0.5 : 0), radius: 6)
                        .offset(x: thumbX - (isDragging ? 9 : 7))
                }
                .frame(height: 20)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            isDragging = true
                            let ratio = min(max(0, gesture.location.x / width), 1)
                            let span = range.upperBound - range.lowerBound
                            value = range.lowerBound + Float(ratio) * span
                        }
                        .onEnded { _ in isDragging = false }
                )
            }
            .frame(height: 20)
        }
        .animation(.snappy(duration: 0.15), value: isDragging)
    }
}

/// A module in the signal chain.
///
/// The indicator dot is the fastest read on the screen: filled means this stage is
/// altering the signal, hollow means it's passing it through untouched.
struct ChainModule<Content: View>: View {
    let title: String
    let isEngaged: Bool
    var summary: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle()
                    .fill(isEngaged ? Theme.accentOnDark : Color.clear)
                    .overlay(
                        Circle().strokeBorder(
                            isEngaged ? Color.clear : Theme.studioTertiaryText,
                            lineWidth: 1.5
                        )
                    )
                    .frame(width: 8, height: 8)

                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .kerning(1.2)
                    .foregroundStyle(isEngaged ? Theme.studioPrimaryText : Theme.studioSecondaryText)

                Spacer()

                if let summary {
                    Text(summary)
                        .font(.studioValue(12))
                        .foregroundStyle(Theme.studioTertiaryText)
                }
            }

            content
        }
        .padding(16)
        .background(Theme.studioCard, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(isEngaged ? Theme.accentOnDark.opacity(0.35) : Color.clear, lineWidth: 1)
        )
    }
}

/// The wire between two modules. Carries the accent only when signal upstream is
/// actually being altered, so the chain visibly "lights up" from the top down.
struct ChainConnector: View {
    let isLive: Bool

    var body: some View {
        Rectangle()
            .fill(isLive ? Theme.accentOnDark.opacity(0.55) : Theme.studioCardRaised)
            .frame(width: 2, height: 14)
            .padding(.leading, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
