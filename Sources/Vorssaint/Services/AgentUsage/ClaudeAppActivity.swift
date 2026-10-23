// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Foundation
import OSLog

/// Reads the Claude app's sidebar through Accessibility, read-only and only
/// while the app runs, Claude is among the island's agents and the island
/// reads agents at all. Nothing it reads leaves the Mac.
final class ClaudeAppActivityService {
    static let shared = ClaudeAppActivityService()

    static let interval: TimeInterval = 2
    /// A sidebar is a couple of hundred elements; more means the walk lost its way.
    private static let nodeLimit = 1500
    /// The sidebar's rows sit about twenty levels down. A tree deeper than
    /// this, as one that loops back on itself while the Mac is locked, is
    /// not the window being read.
    private static let depthLimit = 48

    private let queue = DispatchQueue(label: "com.vorssaint.claude-app-activity", qos: .utility)
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint", category: "agents")
    // Main thread.
    private var running = false
    private var generation = 0
    // Confined to `queue`.
    private var timer: DispatchSourceTimer?
    private var current: [AgentLiveSession] = []
    private var exposed: pid_t = 0
    /// Set from the system's lock notifications, read on `queue`.
    private let lockState = NSLock()
    private var screenLocked = false

    private init() {
        let center = DistributedNotificationCenter.default()
        for (name, locked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            center.addObserver(forName: Notification.Name(name), object: nil, queue: nil) { [weak self] _ in
                guard let self else { return }
                self.lockState.withLock { self.screenLocked = locked }
            }
        }
    }

    /// Main thread.
    func synchronize(enabled: Bool) {
        let trusted = AXIsProcessTrusted()
        let wanted = enabled && trusted
        guard wanted != running else { return }
        Self.log.log("claude app watch \(wanted ? "on" : "off", privacy: .public) (enabled \(enabled), trusted \(trusted))")
        running = wanted
        generation += 1
        let generation = self.generation
        queue.async { [self] in
            timer?.cancel()
            timer = nil
            current = []
            guard wanted else { return }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: Self.interval, leeway: .milliseconds(500))
            timer.setEventHandler { [weak self] in self?.poll(generation: generation) }
            self.timer = timer
            timer.resume()
        }
        if !wanted { AgentUsageService.shared.setAppSessions([]) }
    }

    /// Runs on `queue`.
    private func poll(generation: Int) {
        // Locked, or another user in front: the window is not what it shows,
        // and nothing working there is news until the person is back.
        guard SessionActivity.shared.isActive, !lockState.withLock({ screenLocked }) else { return }
        let reading = NSRunningApplication.runningApplications(withBundleIdentifier: AgentClaudeAppUsage.bundleIdentifier)
            .first.map(read) ?? ClaudeAppActivitySupport.Reading()
        let next = ClaudeAppActivitySupport.sessions(ClaudeAppActivitySupport.working(reading),
                                                     previous: current, now: Date())
        // Only a change of what works is news; the clock runs on its own.
        guard next.map(\.id) != current.map(\.id) else { return }
        Self.log.log("claude app working: \(reading.sessions.count) sessions, modes \(reading.modes.map(\.name).joined(separator: ","), privacy: .public)")
        current = next
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, self.generation == generation else { return }
            AgentUsageService.shared.setAppSessions(next)
        }
    }

    private func read(_ app: NSRunningApplication) -> ClaudeAppActivitySupport.Reading {
        let root = AXUIElementCreateApplication(app.processIdentifier)
        // Electron answers a long list slowly; a short wait reads it as empty.
        AXUIElementSetMessagingTimeout(root, 3)
        // An Electron app builds its web content's tree only once asked to.
        if exposed != app.processIdentifier {
            AXUIElementSetAttributeValue(root, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            exposed = app.processIdentifier
        }
        return walk(Self.elements(root, kAXWindowsAttribute))
    }

    /// Down to the sidebar, never into the conversation or its artifacts.
    /// Iterative, bounded in depth and size, and never through an element
    /// twice, so no shape the window's tree takes can exhaust the stack.
    private func walk(_ windows: [AXUIElement]) -> ClaudeAppActivitySupport.Reading {
        var reading = ClaudeAppActivitySupport.Reading()
        var pending = windows.reversed().map { (element: $0, inSidebar: false, depth: 0) }
        var seen = Set<VisitedElement>()
        while let (element, parentInSidebar, depth) = pending.popLast() {
            guard seen.count < Self.nodeLimit, depth < Self.depthLimit,
                  seen.insert(VisitedElement(element)).inserted else { continue }
            let role = Self.string(element, kAXRoleAttribute)
            let subrole = Self.string(element, kAXSubroleAttribute)
            var inSidebar = parentInSidebar
            if subrole.hasPrefix("AXLandmark") {
                guard subrole == "AXLandmarkComplementary", Self.string(element, kAXDescriptionAttribute) == "Sidebar"
                else { continue }
                inSidebar = true
            }
            if inSidebar, role == kAXRadioButtonRole as String,
               let mode = ClaudeAppActivitySupport.workingMode(Self.string(element, kAXDescriptionAttribute)) {
                let shown = (Self.value(element, kAXValueAttribute) as? NSNumber)?.boolValue ?? false
                reading.modes.append((mode, shown))
            }
            let children = Self.elements(element, kAXChildrenAttribute)
            if inSidebar, let status = children.first(where: { Self.string($0, kAXSubroleAttribute) == "AXApplicationStatus" }) {
                // The row's title sits beside its status.
                let text = Self.elements(status, kAXChildrenAttribute).map { Self.string($0, kAXValueAttribute) }.joined()
                if ClaudeAppActivitySupport.isWorking(status: text),
                   let title = children.lazy.map({ Self.string($0, kAXValueAttribute) }).first(where: { !$0.isEmpty }) {
                    reading.sessions.append(title)
                }
                continue
            }
            // Reversed, so the first child is read first, in the window's order.
            pending.append(contentsOf: children.reversed().map { ($0, inSidebar, depth + 1) })
        }
        return reading
    }

    /// An element as Accessibility identifies it: the same element read
    /// twice compares equal, though each read hands back a new reference.
    private struct VisitedElement: Hashable {
        let element: AXUIElement
        init(_ element: AXUIElement) { self.element = element }
        static func == (lhs: Self, rhs: Self) -> Bool { CFEqual(lhs.element, rhs.element) }
        func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String {
        value(element, attribute) as? String ?? ""
    }

    private static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        value(element, attribute) as? [AXUIElement] ?? []
    }
}
