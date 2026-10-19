// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Darwin
import Foundation

/// A Claude Code session stopped on something only the person can answer:
/// a permission prompt, a question or a dialog. Claude Code says so itself,
/// in the `sessions/<pid>.json` record it keeps beside its logs while it runs.
struct ClaudeWaitingSession: Equatable, Identifiable {
    enum Reason: Equatable {
        case permission, input, dialog, other
    }

    /// The session id, which names its log.
    let id: String
    let pid: Int32
    let reason: Reason
    /// When it began to wait, as the record says.
    let since: Date
    /// The session's own name, as Claude Code shows it.
    let name: String
    let project: String
    /// Named as its limits card is; nil for the usual folder while no card claims it.
    let account: String?
    /// Run by the Claude app rather than a terminal.
    let desktop: Bool
}

enum ClaudeAttentionSupport {
    /// A record is a few hundred bytes; anything bigger is not one.
    static let recordLimit = 1 << 16
    /// A session already waiting when watching starts, as after the Mac
    /// wakes, is news only when it began this recently.
    static let lateArrival: TimeInterval = 60

    /// Claude Code's `waitingFor`: any approval dialog is a "permission
    /// prompt", a question or an MCP form needs input, others are dialogs.
    static func reason(_ text: String?) -> ClaudeWaitingSession.Reason {
        switch text {
        case "permission prompt", "sandbox request", "worker request": return .permission
        case "input needed", "goal proposal": return .input
        case "dialog open": return .dialog
        default: return .other
        }
    }

    /// The session a record describes, when it waits on the person and its
    /// process runs on this Mac. Nothing else in the record is kept.
    static func waiting(_ data: Data, account: String?,
                        isRunning: (Int32) -> Bool = AgentSessionRegistry.isRunning) -> ClaudeWaitingSession? {
        guard data.count < recordLimit,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              json["status"] as? String == "waiting",
              let pid = json["pid"] as? Int, let session = json["sessionId"] as? String, !session.isEmpty else { return nil }
        // A session in a container or virtual machine names a process this Mac cannot see.
        if let domain = json["pidDomain"] as? String, domain != "darwin" { return nil }
        let process = Int32(clamping: pid)
        guard isRunning(process) else { return nil }
        let cwd = json["cwd"] as? String ?? ""
        return ClaudeWaitingSession(
            id: AgentLogParser.native(session), pid: process, reason: reason(json["waitingFor"] as? String),
            since: AgentLogParser.seconds(json["statusUpdatedAt"]) ?? AgentLogParser.seconds(json["updatedAt"]) ?? .distantPast,
            name: AgentLogParser.native(json["name"] as? String ?? ""),
            project: cwd.isEmpty ? "" : AgentLogParser.projectName(cwd),
            account: account, desktop: json["entrypoint"] as? String == "claude-desktop")
    }

    /// Sessions that began to wait since `previous`: new ones, and ones that
    /// stopped on something else. On a first look, only recent ones.
    static func arrivals(previous: [ClaudeWaitingSession]?, current: [ClaudeWaitingSession],
                         now: Date) -> [ClaudeWaitingSession] {
        guard let previous else { return current.filter { now.timeIntervalSince($0.since) < lateArrival } }
        return current.filter { session in !previous.contains { $0.id == session.id && $0.since == session.since } }
    }

    /// A Claude log is named by its session.
    static func session(ofLog path: String) -> String {
        ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    /// One step up the process tree, and the terminal `pid` writes to.
    static func process(_ pid: pid_t) -> (parent: pid_t, tty: String?)? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let device = info.kp_eproc.e_tdev
        var tty: String?
        if device != -1, let name = devname(device, S_IFCHR) {
            let text = String(cString: name)
            if text != "??" { tty = "/dev/" + text }
        }
        return (info.kp_eproc.e_ppid, tty)
    }

    /// Brings the tab running on `tty` forward, in the terminals that can
    /// say which tab that is; nil for any other app, which is only activated.
    static func revealScript(bundleID: String, tty: String) -> String? {
        // A terminal device's own name, so nothing needs escaping.
        guard tty.range(of: #"^/dev/tty[a-z]{0,2}[0-9a-f]+$"#, options: .regularExpression) != nil else { return nil }
        switch bundleID {
        case "com.apple.Terminal":
            return """
            tell application id "com.apple.Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(tty)" then
                            set miniaturized of w to false
                            set selected tab of w to t
                            set index of w to 1
                            activate
                            return "found"
                        end if
                    end repeat
                end repeat
            end tell
            """
        case "com.googlecode.iterm2":
            return """
            tell application id "com.googlecode.iterm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(tty)" then
                                select w
                                select t
                                select s
                                activate
                                return "found"
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            """
        default:
            return nil
        }
    }
}

/// Watches the records Claude Code keeps for its running sessions, read-only,
/// for one that waits on the person. Only while Claude's alerts are on and
/// the island is in view.
final class ClaudeAttentionService: ObservableObject {
    static let shared = ClaudeAttentionService()

