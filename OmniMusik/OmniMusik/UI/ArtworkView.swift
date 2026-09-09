//
//  ArtworkView.swift
//  OmniMusik
//

import SwiftUI
import UIKit

/// Album art with a source-appropriate placeholder. Used at every size from the
/// mini player to the Now Playing hero, so sizing is the caller's decision.
///
/// **Prefer `init(track:)`.** Local files carry artwork as bytes and remote sources
/// hand back a URL, so passing only `data` silently renders a placeholder for every
/// streaming track — which is exactly what happened when Spotify was added and five
/// of six call sites were left on the data-only initialiser.
struct ArtworkView: View {
    let data: Data?

    /// Remote artwork, for sources that hand back a URL rather than bytes.
    /// Local data wins when both are present: it is already on disk.
    var url: URL?
    var cornerRadius: CGFloat = 6

    init(data: Data?, url: URL? = nil, cornerRadius: CGFloat = 6) {
        self.data = data
        self.url = url
        self.cornerRadius = cornerRadius
    }

    init(track: Track, cornerRadius: CGFloat = 6) {
        self.init(data: track.artworkData, url: track.artworkURL, cornerRadius: cornerRadius)
    }

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if let url {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(.quaternary)
                }
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
        case .appleMusic: .pink   // Apple Music keeps its own identity colour
        case .spotify: .green     // and so does Spotify
        }
    }
}
