//
//  PlaybackNotifier.swift
//  OmniMusik
//
//  Telling somebody something while the phone is locked.
//
//  There is exactly one thing an app can do from the background when it needs the
//  person's attention, and this is it. When the queue reaches a track whose service
//  needs its own app woken — which iOS only permits from the foreground — a local
//  notification is the only way to say so. The alternative is playback stopping with
//  no explanation anywhere.
//
//  Permission is requested at the moment it is first needed rather than at launch. A
//  prompt on first run, before the app has done anything, is asking for trust that
//  has not been earned; a prompt attached to a thing that just happened explains
//  itself.
//

import Foundation
import UserNotifications

@MainActor
enum PlaybackNotifier {

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

    /// Posts the "come back and I will continue" notification.
    ///
    /// Delivered immediately, and replaces any previous one by using a fixed
    /// identifier: a queue that meets three streaming tracks in a row should not
    /// stack three notifications saying the same thing.
    static func notifyPlaybackNeedsForeground(track: Track) async {
        guard await ensureAuthorized() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Tap to keep playing"
        content.body = "\(track.title) is on \(track.source.displayName), which needs OmniMusik open to start."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "playback.needs-foreground",
            content: content,
            trigger: nil // Immediately.
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    static func clearPending() {
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: ["playback.needs-foreground"])
    }
}