    @Published private(set) var waiting: [ClaudeWaitingSession] = []
    /// A session that just began to wait.
    let arrived = PassthroughSubject<ClaudeWaitingSession, Never>()

    /// A record changes the moment a prompt opens; a second is soon enough to say so.
    static let interval: TimeInterval = 1
    /// Folders are found again this often, as when a new account is used.
    private static let folderInterval: TimeInterval = 30

    private let queue = DispatchQueue(label: "com.vorssaint.claude-attention", qos: .utility)
    private let defaults: UserDefaults
    private let home = FileManager.default.homeDirectoryForCurrentUser
    // Main thread.
    private var generation = 0
    private var running = false

    // Confined to `queue`.
    private var timer: DispatchSourceTimer?
    private var names: [ClaudeAccountProfile.LogName] = []
    private var folders: [URL] = []
    private var foldersFound = Date.distantPast
    private var last: [ClaudeWaitingSession]?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool {
        NotchAgentSupport.isEnabled(in: defaults) && NotchAgentSupport.providers(in: defaults).contains(.claude)
            && defaults.bool(forKey: DefaultsKey.notchAgentsAttentionAlert)
    }

    /// Follows the preferences and the account names. Main thread.
    func synchronize() {
        guard isEnabled else { return pause() }
        let names = ClaudeProfileLimitsService.shared.logNames
        let generation = self.generation
        queue.async { [self] in
            if names != self.names { (self.names, foldersFound) = (names, .distantPast) }
            guard timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: Self.interval, leeway: .milliseconds(250))
            timer.setEventHandler { [weak self] in self?.poll(generation: generation) }
            self.timer = timer
            timer.resume()
        }
        running = true
    }

    /// The island is away or the alert is off: nothing is read, and what
    /// was waiting is forgotten, so coming back announces only what is new.
    func pause() {
        guard running else { return }
        running = false
        generation += 1
        if !waiting.isEmpty { waiting = [] }
        queue.async { [self] in
            timer?.cancel()
            timer = nil
            last = nil
        }
    }

    /// Runs on `queue`.
    private func poll(generation: Int) {
        let now = Date()
        if now.timeIntervalSince(foldersFound) >= Self.folderInterval {
            folders = AgentLogRoot.all(home: home).filter { $0.provider == .claude }
                .map { $0.url.deletingLastPathComponent().appending(path: "sessions", directoryHint: .isDirectory) }
            foldersFound = now
        }
        var current: [ClaudeWaitingSession] = []
        for folder in folders {
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { continue }
            let account = ClaudeAccountProfile.accountName(forLog: folder.path + "/", names: names, home: home)
            for file in files where file.hasSuffix(".json") && Int32(file.dropLast(5)) != nil {
                guard let data = try? Data(contentsOf: folder.appending(path: file)),
                      let session = ClaudeAttentionSupport.waiting(data, account: account),
                      !current.contains(where: { $0.id == session.id }) else { continue }
                current.append(session)
            }
        }
        current.sort { ($0.since, $0.id) < ($1.since, $1.id) }
        let arrivals = ClaudeAttentionSupport.arrivals(previous: last, current: current, now: now)
        guard current != last else { return }
        last = current
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, self.generation == generation else { return }
            if self.waiting != current { self.waiting = current }
            arrivals.forEach(self.arrived.send)
        }
    }

    /// Brings the session's terminal tab forward, or the app it runs in.
    func reveal(_ session: ClaudeWaitingSession) {
        DispatchQueue.global(qos: .userInitiated).async {
            var pid = session.pid
            var tty: String?
            var host: NSRunningApplication?
            // A shell or two, then the terminal, which is an app of its own.
            for _ in 0..<32 {
                if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular {
                    host = app
                    break
                }
                guard let step = ClaudeAttentionSupport.process(pid), step.parent > 1 else { break }
                if tty == nil { tty = step.tty }
                pid = step.parent
            }
            guard let host else { return }
            if let bundle = host.bundleIdentifier, let tty,
               let script = ClaudeAttentionSupport.revealScript(bundleID: bundle, tty: tty),
               AppleScriptRunner.run(script).output == "found" { return }
            DispatchQueue.main.async { host.activate() }
        }
    }
}
