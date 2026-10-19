// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The Claude app's chats and cloud sessions, as its window reports them.
enum ClaudeAppActivityTests {
    static func run(_ suite: TestSuite) {
        labels(suite)
        working(suite)
        clocks(suite)
    }

    private static func labels(_ suite: TestSuite) {
        suite.expect(ClaudeAppActivitySupport.isWorking(status: "Running")
                        && ClaudeAppActivitySupport.isWorking(status: " running\n")
                        && !ClaudeAppActivitySupport.isWorking(status: "")
                        && !ClaudeAppActivitySupport.isWorking(status: "Unread"),
                     "only a row whose status says it runs is working")
        suite.expect(ClaudeAppActivitySupport.workingMode("Claude, working") == "Claude"
                        && ClaudeAppActivitySupport.workingMode("Code") == nil
                        && ClaudeAppActivitySupport.workingMode(", working") == nil
                        && ClaudeAppActivitySupport.workingMode("Claude, working on it") == nil,
                     "a mode is working only when its switch ends by saying so")
    }

    private static func working(_ suite: TestSuite) {
        var reading = ClaudeAppActivitySupport.Reading(sessions: ["Resume Builder"], modes: [("Claude", false)])
        suite.expect(ClaudeAppActivitySupport.working(reading).map(\.title) == ["Resume Builder", "Claude"],
                     "a running cloud session and a chat replying in the other mode each count")
        reading = ClaudeAppActivitySupport.Reading(sessions: ["Resume Builder"], modes: [("Code", true)])
        suite.expect(ClaudeAppActivitySupport.working(reading).map(\.title) == ["Resume Builder"],
                     "the shown mode's rows already account for it")
        reading = ClaudeAppActivitySupport.Reading(sessions: [], modes: [("Code", true)])
        suite.expect(ClaudeAppActivitySupport.working(reading).map(\.title) == ["Code"],
                     "a shown mode working without a visible row still counts once")
        reading = ClaudeAppActivitySupport.Reading(sessions: ["Same", "Same"], modes: [])
        suite.expect(ClaudeAppActivitySupport.working(reading).count == 1,
                     "a title listed twice is one session")
        suite.expect(ClaudeAppActivitySupport.working(ClaudeAppActivitySupport.Reading()).isEmpty,
                     "an idle app adds nothing")
    }

    private static func clocks(_ suite: TestSuite) {
        let start = Date(timeIntervalSince1970: 2_000_000)
        let first = ClaudeAppActivitySupport.sessions([("a", "A")], previous: [], now: start)
        let later = ClaudeAppActivitySupport.sessions([("a", "A"), ("b", "B")], previous: first,
                                                      now: start.addingTimeInterval(90))
        suite.expect(first.first?.started == start && later.first?.started == start
                        && later.last?.started == start.addingTimeInterval(90),
                     "a session keeps its start while it works and a new one starts its own clock")
        suite.expect(later.allSatisfy { $0.provider == .claude && $0.cost == 0 } && later.last?.project == "B",
                     "the app's sessions are Claude's, named by their title, with no usage of their own")
        let merged = ClaudeAppActivitySupport.merging(AgentUsageSummary.snapshot(
            records: [], limits: [:], live: [AgentLiveSession(id: "log", provider: .claude, started: start.addingTimeInterval(30),
                                                              lastActivity: start, model: "", project: "", tokens: AgentTokens(), cost: 0)],
            plans: [:], providers: [.claude], now: start), app: first)
        suite.expect(merged.live.map(\.id) == ["a", "log"],
                     "the app's sessions join the logged ones, the longest-running first")
    }
}
