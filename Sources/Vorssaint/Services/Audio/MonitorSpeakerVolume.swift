// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreAudio
import CoreGraphics
import Foundation
import OSLog

/// The level and mute of each monitor's speakers. The monitor is told, never
/// asked, so the last level set here stands for it, remembered per output.
/// Safe from any thread: the mixer calls in from its audio queue.
enum MonitorSpeakerVolume {
    /// Posted on the main thread when the monitors reachable over DDC change.
    static let availabilityChanged = Notification.Name("com.vorssaint.monitor-speakers.changed")

    private struct Monitor: Equatable {
        let id: CGDirectDisplayID
        let vendor: UInt32
        let model: UInt32
    }

    private static let lock = NSLock()
    private static var monitors: [Monitor] = []
    /// Narrates each decision, like the display pipeline it rides on.
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint", category: "audio")

    /// The displays the brightness pipeline reaches over DDC, after each of
    /// its scans; empty once it stops.
    static func updateMonitors(_ ids: [CGDirectDisplayID]) {
        let found = ids.sorted().map { Monitor(id: $0, vendor: CGDisplayVendorNumber($0), model: CGDisplayModelNumber($0)) }
        let changed = lock.withLock {
            defer { monitors = found }
            return monitors != found
        }
        guard changed else { return }
        log.log("monitor speakers reachable on displays \(found.map { String($0.id) }.joined(separator: ","), privacy: .public)")
        DispatchQueue.main.async { NotificationCenter.default.post(name: availabilityChanged, object: nil) }
    }

    /// Whether this output's level belongs to a monitor this Mac can reach.
    static func controls(_ device: AudioObjectID) -> Bool {
        target(device) != nil
    }

    static func level(for device: AudioObjectID) -> Double? {
        target(device).map { storedLevel($0.uid) }
    }

    static func isMuted(for device: AudioObjectID) -> Bool? {
        target(device).map { storedMuted($0.uid) }
    }

    @discardableResult
    static func setLevel(_ level: Double, for device: AudioObjectID) -> Bool {
        guard level.isFinite, let target = target(device) else {
            log.log("speaker level \(level) for output \(device): no monitor reachable")
            return false
        }
        let level = min(max(level, 0), 1)
        log.log("speaker level \(level) for display \(target.display)")
        store(level: level, for: target.uid)
        // Muted, the new level waits for the unmute to be heard.
        if storedMuted(target.uid) { return true }
        return send(MonitorSpeakerSupport.audibleValue(level: level, muted: false), to: target.display)
    }

    @discardableResult
    static func setMuted(_ muted: Bool, for device: AudioObjectID) -> Bool {
        guard let target = target(device) else { return false }
        let was = storedMuted(target.uid)
        store(muted: muted, for: target.uid)
        guard was != muted else { return true }
        return send(MonitorSpeakerSupport.audibleValue(level: storedLevel(target.uid), muted: muted),
                    to: target.display)
    }

    // MARK: - Private

    private static func target(_ device: AudioObjectID) -> (uid: String, display: CGDirectDisplayID)? {
        var transport: UInt32 = 0
        guard read(device, kAudioDevicePropertyTransportType, &transport),
              MonitorSpeakerSupport.carriesDisplayAudio(transport: transport) else { return nil }
        var uidRef: CFString = "" as CFString
        guard read(device, kAudioDevicePropertyDeviceUID, &uidRef),
              let monitor = MonitorSpeakerSupport.monitor(fromAudioUID: uidRef as String) else { return nil }
        let display = lock.withLock {
            monitors.first { $0.vendor == monitor.vendor && $0.model == monitor.model }?.id
        }
        return display.map { (uidRef as String, $0) }
    }

    /// Only reached once the brightness pipeline listed a monitor, so it
    /// already exists and this never creates it off the main thread.
    private static func send(_ value: UInt16, to display: CGDirectDisplayID) -> Bool {
        BrightnessService.shared.setSpeakerVolume(value, for: display)
    }

    private static func storedLevel(_ uid: String) -> Double {
        let levels = UserDefaults.standard.dictionary(forKey: DefaultsKey.monitorSpeakerLevels) as? [String: Double]
        return levels?[uid].map { min(max($0, 0), 1) } ?? MonitorSpeakerSupport.defaultLevel
    }

    private static func storedMuted(_ uid: String) -> Bool {
        UserDefaults.standard.stringArray(forKey: DefaultsKey.monitorSpeakerMuted)?.contains(uid) == true
    }

    private static func store(level: Double, for uid: String) {
        lock.withLock {
            var levels = UserDefaults.standard.dictionary(forKey: DefaultsKey.monitorSpeakerLevels) as? [String: Double] ?? [:]
            levels[uid] = level
            UserDefaults.standard.set(levels, forKey: DefaultsKey.monitorSpeakerLevels)
        }
    }

    private static func store(muted: Bool, for uid: String) {
        lock.withLock {
            var outputs = Set(UserDefaults.standard.stringArray(forKey: DefaultsKey.monitorSpeakerMuted) ?? [])
            if muted { outputs.insert(uid) } else { outputs.remove(uid) }
            UserDefaults.standard.set(outputs.sorted(), forKey: DefaultsKey.monitorSpeakerMuted)
        }
    }

    private static func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                _ value: inout T) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, UnsafeMutableRawPointer($0)) == noErr
        }
    }
}
