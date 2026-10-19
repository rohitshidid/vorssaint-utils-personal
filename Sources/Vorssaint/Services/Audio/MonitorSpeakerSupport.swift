// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreAudio
import Foundation

/// Pure helpers for a monitor's own speakers. An HDMI or DisplayPort output
/// has no level macOS can set, so the level goes to the monitor over DDC/CI
/// instead, the way its own buttons would set it.
enum MonitorSpeakerSupport {
    /// VCP code for the speaker volume in the DDC/CI standard.
    static let volumeCode: UInt8 = 0x62
    /// The standard's scale. A write-only monitor never reports its own.
    static let maximum: UInt16 = 100
    /// Where the level starts before one was set here: a monitor that never
    /// answers reads cannot say where its buttons left it.
    static let defaultLevel = 0.5

    static func carriesDisplayAudio(transport: UInt32) -> Bool {
        transport == kAudioDeviceTransportTypeHDMI || transport == kAudioDeviceTransportTypeDisplayPort
    }

    /// The monitor behind a display's audio output. macOS names the output
    /// after the monitor's EDID: its vendor, then its product code with the
    /// two bytes swapped, so "10AC97A1-…" is Dell's product 0xA197.
    static func monitor(fromAudioUID uid: String) -> (vendor: UInt32, model: UInt32)? {
        let head = uid.prefix(9)
        guard head.count == 9, head.last == "-", head.dropLast().allSatisfy(\.isHexDigit),
              let vendor = UInt32(head.prefix(4), radix: 16), vendor != 0,
              let swapped = UInt32(head.dropFirst(4).prefix(4), radix: 16) else { return nil }
        return (vendor, (swapped & 0xFF) << 8 | swapped >> 8)
    }

    static func deviceValue(for level: Double) -> UInt16 {
        guard level.isFinite else { return 0 }
        return UInt16((min(max(level, 0), 1) * Double(maximum)).rounded())
    }

    /// What reaches the monitor: nothing while muted, since DDC's own mute
    /// control is optional and many monitors ignore it.
    static func audibleValue(level: Double, muted: Bool) -> UInt16 {
        muted ? 0 : deviceValue(for: level)
    }
}
