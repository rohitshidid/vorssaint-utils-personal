// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreAudio
import Foundation

/// A monitor's own speakers, which take their level over DDC/CI.
enum MonitorSpeakerTests {
    static func run(_ suite: TestSuite) {
        let dell = MonitorSpeakerSupport.monitor(fromAudioUID: "10AC97A1-0000-0000-1421-0103803C2278")
        suite.expect(dell?.vendor == 0x10AC && dell?.model == 0xA197,
                     "a display output's UID names its monitor: the vendor, then the product with its bytes swapped")
        for uid in ["BuiltInSpeakerDevice", "10AC97A1", "0000ABCD-0000", "10AC97ZZ-0000", "F43D3A5E41BB-4537"] {
            suite.expect(MonitorSpeakerSupport.monitor(fromAudioUID: uid) == nil,
                         "\(uid) names no monitor")
        }
        suite.expect(MonitorSpeakerSupport.carriesDisplayAudio(transport: kAudioDeviceTransportTypeHDMI)
                        && MonitorSpeakerSupport.carriesDisplayAudio(transport: kAudioDeviceTransportTypeDisplayPort)
                        && !MonitorSpeakerSupport.carriesDisplayAudio(transport: kAudioDeviceTransportTypeBuiltIn)
                        && !MonitorSpeakerSupport.carriesDisplayAudio(transport: kAudioDeviceTransportTypeUSB),
                     "only a display's own audio goes to its monitor")
        suite.expect(MonitorSpeakerSupport.deviceValue(for: 0.5) == 50 && MonitorSpeakerSupport.deviceValue(for: 1.4) == 100
                        && MonitorSpeakerSupport.deviceValue(for: -1) == 0 && MonitorSpeakerSupport.deviceValue(for: .nan) == 0,
                     "the level maps onto the standard's 0-100 scale and never past it")
        suite.expect(MonitorSpeakerSupport.audibleValue(level: 0.6, muted: true) == 0
                        && MonitorSpeakerSupport.audibleValue(level: 0.6, muted: false) == 60,
                     "muting sends silence, since many monitors ignore DDC's own mute")
        suite.expect(MonitorSpeakerSupport.volumeCode == 0x62
                        && BrightnessSupport.writePacket(code: MonitorSpeakerSupport.volumeCode, value: 60)
                            == [0x84, 0x03, 0x62, 0x00, 0x3C, 0x84 ^ 0x03 ^ 0x62 ^ 0x00 ^ 0x3C ^ 0x6E ^ 0x51],
                     "the volume write is a Set VCP Feature for speaker volume")
    }
}
