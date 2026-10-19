// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Foundation

/// Where Murmur's dictation is, as the island shows it.
enum NotchDictationPhase: Equatable {
    case listening(locked: Bool, command: Bool)
    case transcribing
    case typed
    /// A line Murmur shows after a hold, like a refusal or a rewrite done.
    case message(String, isError: Bool)

    var isListening: Bool {
        if case .listening = self { return true }
        return false
    }

    /// Still recording or working: the notice stays while Murmur says so.
    var isActive: Bool { isListening || self == .transcribing }
}

/// One word from Murmur: nil `phase` when it went back to rest.
struct NotchDictationUpdate: Equatable {
    var phase: NotchDictationPhase?
    var level: Double
}

/// Murmur and the island talk by distributed notification, which carries
/// only what is shown here: never a word of what was said.
enum NotchDictationSupport {
    /// Murmur's state, posted while it records and as each hold ends.
    static let stateName = Notification.Name("ai.pivotstudio.murmur.dictation")
    /// Murmur asks, as when it launches, whether the island shows dictation.
    static let helloName = Notification.Name("ai.pivotstudio.murmur.hello")
    /// The island's answer, and its word whenever that changes.
    static let presenceName = Notification.Name("com.vorssaint.island.dictation")
    static let murmurBundleID = "ai.pivotstudio.murmur"
    /// A message is Murmur's own short status line, never a transcript.
    static let messageLimit = 120

    static func update(_ info: [AnyHashable: Any]?) -> NotchDictationUpdate? {
        guard let info, let phase = info["phase"] as? String else { return nil }
        let level = min(1, max(0, (info["level"] as? NSNumber)?.doubleValue ?? 0))
        switch phase {
        case "listening":
            return NotchDictationUpdate(phase: .listening(locked: info["locked"] as? Bool ?? false,
                                                          command: info["command"] as? Bool ?? false),
                                        level: level.isFinite ? level : 0)
        case "transcribing": return NotchDictationUpdate(phase: .transcribing, level: 0)
        case "typed": return NotchDictationUpdate(phase: .typed, level: 0)
        case "message":
            let text = (info["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return NotchDictationUpdate(phase: .message(String(text.prefix(messageLimit)),
                                                        isError: info["error"] as? Bool ?? false), level: 0)
        case "idle": return NotchDictationUpdate(phase: nil, level: 0)
        default: return nil
        }
    }
}

/// Listens for Murmur while the island shows its dictation, and tells
/// Murmur so, which then leaves its own overlay away.
final class NotchDictationService: NSObject {
    static let shared = NotchDictationService()

    let updates = PassthroughSubject<NotchDictationUpdate, Never>()
    private var observing = false
    private var trusted = false
    private var checked = Date.distantPast
    private var center: DistributedNotificationCenter { .default() }

    /// Main thread.
    func synchronize() {
        let wanted = NotchSupport.routes(.dictation)
        guard wanted != observing else { return }
        observing = wanted
        if wanted {
            // Delivered while another app is in front, which is always.
            center.addObserver(self, selector: #selector(stateChanged(_:)), name: NotchDictationSupport.stateName,
                               object: nil, suspensionBehavior: .deliverImmediately)
            center.addObserver(self, selector: #selector(asked(_:)), name: NotchDictationSupport.helloName,
                               object: nil, suspensionBehavior: .deliverImmediately)
        } else {
            center.removeObserver(self)
            checked = .distantPast
        }
        announce()
    }

    /// Also on quit, so Murmur brings its overlay back at once.
    func stop() {
        guard observing else { return }
        observing = false
        center.removeObserver(self)
        announce()
    }

    private func announce() {
        center.postNotificationName(NotchDictationSupport.presenceName, object: nil,
                                    userInfo: ["shows": observing], deliverImmediately: true)
    }

    @objc private func asked(_ note: Notification) {
        announce()
    }

    @objc private func stateChanged(_ note: Notification) {
        guard let update = NotchDictationSupport.update(note.userInfo) else { return }
        // Only a running Murmur speaks for it, looked up every few seconds
        // rather than with each level.
        let now = Date()
        if now.timeIntervalSince(checked) > 2 {
            trusted = !NSRunningApplication.runningApplications(withBundleIdentifier: NotchDictationSupport.murmurBundleID).isEmpty
            checked = now
        }
        guard trusted else { return }
        updates.send(update)
    }
}
