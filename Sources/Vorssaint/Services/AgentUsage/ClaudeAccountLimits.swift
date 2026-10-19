// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// A Claude Code folder of its own, a `CLAUDE_CONFIG_DIR`, whose account gets
/// a limits card. The usual `~/.claude` keeps its sign-in beside it, in
/// `~/.claude.json`; any other folder keeps that file inside.
struct ClaudeAccountProfile: Codable, Equatable, Identifiable {
    static let maximum = 8
    static let prefix = ".claude-"

    let id: String
    var name: String
    let directory: String

    static func decode(_ value: String) -> [Self] {
        guard value.utf8.count <= 64 * 1024,
              let decoded = try? JSONDecoder().decode([Self].self, from: Data(value.utf8)) else { return [] }
        var ids = Set<String>(), paths = Set<String>()
        return decoded.prefix(maximum).filter {
            UUID(uuidString: $0.id) != nil && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.name.count <= 40 && $0.directory.hasPrefix("/")
                && ids.insert($0.id).inserted
                && paths.insert(URL(fileURLWithPath: $0.directory).resolvingSymlinksInPath().path).inserted
        }
    }

    static func encode(_ profiles: [Self]) -> String {
        (try? JSONEncoder().encode(profiles)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    static func saved(in defaults: UserDefaults = .standard) -> [Self] {
        decode(defaults.string(forKey: DefaultsKey.notchAgentsClaudeProfiles) ?? "")
    }

    /// The usual folder, which Claude Code uses without `CLAUDE_CONFIG_DIR`.
    static func defaultDirectory(home: URL) -> URL {
        home.appending(path: ".claude", directoryHint: .isDirectory).resolvingSymlinksInPath()
    }

    /// Only metadata is looked at: Claude Code, not Vorssaint, opens the
    /// sign-in, which it keeps in the Keychain. The folder must be the
    /// person's own, and its account profile, when there is one, too.
    func canonicalDirectory(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        guard directory.hasPrefix("/") else { return nil }
        let manager = FileManager.default
        let url = URL(fileURLWithPath: directory, isDirectory: true).resolvingSymlinksInPath()
        guard url.path != "/", url != home.resolvingSymlinksInPath(),
              let root = try? manager.attributesOfItem(atPath: url.path),
              root[.type] as? FileAttributeType == .typeDirectory,
              (root[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              let mode = root[.posixPermissions] as? NSNumber, mode.intValue & 0o022 == 0 else { return nil }
        let profile = Self.profileURL(configDirectory: url == Self.defaultDirectory(home: home) ? nil : url, home: home)
        if let metadata = try? manager.attributesOfItem(atPath: profile.path) {
            // A symbolic or hard link would make two folders one account.
            guard metadata[.type] as? FileAttributeType == .typeRegular,
                  (metadata[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
                  (metadata[.referenceCount] as? NSNumber)?.intValue == 1 else { return nil }
            return url
        }
        // A folder Claude Code has not signed in from yet still has its settings or logs.
        let known = ["settings.json", "projects"].contains { manager.fileExists(atPath: url.appending(path: $0).path) }
        return known ? url : nil
    }

    /// What a check sets `CLAUDE_CONFIG_DIR` to: nil for the usual folder,
    /// which Claude Code finds without it.
    func configDirectory(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        guard let url = canonicalDirectory(home: home) else { return nil }
        return url == Self.defaultDirectory(home: home) ? nil : url
    }

    /// Where Claude Code keeps the account it signs in to.
    static func profileURL(configDirectory: URL?, home: URL) -> URL {
        configDirectory?.appending(path: ".claude.json") ?? home.appending(path: ".claude.json")
    }

    /// The `~/.claude-<name>` folders, or `~/.claude`, named `defaultName`,
    /// while there are none. Once Claude Code runs with folders of its own,
    /// the usual one is the Claude app's, which signs in to it for its own
    /// sessions, and is not one of the person's accounts. It can be added by
    /// hand.
    static func discover(home: URL = FileManager.default.homeDirectoryForCurrentUser, defaultName: String) -> [Self] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: home, includingPropertiesForKeys: nil)) ?? []
        var paths = Set<String>()
        let found = folders.filter { $0.lastPathComponent == ".claude" || $0.lastPathComponent.hasPrefix(prefix) }
            .sorted { $0.path < $1.path }.compactMap { folder -> Self? in
                let profile = Self(id: UUID().uuidString, name: name(for: folder, defaultName: defaultName),
                                   directory: folder.path)
                guard let canonical = profile.canonicalDirectory(home: home), paths.insert(canonical.path).inserted
                else { return nil }
                return Self(id: profile.id, name: profile.name, directory: canonical.path)
            }
        let usual = defaultDirectory(home: home).path
        let own = found.filter { $0.directory != usual }
        return own.isEmpty ? found : own
    }

    /// The folder Claude's provider-wide reading checks: the first account
    /// the person added, or nil for the usual folder while none is.
    static func mainConfigDirectory(profiles: [Self] = saved(),
                                    home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        profiles.lazy.compactMap { $0.canonicalDirectory(home: home) }.first
            .flatMap { $0 == defaultDirectory(home: home) ? nil : $0 }
    }

    /// `.claude-work` is Work; the usual `.claude` takes `defaultName`.
    static func name(for folder: URL, defaultName: String) -> String {
        let folder = folder.lastPathComponent
        let name = folder.hasPrefix(prefix) ? String(folder.dropFirst(prefix.count)) : String(folder.drop { $0 == "." })
        return name.isEmpty || folder == ".claude" ? defaultName : String(name.capitalized.prefix(40))
    }

    /// The other Claude Code folders whose sessions are read beside the
    /// usual one's: each `~/.claude-<name>` Claude Code has used, as one an
    /// alias sets `CLAUDE_CONFIG_DIR` to, and every folder added in Settings.
    /// A folder counts as used once it holds both an account profile and
    /// session logs, so another tool's `.claude-` folder is left alone.
    static func configDirectories(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                                  profiles: [Self] = saved()) -> [URL] {
        let manager = FileManager.default
        let folders = (try? manager.contentsOfDirectory(at: home, includingPropertiesForKeys: nil)) ?? []
        let found = folders.filter { $0.lastPathComponent.hasPrefix(prefix) }.sorted { $0.path < $1.path }.filter {
            manager.fileExists(atPath: $0.appending(path: ".claude.json").path)
                && manager.fileExists(atPath: $0.appending(path: "projects").path)
        }
        let probe = { (url: URL) in Self(id: "", name: "", directory: url.path) }
        var seen = Set([defaultDirectory(home: home).path])
        return (found.map(probe) + profiles).compactMap { $0.canonicalDirectory(home: home) }
            .filter { seen.insert($0.path).inserted }
    }

    /// A folder whose sessions show under an account card's name. `folder`
    /// is its real path with a trailing slash, as logs are named.
    struct LogName: Equatable {
        let folder: String
        let name: String
    }

    /// The person and organization a folder's account profile signs in to;
    /// nil while it names neither.
    static func identity(configDirectory: URL?, home: URL) -> String? {
        guard let data = try? Data(contentsOf: profileURL(configDirectory: configDirectory, home: home)),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let account = json["oauthAccount"] as? [String: Any],
              let person = account["accountUuid"] as? String, let organization = account["organizationUuid"] as? String,
              !person.isEmpty, !organization.isEmpty else { return nil }
        return person + "/" + organization
    }

    /// Each added folder under its card's name. The usual folder, which the
    /// Claude app signs in to, joins the added account it shares a sign-in
    /// with, so the app's sessions and the terminal's show as one account.
    /// Only the profiles are read; nothing in the folders changes.
    static func logNames(profiles: [Self], home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [LogName] {
        var names = profiles.compactMap { profile in
            profile.canonicalDirectory(home: home).map { LogName(folder: AgentLogRoot.canonical($0).path + "/", name: profile.name) }
        }
        let usual = AgentLogRoot.canonical(defaultDirectory(home: home)).path + "/"
        guard !names.contains(where: { $0.folder == usual }),
              let shared = identity(configDirectory: nil, home: home),
              let match = profiles.first(where: { profile in
                  profile.configDirectory(home: home).map { identity(configDirectory: $0, home: home) == shared } ?? false
              }) else { return names }
        names.append(LogName(folder: usual, name: match.name))
        return names
    }

    static func accountName(forLog path: String, profiles: [Self],
                            home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
        accountName(forLog: path, names: logNames(profiles: profiles, home: home), home: home)
    }

    /// The account a Claude session log belongs to, named as its card is, or
    /// for its folder: nil for the usual folder while no card claims it.
    /// Logs are named by their real path, so folders are compared by theirs.
    static func accountName(forLog path: String, names: [LogName],
                            home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
        if let match = names.first(where: { path.hasPrefix($0.folder) }) { return match.name }
        let base = AgentLogRoot.canonical(home).path + "/"
        guard path.hasPrefix(base), let folder = path.dropFirst(base.count).split(separator: "/").first,
              folder.hasPrefix(prefix) else { return nil }
        return name(for: URL(fileURLWithPath: base + folder), defaultName: "")
    }
}

/// What stopped an account check.
enum ClaudeAccountUsageError: Error, Equatable {
    /// The folder is no longer a private Claude Code folder.
    case invalidProfile
    /// Claude Code is not on this Mac.
    case missingCLI
    /// Signed out, or signed in with a key, which has no plan limits.
    case needsSignIn
    /// A Claude Code from before its limits could be read from outside it.
    case outdated
    /// No usable answer: it stopped, ran out of time or refused.
    case unavailable
    /// The page closed for good, the Mac locked or Claude was turned off.
    case cancelled
}

struct ClaudeAccountReading: Equatable {
    let limits: AgentLimits
    let plan: String?
}

/// Asks the account behind one Claude Code folder for its limits, the way
/// the provider's own check does, with that folder's sign-in.
enum ClaudeAccountUsageReader {
    /// A reading this recent still stands.
    static let refreshInterval: TimeInterval = 5 * 60
    /// After a window renews, the next reading comes sooner.
    static let renewedInterval: TimeInterval = 60
    static let retryAfter: TimeInterval = 5 * 60
    /// Only the person can install, update or sign in to Claude Code, or fix a folder.
    static let settledRetry: TimeInterval = 30 * 60

    /// How long after the last check the account is asked again.
    static func interval(after failure: ClaudeAccountUsageError?, renewed: Bool) -> TimeInterval {
        switch failure {
        case nil: return renewed ? renewedInterval : refreshInterval
        case .unavailable?, .cancelled?: return retryAfter
        case .invalidProfile?, .missingCLI?, .needsSignIn?, .outdated?: return settledRetry
        }
    }

    /// The plan the folder's account profile names.
    static func plan(configDirectory: URL?, home: URL) -> String? {
        guard let data = try? Data(contentsOf: ClaudeAccountProfile.profileURL(configDirectory: configDirectory, home: home)),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let account = json["oauthAccount"] as? [String: Any] else { return nil }
        return AgentPlans.claude(organizationType: account["organizationType"] as? String,
                                 rateLimitTier: account["organizationRateLimitTier"] as? String
                                    ?? account["userRateLimitTier"] as? String)?.name
    }

    static func read(_ profile: ClaudeAccountProfile, executable: URL, environment: [String: String],
                     request: AgentClaudeServer.Request,
                     home: URL = FileManager.default.homeDirectoryForCurrentUser,
                     timeout: TimeInterval = AgentClaudeServer.timeout) -> Result<ClaudeAccountReading, ClaudeAccountUsageError> {
        guard profile.canonicalDirectory(home: home) != nil else { return .failure(.invalidProfile) }
        let configDirectory = profile.configDirectory(home: home)
        let result = request.run(executable, home: home, configDirectory: configDirectory,
                                 environment: environment, timeout: timeout)
        if request.isCancelled { return .failure(.cancelled) }
        switch result {
        case .success(let summary):
            return .success(ClaudeAccountReading(limits: summary.limits,
                                                 plan: plan(configDirectory: configDirectory, home: home)))
        case .failure(.missing): return .failure(.missingCLI)
        case .failure(.needsSignIn): return .failure(.needsSignIn)
        case .failure(.outdated): return .failure(.outdated)
        case .failure(.unreachable): return .failure(.unavailable)
        }
    }
}
