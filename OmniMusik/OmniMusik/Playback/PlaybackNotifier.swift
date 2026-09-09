//
//  PlaybackNotifier.swift
//  OmniMusik
//
//  Telling somebody something while the phone is locked.
//
//  There is exactly one thing an app can do from the background when it needs the
//  person's attention, and this is it. When the queue reaches a track whose service
//  needs its own app woken — which iOS only permits from the foreground — the track
//  is skipped so the music keeps going, and this says which one and why.
//
//  Permission is requested when a streaming service is connected, not at launch and
//  not at the moment of need. A prompt on first run asks for trust the app has not
//  earned; asking at the moment of need does not work at all here, because that
//  moment is behind a lock screen and iOS will not present a permission prompt to a
//  backgrounded app. Connecting Spotify is both a foreground action and the point at
//  which this becomes relevant, so that is where the ask belongs.
//

import Foundation
import UserNotifications

@MainActor
enum PlaybackNotifier {

    /// Asks up front, at a moment when a prompt can actually be shown.
    static func requestIfNeededAfterConnecting() async {
        _ = await ensureAuthorized()
    }

    /// Asks to notify, returning whether it is allowed.
    ///
    /// Never re-prompts: once someone has answered, `requestAuthorization` returns
    /// the standing answer without showing anything.
    static func ensureAuthorized() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        @unknown default:
            return false
        }
    }

    /// Reports a track the queue passed over.
    ///
    /// Informational rather than a call to action: playback did not stop, so this
    /// explains a gap instead of asking for a rescue. No sound, because interrupting
    /// music to announce that the music is still playing would be absurd.
    ///
    /// A fixed identifier means a queue meeting three streaming tracks in a row
    /// replaces its own notification rather than stacking three.
    static func notifySkipped(track: Track) async {
        guard await ensureAuthorized() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Skipped \(track.title)"
        content.body = "\(track.source.displayName) needs OmniMusik open to start its app, so playback moved on."

        let request = UNNotificationRequest(
            identifier: "playback.skipped-needs-foreground",
            content: content,
            trigger: nil // Immediately.
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    static func clearPending() {
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: ["playback.skipped-needs-foreground"])
    }
}
