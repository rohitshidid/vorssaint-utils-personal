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

    private let queue = DispatchQueue(label: "com.vorssaint.claude-app-activity", qos: .utility)
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint", category: "agents")
    // Main thread.
    private var running = false
    private var generation = 0
    // Confined to `queue`.
    private var timer: DispatchSourceTimer?
    private var current: [AgentLiveSession] = []
    private var exposed: pid_t = 0

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
        var reading = ClaudeAppActivitySupport.Reading()
        var visited = 0
        for window in Self.elements(root, kAXWindowsAttribute) {
            walk(window, inSidebar: false, reading: &reading, visited: &visited)
        }
        return reading
    }

    /// Down to the sidebar, never into the conversation or its artifacts.
    private func walk(_ element: AXUIElement, inSidebar: Bool, reading: inout ClaudeAppActivitySupport.Reading,
                      visited: inout Int) {
        visited += 1
        guard visited < Self.nodeLimit else { return }
        let role = Self.string(element, kAXRoleAttribute)
        let subrole = Self.string(element, kAXSubroleAttribute)
        var inSidebar = inSidebar
        if subrole.hasPrefix("AXLandmark") {
            guard subrole == "AXLandmarkComplementary", Self.string(element, kAXDescriptionAttribute) == "Sidebar"
            else { return }
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
            return
        }
        for child in children { walk(child, inSidebar: inSidebar, reading: &reading, visited: &visited) }
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
