// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Where Docker or Ollama stands on this Mac.
enum NotchWorkloadState: Equatable {
    /// Not read yet.
    case unknown
    /// Not installed, so its section stays away.
    case missing
    /// Installed, but its daemon or server does not answer.
    case stopped
    case running
}

/// A running container, with the memory Docker counts against it.
struct NotchDockerContainer: Identifiable, Equatable {
    let id: String
    let name: String
    let image: String
    let status: String
    var memory: UInt64?
}

/// A model Ollama holds in memory, and when it lets go of it by itself.
struct NotchOllamaModel: Identifiable, Equatable {
    let name: String
    let size: UInt64
    let expiresAt: Date?
    var id: String { name }
}

enum NotchWorkloadSupport {
    /// The island page reads again this long after the last reading ended.
    /// `docker stats` alone takes about two seconds to sample.
    static let interval: TimeInterval = 3
    static let ollamaURL = URL(string: "http://127.0.0.1:11434")!
    /// An expiry this far off is Ollama's "keep it loaded" (`keep_alive: -1`).
    static let foreverAfter: TimeInterval = 365 * 24 * 3600

    /// Docker Desktop links its CLI into /usr/local/bin, Homebrew into its own
    /// prefix, and OrbStack and Rancher Desktop into the home folder. An app
    /// opened from Finder has none of these on its PATH.
    static func dockerCandidates(home: String) -> [String] {
        ["/usr/local/bin/docker", "/opt/homebrew/bin/docker",
         "/Applications/Docker.app/Contents/Resources/bin/docker",
         home + "/.orbstack/bin/docker", home + "/.rd/bin/docker", home + "/.docker/bin/docker"]
    }

    static func ollamaCandidates(home: String) -> [String] {
        ["/Applications/Ollama.app", home + "/Applications/Ollama.app",
         "/usr/local/bin/ollama", "/opt/homebrew/bin/ollama"]
    }

    /// `docker ps --format '{{json .}}'`: one object per line. Anything else
    /// the CLI prints, like a warning about its context, is skipped.
    static func containers(ps output: String) -> [NotchDockerContainer] {
        jsonLines(output).compactMap { row in
            guard let id = row["ID"] as? String, isContainerID(id) else { return nil }
            let names = (row["Names"] as? String) ?? ""
            return NotchDockerContainer(id: id,
                                        name: names.split(separator: ",").first.map(String.init) ?? String(id.prefix(12)),
                                        image: (row["Image"] as? String) ?? "",
                                        status: (row["Status"] as? String) ?? "")
        }
    }

    /// `docker stats --no-stream --format '{{json .}}'`, as memory in use by
    /// container ID. Short and full IDs both match, so either listing works.
    static func memory(stats output: String) -> [String: UInt64] {
        var memory: [String: UInt64] = [:]
        for row in jsonLines(output) {
            guard let id = (row["ID"] as? String) ?? (row["Container"] as? String),
                  let usage = row["MemUsage"] as? String,
                  let used = usage.components(separatedBy: "/").first,
                  let bytes = bytes(used) else { continue }
            memory[id] = bytes
        }
        return memory
    }

    static func merge(_ containers: [NotchDockerContainer], memory: [String: UInt64]) -> [NotchDockerContainer] {
        containers.map { container in
            var container = container
            container.memory = memory[container.id]
                ?? memory.first { container.id.hasPrefix($0.key) || $0.key.hasPrefix(container.id) }?.value
            return container
        }
        .sorted { ($0.memory ?? 0, $1.name) > ($1.memory ?? 0, $0.name) }
    }

    /// Docker's own sizes: "412.3MiB", "1.2GiB", "980kB", "0B".
    static func bytes(_ text: String) -> UInt64? {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard let split = text.firstIndex(where: { !$0.isNumber && $0 != "." }),
              let value = Double(text[..<split]), value.isFinite, value >= 0 else { return nil }
        let units: [String: Double] = [
            "b": 1, "kib": 0x1p10, "mib": 0x1p20, "gib": 0x1p30, "tib": 0x1p40,
            "kb": 1e3, "mb": 1e6, "gb": 1e9, "tb": 1e12,
        ]
        guard let unit = units[text[split...].trimmingCharacters(in: .whitespaces).lowercased()] else { return nil }
        return UInt64((value * unit).rounded())
    }

    /// Ollama's `/api/ps`, largest model first. Nil when the answer is not one.
    static func models(ps data: Data) -> [NotchOllamaModel]? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = object["models"] as? [[String: Any]] else { return nil }
        return rows.compactMap { row -> NotchOllamaModel? in
            guard let name = (row["name"] as? String) ?? (row["model"] as? String), !name.isEmpty else { return nil }
            let size = (row["size"] as? NSNumber)?.uint64Value ?? 0
            return NotchOllamaModel(name: name, size: size, expiresAt: (row["expires_at"] as? String).flatMap(date))
        }
        .sorted { ($0.size, $1.name) > ($1.size, $0.name) }
    }

    /// Go's RFC 3339 times carry up to nine fractional digits, which
    /// ISO8601DateFormatter does not read, and the fraction does not matter here.
    static func date(_ text: String) -> Date? {
        var text = text
        if let dot = text.firstIndex(of: "."),
           let end = text[dot...].firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }) {
            text.removeSubrange(dot..<end)
        }
        return ISO8601DateFormatter().date(from: text)
    }

    /// Seconds until Ollama unloads the model itself; nil when it keeps it.
    static func remaining(_ model: NotchOllamaModel, now: Date) -> TimeInterval? {
        guard let expiresAt = model.expiresAt else { return nil }
        let left = expiresAt.timeIntervalSince(now)
        return left > foreverAfter ? nil : max(0, left)
    }

    /// "4 min", "2 hr": the time left, rounded up to the minute so the last
    /// one never reads as none.
    static func timeLeft(_ seconds: TimeInterval, locale: Locale) -> String {
        let formatter = DateComponentsFormatter()
        var calendar = Calendar.current
        calendar.locale = locale
        formatter.calendar = calendar
        formatter.unitsStyle = .short
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
        formatter.maximumUnitCount = 1
        return formatter.string(from: max(60, (seconds / 60).rounded(.up) * 60)) ?? ""
    }

    static func memory(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .memory)
    }

    /// What `ollama stop` sends: the model, with nothing to generate and no
    /// time left in memory.
    static func unloadBody(_ model: String) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["model": model, "keep_alive": 0])) ?? Data()
    }

    /// Only an ID Docker printed goes back to it.
    static func isContainerID(_ id: String) -> Bool {
        (12...64).contains(id.count) && id.allSatisfy(\.isHexDigit)
    }

    private static func jsonLines(_ output: String) -> [[String: Any]] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            guard line.first == "{" else { return nil }
            return (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
        }
    }
}
