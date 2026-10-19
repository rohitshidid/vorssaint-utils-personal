// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

struct ClaudeProfileLimitsState: Equatable, Identifiable {
    var profile: ClaudeAccountProfile
    var limits: AgentLimits?
    var plan: String?
    /// Waiting for its turn or being checked.
    var checking = false
    var failure: ClaudeAccountUsageError?
    /// When the last check began; nil until one has.
    var attempted: Date?
    var id: String { profile.id }

    /// An expired window is unknown, not a freshly replenished allowance.
    func currentLimits(at now: Date) -> AgentLimits? {
        AgentClaudeServer.current(limits, now: now)
    }

    func isDue(at now: Date) -> Bool {
        guard let attempted else { return true }
        // Only a window that renewed after the reading asks sooner, so a
        // Claude Code that answers with a past renewal is not asked every minute.
        let renewed = limits.map { reading in
            reading.windows.contains { $0.resetsAt.map { $0 > reading.observedAt && $0 <= now } ?? false }
        } ?? false
        return now.timeIntervalSince(attempted) >= ClaudeAccountUsageReader.interval(after: failure, renewed: renewed)
    }
}

/// The limits of each Claude Code folder the person added, kept apart from
/// the provider-wide reading and in memory only. One folder is checked at a
/// time: when the AI page shows them and they are due, or when a card or
/// Settings asks, and never while the island is away or Claude is off.
final class ClaudeProfileLimitsService: ObservableObject {
    typealias Reader = (ClaudeAccountProfile, _ searchPath: String?, AgentClaudeServer.Request)
        -> Result<ClaudeAccountReading, ClaudeAccountUsageError>
    static let shared = ClaudeProfileLimitsService()

    @Published private(set) var states: [ClaudeProfileLimitsState] = []
    /// Which folders' sessions show under which card's name, the Claude
    /// app's folder joining the account it shares a sign-in with. Worked
    /// out when the accounts sync rather than each time a session redraws.
    @Published private(set) var logNames: [ClaudeAccountProfile.LogName] = []
    /// Asks the due folders again while the page shows any; nil otherwise.
    private(set) var timer: Timer?

    private let queue = DispatchQueue(label: "com.vorssaint.claude-profile-limits", qos: .utility)
    private let defaults: UserDefaults
    private let reader: Reader
    private let loginShellPath: () -> String?
    private var running: (id: String, request: AgentClaudeServer.Request)?
    /// Checks waiting their turn. Those the person asked for still run after
    /// the page closes; the page's own wait for it to show again.
    private var waiting: [(id: String, asked: Bool)] = []
    private var visible = false
    /// A Terminal window's PATH, asked of the login shell only when the
    /// person checks again for a Claude Code that was not found: that runs
    /// their shell's startup files.
    private var shellPath: String?

    init(defaults: UserDefaults = .standard, reader: Reader? = nil,
         loginShellPath: @escaping () -> String? = AgentCodexServer.loginShellPath) {
        self.defaults = defaults
        self.reader = reader ?? Self.read
        self.loginShellPath = loginShellPath
    }

    /// Only while an account card can show: a hidden Limits card asks nothing.
    var isEnabled: Bool {
        NotchAgentSupport.isEnabled(in: defaults) && NotchAgentSupport.showsClaudeAccounts(in: defaults)
    }

    /// Follows the saved folders and whether Claude is on. Asks only what is
    /// due, and only while the page shows.
    func synchronize() {
        if !isEnabled { cancelChecks() }
        let wanted = ClaudeAccountProfile.saved(in: defaults)
        let names = ClaudeAccountProfile.logNames(profiles: wanted)
        if names != logNames { logNames = names }
        if states.map(\.profile) != wanted {
            let previous = states
            states = wanted.map { profile in
                // A renamed folder keeps its reading and its check.
                guard var state = previous.first(where: { $0.id == profile.id && $0.profile.directory == profile.directory })
                else { return ClaudeProfileLimitsState(profile: profile) }
                state.profile = profile
                return state
            }
            let kept = Set(states.filter(\.checking).map(\.id))
            waiting.removeAll { !kept.contains($0.id) }
            if let running, !kept.contains(running.id) {
                running.request.cancel()
                self.running = nil
                startNext()
            }
        }
        syncTimer()
        if visible { refresh() }
    }

