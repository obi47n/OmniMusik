//
//  HandoffLog.swift
//  OmniMusik
//
//  Temporary on-device trace for the Spotify handoff. Debug builds only.
//
//  Reasoning about this path from the outside has been wrong repeatedly. This writes
//  a timestamped line at each step to Documents/handoff.log, which can be pulled off
//  a device with `devicectl device copy from`, so the next answer comes from what
//  actually happened rather than from what the code appears to do.
//

import Foundation

enum HandoffLog {
    static func note(_ message: String) {
        #if DEBUG
        let url = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("handoff.log")
        let stamp = ISO8601DateFormatter().string(from: .now)
        let line = "\(stamp) \(message)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
        #endif
    }
}
