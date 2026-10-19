// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum ClaudeAccountLimitsTests {
    static func run(_ suite: TestSuite) {
        strings(suite)
        let manager = FileManager.default
        let home = manager.temporaryDirectory.appendingPathComponent("claude-accounts-" + UUID().uuidString)
            .resolvingSymlinksInPath()
        defer { try? manager.removeItem(at: home) }
        do {
            try manager.createDirectory(at: home, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            // The usual folder, two accounts an alias points Claude Code at,
            // and another tool's folder that merely shares the prefix.
            for (name, org) in [(".claude-personal", "personal"), (".claude-work", "work")] {
                let folder = home.appending(path: name)
                try manager.createDirectory(at: folder.appending(path: "projects/-Users-me-app"),
                                            withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try profileJSON(org).write(to: folder.appending(path: ".claude.json"))
            }
            try manager.createDirectory(at: home.appending(path: ".claude/projects"), withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
            try profileJSON("usual").write(to: home.appending(path: ".claude.json"))
            try manager.createDirectory(at: home.appending(path: ".claude-helper/cache"), withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
            folders(suite, home: home)
            try checks(suite, home: home)
            tiles(suite)
            lifecycle(suite, home: home)
        } catch { suite.expect(false, "Claude account contract: \(error)") }
    }

    private static func profileJSON(_ organization: String) -> Data {
        Data(#"{"oauthAccount":{"organizationUuid":"\#(organization)","organizationType":"claude_max"}}"#.utf8)
    }

    private static func sameAccount(_ person: String, _ organization: String) -> Data {
        Data(#"{"oauthAccount":{"accountUuid":"\#(person)","organizationUuid":"\#(organization)"}}"#.utf8)
    }

    private static func strings(_ suite: TestSuite) {
        let informal: [AppLanguage: String] = [
            .ru: #"(?i)\b(выбери|войди|обнови|попробуй|установи|выполни|ты|тебе|тебя|твой|твоя)\b"#,
            .uk: #"(?i)\b(вибери|увійди|онови|спробуй|установи|виконай|ти|тобі|тебе|твій|твоя)\b"#]
        for (language, pattern) in informal {
            let text = Mirror(reflecting: FeatureStrings.claudeAccounts(language)).children.compactMap { $0.value as? String }
            suite.expect(!text.isEmpty && text.allSatisfy { $0.range(of: pattern, options: .regularExpression) == nil },
                         "Claude account text uses the formal register in \(language.rawValue)")
        }
        suite.expect(AppLanguage.allCases.allSatisfy { language in
            Mirror(reflecting: FeatureStrings.claudeAccounts(language)).children.allSatisfy {
                !(($0.value as? String) ?? "").trimmingCharacters(in: .whitespaces).isEmpty
            }
        }, "every language has every Claude account line")
    }

    private static func folders(_ suite: TestSuite, home: URL) {
        let profile = ClaudeAccountProfile(id: UUID().uuidString, name: "Work", directory: home.appending(path: ".claude-work").path)
        let decoded = ClaudeAccountProfile.decode(ClaudeAccountProfile.encode([
            profile, ClaudeAccountProfile(id: "not-a-uuid", name: "Bad", directory: "/tmp"),
            ClaudeAccountProfile(id: UUID().uuidString, name: "Again", directory: profile.directory),
            ClaudeAccountProfile(id: UUID().uuidString, name: "Relative", directory: "relative/path")]))
        suite.expect(decoded == [profile], "saved Claude accounts keep only valid, distinct folders")

        let found = ClaudeAccountProfile.discover(home: home, defaultName: "Default")
        suite.expect(found.map(\.name) == ["Personal", "Work"]
                        && found.map { URL(fileURLWithPath: $0.directory).lastPathComponent }
                            == [".claude-personal", ".claude-work"],
                     "finding local accounts lists each ~/.claude-<name> Claude Code used, not the Claude app's usual folder")
        let usualOnly = home.appending(path: "only-usual")
        try? FileManager.default.createDirectory(at: usualOnly.appending(path: ".claude/projects"),
                                                 withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let lone = ClaudeAccountProfile.discover(home: usualOnly, defaultName: "Default")
        suite.expect(lone.map(\.name) == ["Default"] && lone.first?.configDirectory(home: usualOnly) == nil
                        && found.last?.configDirectory(home: home)?.lastPathComponent == ".claude-work",
                     "the usual folder is found while it is the only one, and is never passed as CLAUDE_CONFIG_DIR")
        suite.expect(ClaudeAccountProfile.mainConfigDirectory(profiles: found, home: home)?.lastPathComponent == ".claude-personal"
                        && ClaudeAccountProfile.mainConfigDirectory(profiles: [], home: home) == nil
                        && ClaudeAccountProfile.mainConfigDirectory(profiles: lone, home: usualOnly) == nil,
                     "Claude's own reading follows the first added account, and the usual folder while none is")

        let configured = ClaudeAccountProfile.configDirectories(home: home, profiles: [])
        suite.expect(configured.map(\.lastPathComponent) == [".claude-personal", ".claude-work"],
                     "sessions are read from every account folder Claude Code used, never another tool's folder")
        let real = AgentLogRoot.canonical(home)
        let roots = AgentLogRoot.all(home: home, claudeFolders: configured).filter { $0.provider == .claude }
        // A root that does not exist yet keeps the path as given, which a
        // temporary folder's link makes differ from the real one.
        suite.expect(roots.map { $0.url.pathComponents.suffix(2).joined(separator: "/") }
                        == [".claude/projects", "claude/projects", ".claude-personal/projects", ".claude-work/projects"],
                     "each account folder's projects are a Claude log root beside the usual ones")
        let twice = AgentLogRoot.all(home: home, claudeFolders: configured + configured + [home.appending(path: ".claude")])
        suite.expect(twice.count == Set(twice.map(\.url)).count, "a folder listed twice is read once")
        // Logs are named by their real path, as discovery and file events report them.
        let work = real.appending(path: ".claude-work/projects/-Users-me-app/session.jsonl").path
        let usual = real.appending(path: ".claude/projects/-Users-me-app/session.jsonl").path
        suite.expect(ClaudeAccountProfile.accountName(forLog: work, profiles: [], home: home) == "Work"
                        && ClaudeAccountProfile.accountName(forLog: usual, profiles: [], home: home) == nil,
                     "a running session is labeled with its account folder; the usual one stays unlabeled")
        var named = profile
        named.name = "Job"
        let usualProfile = ClaudeAccountProfile(id: UUID().uuidString, name: "Personal",
                                                directory: home.appending(path: ".claude").path)
        // The usual folder signs in as Personal does, as the Claude app and an alias for the same account do.
        let personal = ClaudeAccountProfile(id: UUID().uuidString, name: "Personal",
                                            directory: home.appending(path: ".claude-personal").path)
        try? sameAccount("acct-1", "org-1").write(to: home.appending(path: ".claude.json"))
        try? sameAccount("acct-1", "org-1").write(to: home.appending(path: ".claude-personal/.claude.json"))
        try? sameAccount("acct-2", "org-2").write(to: home.appending(path: ".claude-work/.claude.json"))
        let merged = ClaudeAccountProfile.logNames(profiles: [personal, named], home: home)
        suite.expect(ClaudeAccountProfile.accountName(forLog: usual, names: merged, home: home) == "Personal"
                        && ClaudeAccountProfile.accountName(forLog: work, names: merged, home: home) == "Job"
                        && ClaudeAccountProfile.accountName(forLog: usual, profiles: [named], home: home) == nil,
                     "the Claude app's sessions show under the added account it shares a sign-in with, and no other")
        try? sameAccount("acct-1", "org-2").write(to: home.appending(path: ".claude-personal/.claude.json"))
        suite.expect(ClaudeAccountProfile.accountName(forLog: usual, profiles: [personal, named], home: home) == nil,
                     "the same person in another organization is another account")
        try? profileJSON("personal").write(to: home.appending(path: ".claude-personal/.claude.json"))
        try? profileJSON("work").write(to: home.appending(path: ".claude-work/.claude.json"))
        try? profileJSON("usual").write(to: home.appending(path: ".claude.json"))
        suite.expect(ClaudeAccountProfile.accountName(forLog: work, profiles: [named], home: home) == "Job"
                        && ClaudeAccountProfile.accountName(forLog: usual, profiles: [usualProfile], home: home) == "Personal",
                     "a session takes the name its account's card was given")
    }

    private static func checks(_ suite: TestSuite, home: URL) throws {
        let work = home.appending(path: ".claude-work")
        try JSONSerialization.data(withJSONObject: ["env": ["DISABLE_TELEMETRY": "1"]])
            .write(to: work.appending(path: "settings.json"))
        defer { try? FileManager.default.removeItem(at: work.appending(path: "settings.json")) }
        let base = ["PATH": "/usr/bin", "CLAUDE_CONFIG_DIR": "/elsewhere"]
        suite.expect(AgentClaudeServer.environment(base, home: home, configDirectory: work)
                        == ["PATH": "/usr/bin", "DISABLE_AUTOUPDATER": "1", "DISABLE_TELEMETRY": "1",
                            "CLAUDE_CONFIG_DIR": work.path]
                        && AgentClaudeServer.environment(base, home: home) == ["PATH": "/usr/bin", "DISABLE_AUTOUPDATER": "1"],
                     "a check points Claude Code at the account's folder and its settings, and the usual one at none")
        suite.expect(AgentClaudeServer.organization(home: home, configDirectory: work) == "work"
                        && AgentClaudeServer.organization(home: home) == "usual",
                     "an account folder keeps its own sign-in profile inside it")

        let tool = home.appending(path: "claude")
        try Data(standIn.utf8).write(to: tool)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        let environment = ["PATH": "/usr/bin:/bin", "HOME": home.path, "CLAUDE_CONFIG_DIR": "/elsewhere"]
        func read(_ name: String) -> Result<ClaudeAccountReading, ClaudeAccountUsageError> {
            let profile = ClaudeAccountProfile(id: UUID().uuidString, name: name, directory: home.appending(path: name).path)
            return ClaudeAccountUsageReader.read(profile, executable: tool, environment: environment,
                                                 request: AgentClaudeServer.Request(), home: home, timeout: 5)
        }
        let readings = [".claude-work", ".claude-personal", ".claude"].map { try? read($0).get() }
        suite.expect(readings.map { $0?.limits.windows.first?.usedPercent } == [30, 70, 50]
                        && readings.allSatisfy { $0?.limits.source == .account && $0?.plan != nil },
                     "each account is checked with its own folder's sign-in and keeps its own limits and plan")
        let missing = ClaudeAccountProfile(id: UUID().uuidString, name: "Gone", directory: home.appending(path: ".claude-gone").path)
        let cancelled = AgentClaudeServer.Request()
        cancelled.cancel()
        suite.expect(ClaudeAccountUsageReader.read(missing, executable: tool, environment: environment,
                                                   request: AgentClaudeServer.Request(), home: home) == .failure(.invalidProfile)
                        && read(".claude-helper") == .failure(.invalidProfile)
                        && ClaudeAccountUsageReader.read(
                            ClaudeAccountProfile(id: UUID().uuidString, name: "W", directory: work.path), executable: tool,
                            environment: environment, request: cancelled, home: home) == .failure(.cancelled),
                     "a folder that is gone or not Claude Code's is never checked, and a cancelled check says so")
    }

    private static func tiles(_ suite: TestSuite) {
        let tiles = NotchAgentSupport.tiles(cards: [.limits], providers: [.claude, .codex], claudeAccounts: ["a", "b"])
        suite.expect(tiles.map(\.id) == ["limits.claude.a", "limits.claude.b", "limits.codex"]
                        && NotchAgentSupport.height(of: [tiles[0]]) == NotchAgentSupport.accountCardHeight,
                     "added Claude accounts take the place of Claude's one limits card")
    }

    private final class Probe: @unchecked Sendable {
        private let lock = NSLock()
        private var asked: [String] = []
        var calls: [String] { lock.withLock { asked } }

        func read(_ profile: ClaudeAccountProfile, _ path: String?,
                  _ request: AgentClaudeServer.Request) -> Result<ClaudeAccountReading, ClaudeAccountUsageError> {
            lock.withLock { asked.append(profile.id) }
            let window = AgentLimitWindow(id: "claude.fh", kind: .session, minutes: 300, scope: nil, usedPercent: 42,
                                          resetsAt: Date().addingTimeInterval(3600))
            return .success(ClaudeAccountReading(limits: AgentLimits(provider: .claude, windows: [window], observedAt: Date(),
                                                                     source: .account), plan: "Max"))
        }
    }

    private static func wait(until condition: () -> Bool) {
        let end = Date().addingTimeInterval(3)
        while !condition() && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }

    private static func lifecycle(_ suite: TestSuite, home: URL) {
        let domain = "com.vorssaint.tests.claude-accounts." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        for (key, value) in Defaults.registeredDefaults where key.hasPrefix("notch") { defaults.set(value, forKey: key) }
        for feature in AppFeature.allCases { defaults.set(true, forKey: feature.availabilityKey) }
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        defaults.set(true, forKey: DefaultsKey.notchAgentsEnabled)
        let profiles = ClaudeAccountProfile.discover(home: home, defaultName: "Default")
        defaults.set(ClaudeAccountProfile.encode(profiles), forKey: DefaultsKey.notchAgentsClaudeProfiles)

        let probe = Probe()
        let service = ClaudeProfileLimitsService(defaults: defaults, reader: probe.read, loginShellPath: { nil })
        defer { service.pause() }
        service.synchronize(); service.refresh()
        suite.expect(service.isEnabled && probe.calls.isEmpty && service.states.count == 2,
                     "adding Claude accounts checks none until the page shows them")
        service.pageDidAppear()
        wait { service.states.allSatisfy { !$0.checking } }
        suite.expect(probe.calls == profiles.map(\.id) && service.states.allSatisfy { $0.limits != nil && $0.plan == "Max" }
                        && service.timer != nil,
                     "the page checks each Claude account once, one at a time, and keeps checking while it shows")
        defaults.set(false, forKey: DefaultsKey.notchAgentsClaude)
        service.synchronize()
        suite.expect(!service.isEnabled && service.timer == nil, "turning Claude off stops its account checks")
    }

    /// Answers for whichever folder it is pointed at, and saves what it
    /// fetched there on its way out, as Claude Code does.
    private static let standIn = #"""
    #!/bin/sh
    [ -z "$CLAUDECODE" ] && [ "$DISABLE_AUTOUPDATER" = 1 ] || exit 2
    [ "$CLAUDE_CONFIG_DIR" = /elsewhere ] && exit 5
    if [ -n "$CLAUDE_CONFIG_DIR" ]; then target="$CLAUDE_CONFIG_DIR/.claude.json"; else target="$HOME/.claude.json"; fi
    case "$CLAUDE_CONFIG_DIR" in *work) used=30; org=work ;; *personal) used=70; org=personal ;; "") used=50; org=usual ;; *) exit 6 ;; esac
    while IFS= read -r line; do
      case "$line" in
        *'"subtype":"initialize"'*)
          printf '%s\n' '{"type":"control_response","response":{"subtype":"success","request_id":"initialize","response":{}}}' ;;
        *'"subtype":"get_usage"'*)
          printf '{"type":"control_response","response":{"subtype":"success","request_id":"usage","response":{"rate_limits_available":true,"rate_limits":{"five_hour":{"utilization":%s,"resets_at":"2099-10-15T10:40:00Z"}}}}}\n' "$used" ;;
      esac
    done
    printf '{"oauthAccount":{"organizationUuid":"%s","organizationType":"claude_max"},"cachedUsageUtilization":{"fetchedAtMs":%s000}}\n' "$org" "$(date +%s)" > "$target"
    """#
}