    /// A Settings preview shows what is known without asking.
    func pageDidAppear(preview: Bool = false) {
        if !preview { visible = true }
        synchronize()
    }

    /// A check under way finishes and keeps its time, so looking at the page
    /// again does not start it over.
    func pageDidDisappear() {
        visible = false
        syncTimer()
        let dropped = Set(waiting.filter { !$0.asked }.map(\.id))
        guard !dropped.isEmpty else { return }
        waiting.removeAll { !$0.asked }
        for index in states.indices where dropped.contains(states[index].id) { states[index].checking = false }
    }

    /// The island is away, the section stops or Claude is off: nothing runs.
    func pause() {
        visible = false
        cancelChecks()
        syncTimer()
    }

    /// Queues the folders that are due, or, when the person asks, `id` or
    /// every folder. One already waiting or under way is not asked twice.
    func refresh(id: String? = nil, force: Bool = false, now: Date = Date()) {
        guard isEnabled, visible || force else { return }
        for index in states.indices where id == nil || states[index].id == id {
            let state = states[index]
            if state.checking {
                if force, let place = waiting.firstIndex(where: { $0.id == state.id }) { waiting[place].asked = true }
                continue
            }
            guard force || state.isDue(at: now) else { continue }
            states[index].checking = true
            waiting.append((state.id, force))
        }
        startNext()
    }

    private func startNext() {
        guard running == nil, !waiting.isEmpty else { return }
        let next = waiting.removeFirst()
        guard let index = states.firstIndex(where: { $0.id == next.id }) else { return startNext() }
        let profile = states[index].profile
        let searching = next.asked && states[index].failure == .missingCLI && shellPath == nil
        states[index].attempted = Date()
        let request = AgentClaudeServer.Request()
        running = (next.id, request)
        let known = shellPath, shell = loginShellPath, read = reader
        queue.async { [weak self] in
            let path = searching ? shell() : known
            let result = read(profile, path, request)
            DispatchQueue.main.async {
                guard let self, self.running?.request === request else { return }
                self.running = nil
                if let path { self.shellPath = path }
                self.finish(profile, result)
                self.startNext()
            }
        }
    }

    private func finish(_ profile: ClaudeAccountProfile, _ result: Result<ClaudeAccountReading, ClaudeAccountUsageError>) {
        guard let index = states.firstIndex(where: { $0.id == profile.id && $0.profile.directory == profile.directory })
        else { return }
        var state = states[index]
        state.checking = false
        switch result {
        case .success(let reading):
            state.limits = reading.limits
            state.plan = reading.plan
            state.failure = nil
        case .failure(.cancelled):
            state.attempted = nil
        case .failure(let failure):
            // Another sign-in may be behind the folder now. A check that
            // could not finish leaves the last reading standing.
            if failure == .needsSignIn || failure == .invalidProfile {
                state.limits = nil
                state.plan = nil
            }
            state.failure = failure
        }
        states[index] = state
    }

    private func cancelChecks() {
        guard running != nil || !waiting.isEmpty else { return }
        if let running {
            running.request.cancel()
            // Asked again once checks can run.
            if let index = states.firstIndex(where: { $0.id == running.id }) { states[index].attempted = nil }
        }
        running = nil
        waiting.removeAll()
        for index in states.indices where states[index].checking { states[index].checking = false }
    }

    private func syncTimer() {
        guard visible, isEnabled, !states.isEmpty else {
            timer?.invalidate()
            timer = nil
            return
        }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Finds Claude Code as the provider's own check does, along the PATH the
    /// app was given or, once asked, a Terminal window's.
    private static func read(_ profile: ClaudeAccountProfile, searchPath: String?,
                             request: AgentClaudeServer.Request) -> Result<ClaudeAccountReading, ClaudeAccountUsageError> {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let path = searchPath ?? ProcessInfo.processInfo.environment["PATH"]
        guard let executable = AgentClaudeServer.executable(home: home, searchPath: path) else { return .failure(.missingCLI) }
        var environment = AgentCodexServer.environment(for: executable, searchPath: nil)
        environment["PATH"] = AgentClaudeServer.searchPath(after: environment["PATH"] ?? "", home: home)
        return ClaudeAccountUsageReader.read(profile, executable: executable, environment: environment,
                                             request: request, home: home)
    }
}
