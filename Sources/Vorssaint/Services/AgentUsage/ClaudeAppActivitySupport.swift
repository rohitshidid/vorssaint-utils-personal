// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// What the Claude app's window says is working. Its chats and the Code
/// sessions it runs in the cloud write no log on this Mac, so the window is
/// the only place that tells: the sidebar marks each working session, and
/// the mode switch marks a mode working while another one is shown.
enum ClaudeAppActivitySupport {
    struct Reading: Equatable {
        /// Titles of the sidebar sessions marked working.
        var sessions: [String] = []
        /// Modes the switch marks working, with whether each one is shown.
        var modes: [(name: String, shown: Bool)] = []

        static func == (lhs: Reading, rhs: Reading) -> Bool {
            lhs.sessions == rhs.sessions && lhs.modes.map(\.name) == rhs.modes.map(\.name)
                && lhs.modes.map(\.shown) == rhs.modes.map(\.shown)
        }
    }

    /// A sidebar row's status reads "Running" while its session works and
    /// is empty otherwise.
    static func isWorking(status: String) -> Bool {
        let text = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return text == "running" || text == "working"
    }

    /// A mode switch reads "Claude, working" while a chat replies.
    static func workingMode(_ label: String) -> String? {
        guard let range = label.range(of: ", working", options: [.backwards, .caseInsensitive]),
              range.upperBound == label.endIndex else { return nil }
        let name = label[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    /// One entry per working thing: each marked session, and each working
    /// mode the sidebar does not already account for. The shown mode's
    /// sessions are its rows, so it counts on its own only without any.
    static func working(_ reading: Reading) -> [(id: String, title: String)] {
        var found = reading.sessions.map { (id: "claude-app:session:" + $0, title: $0) }
        for mode in reading.modes where !(mode.shown && !reading.sessions.isEmpty) {
            found.append((id: "claude-app:mode:" + mode.name, title: mode.name))
        }
        var seen = Set<String>()
        return found.filter { seen.insert($0.id).inserted }
    }

    /// Keeps each session's start while it goes on, so its clock runs on.
    static func sessions(_ working: [(id: String, title: String)], previous: [AgentLiveSession],
                         now: Date) -> [AgentLiveSession] {
        working.map { item in
            let started = previous.first { $0.id == item.id }?.started ?? now
            return AgentLiveSession(id: item.id, provider: .claude, started: started, lastActivity: now,
                                    model: "", project: item.title, tokens: AgentTokens(), cost: 0)
        }
    }

    /// Each of the app's sessions works beside the logged ones, with a mark
    /// and a clock of its own.
    static func merging(_ snapshot: AgentUsageSnapshot, app: [AgentLiveSession]) -> AgentUsageSnapshot {
        guard !app.isEmpty, snapshot.loaded else { return snapshot }
        var merged = snapshot
        merged.live = (snapshot.live + app).sorted { ($0.started, $0.id) < ($1.started, $1.id) }
        merged.seen.insert(.claude)
        return merged
    }
}
