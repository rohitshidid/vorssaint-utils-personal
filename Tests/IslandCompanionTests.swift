// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A Claude session that waits on the person, and Murmur's dictation, as
/// the island reads them.
enum IslandCompanionTests {
    static func run(_ suite: TestSuite) {
        waitingRecords(suite)
        arrivals(suite)
        reveal(suite)
        dictation(suite)
        strings(suite)
    }

    private static func record(_ fields: [String: Any]) -> Data {
        var json: [String: Any] = ["pid": 4242, "sessionId": "a4144ecd-ad09", "cwd": "/Users/me/Projects/vorssaint",
                                   "name": "island-ab", "kind": "interactive", "entrypoint": "cli",
                                   "pidDomain": "darwin", "status": "waiting", "waitingFor": "permission prompt",
                                   "statusUpdatedAt": 1_792_427_091_746, "updatedAt": 1_792_427_091_746]
        for (key, value) in fields { json[key] = value }
        return try! JSONSerialization.data(withJSONObject: json)
    }

    private static func waitingRecords(_ suite: TestSuite) {
        let running: (Int32) -> Bool = { $0 == 4242 }
        let session = ClaudeAttentionSupport.waiting(record([:]), account: "Work", isRunning: running)
        suite.expect(session?.id == "a4144ecd-ad09" && session?.pid == 4242 && session?.reason == .permission
                        && session?.project == "vorssaint" && session?.name == "island-ab" && session?.account == "Work"
                        && session?.desktop == false,
                     "a waiting record names its session, account, project and reason")
        suite.expect(session?.since == Date(timeIntervalSince1970: 1_792_427_091.746),
                     "a record's millisecond status time is when it began to wait")
        for status in ["busy", "idle"] {
            suite.expect(ClaudeAttentionSupport.waiting(record(["status": status]), account: nil, isRunning: running) == nil,
                         "a \(status) session waits on no one")
        }
        suite.expect(ClaudeAttentionSupport.waiting(record([:]), account: nil, isRunning: { _ in false }) == nil,
                     "a record left behind by a killed process waits on no one")
        suite.expect(ClaudeAttentionSupport.waiting(record(["pidDomain": "linux"]), account: nil, isRunning: running) == nil,
                     "a session in a virtual machine names a process this Mac cannot see")
        suite.expect(ClaudeAttentionSupport.waiting(record(["entrypoint": "claude-desktop"]), account: nil,
                                                   isRunning: running)?.desktop == true,
                     "the Claude app's sessions are told apart from a terminal's")
        suite.expect(ClaudeAttentionSupport.waiting(Data(count: ClaudeAttentionSupport.recordLimit), account: nil,
                                                   isRunning: running) == nil,
                     "an oversized file is not read as a record")
        suite.expect(ClaudeAttentionSupport.waiting(Data("{".utf8), account: nil, isRunning: running) == nil,
                     "a record being written is skipped")
        let reasons: [(String?, ClaudeWaitingSession.Reason)] = [
            ("permission prompt", .permission), ("sandbox request", .permission), ("input needed", .input),
            ("dialog open", .dialog), ("something new", .other), (nil, .other)]
        suite.expect(reasons.allSatisfy { ClaudeAttentionSupport.reason($0.0) == $0.1 },
                     "Claude Code's reasons read as permission, question or waiting")
        suite.expect(ClaudeAttentionSupport.session(ofLog: "/Users/me/.claude-work/projects/-a/a4144ecd-ad09.jsonl")
                        == "a4144ecd-ad09",
                     "a log is matched to its session by name")
    }

    private static func arrivals(_ suite: TestSuite) {
        let now = Date(timeIntervalSince1970: 1_000_000)
        func session(_ id: String, since: TimeInterval) -> ClaudeWaitingSession {
            ClaudeWaitingSession(id: id, pid: 1, reason: .permission, since: now.addingTimeInterval(-since),
                                 name: "", project: "", account: nil, desktop: false)
        }
        let old = session("old", since: 600), fresh = session("fresh", since: 5)
        suite.expect(ClaudeAttentionSupport.arrivals(previous: nil, current: [old, fresh], now: now) == [fresh],
                     "a first look announces only what just began to wait")
        suite.expect(ClaudeAttentionSupport.arrivals(previous: [old], current: [old, fresh], now: now) == [fresh],
                     "a session still waiting is announced once")
        let again = session("old", since: 1)
        suite.expect(ClaudeAttentionSupport.arrivals(previous: [old], current: [again], now: now) == [again],
                     "a session that stopped on something new is announced again")
        suite.expect(ClaudeAttentionSupport.arrivals(previous: [old, fresh], current: [], now: now).isEmpty,
                     "an answered session announces nothing")
    }

