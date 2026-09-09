//
//  SyncEpochStore.swift
//  OmniMusik
//
//  Remembers which server's history this device's sync versions came from.
//
//  `UserDefaults` rather than SwiftData: this is one string describing the device's
//  relationship to a service, not domain data. It never syncs, never appears in the
//  UI, and giving it a model would put it in the same store it exists to protect.
//

import Foundation

struct SyncEpochStore {

    private static let key = "sync.epoch"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var stored: String? {
        defaults.string(forKey: Self.key)
    }

    func record(_ epoch: String) {
        defaults.set(epoch, forKey: Self.key)
    }
}
