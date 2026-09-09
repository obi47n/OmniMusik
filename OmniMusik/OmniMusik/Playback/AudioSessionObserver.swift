//
//  AudioSessionObserver.swift
//  OmniMusik
//
//  Audio session interruptions and route changes.
//
//  Two things every music app must handle and the ones users notice instantly when
//  they're missing:
//
//  Interruptions — a phone call or Siri takes the session away. On the way out we
//  pause; on the way back iOS tells us whether resuming is appropriate, and that
//  flag must be respected rather than blindly resuming (the user may have started
//  something else in the meantime).
//
//  Route changes — headphones unplugged. iOS does not stop playback for you, so
//  without this the track continues out of the speaker at whatever volume was set.
//  That is the single most embarrassing bug a music app can ship.
//

import AVFoundation
import Foundation

@MainActor
final class AudioSessionObserver {

    var onInterruptionBegan: (() -> Void)?
    var onInterruptionEnded: ((_ shouldResume: Bool) -> Void)?
    var onOutputDisconnected: (() -> Void)?

    private var observers: [NSObjectProtocol] = []

    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default

        observers.append(
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor [weak self] in
                    self?.handleInterruption(notification)
                }
            }
        )

        observers.append(
            center.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor [weak self] in
                    self?.handleRouteChange(notification)
                }
            }
        )
    }

    private func handleInterruption(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw)
        else { return }

        switch type {
        case .began:
            onInterruptionBegan?()
        case .ended:
            let optionsRaw = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
            onInterruptionEnded?(options.contains(.shouldResume))
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw)
        else { return }

        // .oldDeviceUnavailable is the headphones-yanked case specifically. Other
        // reasons (a new device becoming available, category changes) should not
        // stop playback.
        if reason == .oldDeviceUnavailable {
            onOutputDisconnected?()
        }
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