    private static func reveal(_ suite: TestSuite) {
        let terminal = ClaudeAttentionSupport.revealScript(bundleID: "com.apple.Terminal", tty: "/dev/ttys004")
        suite.expect(terminal?.contains(#"if tty of t is "/dev/ttys004""#) == true
                        && terminal?.contains("set selected tab of w to t") == true,
                     "Terminal brings forward the tab writing to the session's terminal")
        suite.expect(ClaudeAttentionSupport.revealScript(bundleID: "com.googlecode.iterm2", tty: "/dev/ttys012")?
                        .contains("select s") == true,
                     "iTerm2 selects the session writing to that terminal")
        suite.expect(ClaudeAttentionSupport.revealScript(bundleID: "com.apple.Terminal", tty: #"/dev/ttys0" & quit"#) == nil,
                     "only a terminal device's own name is put in a script")
        suite.expect(ClaudeAttentionSupport.revealScript(bundleID: "com.example.editor", tty: "/dev/ttys004") == nil,
                     "an app that cannot name its tabs is only activated")
        let me = ClaudeAttentionSupport.process(getpid())
        suite.expect(me != nil && me!.parent > 0, "a running process names its parent")
    }

    private static func dictation(_ suite: TestSuite) {
        typealias Support = NotchDictationSupport
        suite.expect(Support.update(["phase": "listening", "level": 0.4, "locked": true])
                        == NotchDictationUpdate(phase: .listening(locked: true, command: false), level: 0.4),
                     "a recording carries its level and whether it is locked")
        suite.expect(Support.update(["phase": "listening", "level": 7])?.level == 1
                        && Support.update(["phase": "listening", "level": -1])?.level == 0,
                     "a level stays between silence and full")
        suite.expect(Support.update(["phase": "listening", "command": true])?.phase == .listening(locked: false, command: true),
                     "Command Mode is told apart")
        suite.expect(Support.update(["phase": "transcribing"])?.phase == .transcribing
                        && Support.update(["phase": "typed"])?.phase == .typed,
                     "the hold's end is followed through")
        suite.expect(Support.update(["phase": "idle"]) == NotchDictationUpdate(phase: nil, level: 0),
                     "rest ends the recording")
        let long = String(repeating: "x", count: 500)
        suite.expect(Support.update(["phase": "message", "text": long, "error": true])
                        == NotchDictationUpdate(phase: .message(String(long.prefix(Support.messageLimit)), isError: true), level: 0),
                     "a message is cut to a status line")
        suite.expect(Support.update(["phase": "message", "text": "  "]) == nil && Support.update(["phase": "dancing"]) == nil
                        && Support.update(nil) == nil,
                     "anything else is not a dictation update")
        suite.expect(NotchDictationPhase.listening(locked: false, command: false).isActive
                        && NotchDictationPhase.transcribing.isActive && !NotchDictationPhase.typed.isActive,
                     "a notice stays while Murmur records or works, not after")
        let defaults = UserDefaults(suiteName: "vorss.tests.island-companion")!
        defaults.removePersistentDomain(forName: "vorss.tests.island-companion")
        defer { defaults.removePersistentDomain(forName: "vorss.tests.island-companion") }
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        defaults.set(false, forKey: DefaultsKey.notchDictation)
        suite.expect(!NotchSupport.routes(.dictation, in: defaults), "the island leaves dictation to Murmur when turned off")
        suite.expect(NotchEvent.dictation.priority >= NotchEvent.agents.priority,
                     "a recording is not covered by an AI notice")
    }

    private static func strings(_ suite: TestSuite) {
        suite.expect(AppLanguage.allCases.allSatisfy { language in
            let attention = FeatureStrings.claudeAttention(language), dictation = FeatureStrings.dictation(language)
            let lines = [attention.alert, attention.alertHint, attention.needsYou("Work"), attention.permission,
                         attention.question, attention.waiting] + Mirror(reflecting: dictation).children.compactMap { $0.value as? String }
            return lines.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                && attention.needsYou("Work").contains("Work")
        }, "every language has every line for Claude's alert and Murmur's dictation")
    }
}
