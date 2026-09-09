//
//  ArtworkView.swift
//  OmniMusik
//

import SwiftUI
import UIKit

/// Album art with a source-appropriate placeholder. Used at every size from the
/// mini player to the Now Playing hero, so sizing is the caller's decision.
struct ArtworkView: View {
    let data: Data?
    var cornerRadius: CGFloat = 6

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "music.note")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Small capsule marking which service a track came from. Once the library mixes
/// sources this is the fastest way to tell them apart mid-scroll.
struct SourceBadge: View {
    let source: TrackSource

    var body: some View {
        Text(source.displayName)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }

    private var tint: Color {
        switch source {
        case .local: Theme.accent
        case .appleMusic: .pink  // Apple Music keeps its own identity colour
        }
    }
}
