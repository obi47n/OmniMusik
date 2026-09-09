//
//  NowPlayingCenter.swift
//  OmniMusik
//
//  Lock screen, Control Center, AirPods, and CarPlay transport.
//
//  A detail worth knowing: `MPNowPlayingInfoCenter` is not polled. You publish an
//  elapsed time and a playback rate, and the system extrapolates the position from
//  there. So this is updated on state transitions — play, pause, seek, track change —
//  and never on the position timer. Republishing five times a second would be pure
//  overhead and can make the lock screen scrubber stutter.
//

import MediaPlayer
import UIKit

@MainActor
final class NowPlayingCenter {

    struct Handlers {
        var play: () -> Void
        var pause: () -> Void
        var toggle: () -> Void
        var next: () -> Void
        var previous: () -> Void
        var seek: (TimeInterval) -> Void
    }

    static let shared = NowPlayingCenter()
    private init() {}

    private var didConfigure = false

    /// Registers remote command handlers. Safe to call more than once; only the
    /// first call installs targets.
    func configure(with handlers: Handlers) {
        guard !didConfigure else { return }
        didConfigure = true

        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { _ in
            handlers.play()
            return .success
        }
        center.pauseCommand.addTarget { _ in
            handlers.pause()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { _ in
            handlers.toggle()
            return .success
        }
        center.nextTrackCommand.addTarget { _ in
            handlers.next()
            return .success
        }
        center.previousTrackCommand.addTarget { _ in
            handlers.previous()
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            handlers.seek(event.positionTime)
            return .success
        }
    }

    /// Publishes current track state. Call on transitions, not on a timer.
    func update(
        track: Track?,
        isPlaying: Bool,
        elapsed: TimeInterval,
        duration: TimeInterval,
        rate: Float
    ) {
        guard let track else {
            clear()
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            // Rate is what drives the system's extrapolation. Zero freezes the
            // lock screen scrubber; the Studio's speed setting must be reflected
            // here or the displayed position drifts from what is audible.
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? rate : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
        ]

        if let album = track.album {
            info[MPMediaItemPropertyAlbumTitle] = album
        }

        if let data = track.artworkData, let image = UIImage(data: data) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }
}
