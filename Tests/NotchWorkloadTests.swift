// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Docker's containers and Ollama's models, as the island's page reads them.
enum NotchWorkloadTests {
    static func run(_ suite: TestSuite) {
        docker(suite)
        ollama(suite)
        page(suite)
    }

    private static let postgres = String(repeating: "a1", count: 32)
    private static let redis = String(repeating: "b2", count: 32)

    private static func docker(_ suite: TestSuite) {
        typealias Support = NotchWorkloadSupport
        let ps = """
        WARNING: context "colima" uses an old API version
        {"Command":"\\"docker-entrypoint.s…\\"","ID":"\(postgres)","Image":"postgres:16","Names":"db,legacy-db","Status":"Up 3 hours"}
        {"ID":"\(redis)","Image":"redis:7","Names":"cache","Status":"Up 5 minutes"}
        {"ID":"zz; rm -rf ~","Image":"evil","Names":"evil","Status":"Up"}
        """
        let containers = Support.containers(ps: ps)
        suite.expect(containers.map(\.name) == ["db", "cache"] && containers.first?.image == "postgres:16"
                        && containers.first?.status == "Up 3 hours",
                     "a container is named by its first name, and lines that are not containers are skipped")
        let stats = """
        {"ID":"\(postgres.prefix(12))","MemUsage":"412.3MiB / 7.653GiB","Name":"db"}
        {"ID":"\(redis)","MemUsage":"18MiB / 7.653GiB","Name":"cache"}
        """
        let memory = Support.memory(stats: stats)
        let merged = Support.merge(containers.reversed(), memory: memory)
        suite.expect(merged.map(\.name) == ["db", "cache"]
                        && merged.first?.memory == UInt64((412.3 * 1_048_576).rounded())
                        && merged.last?.memory == 18 * 1_048_576,
                     "memory matches by short or full ID, and the largest container comes first")
        suite.expect(Support.merge(containers, memory: [:]).allSatisfy { $0.memory == nil },
                     "a container stats could not read shows no memory rather than none")
        suite.expect(Support.bytes("0B") == 0 && Support.bytes("980kB") == 980_000 && Support.bytes("1.5GiB") == 1_610_612_736
                        && Support.bytes(" 2MB ") == 2_000_000 && Support.bytes("12") == nil && Support.bytes("--") == nil
                        && Support.bytes("3XB") == nil,
                     "Docker's sizes read in both binary and decimal units")
        suite.expect(Support.isContainerID(postgres) && Support.isContainerID(String(postgres.prefix(12)))
                        && !Support.isContainerID("db") && !Support.isContainerID("abc123; quit")
                        && !Support.isContainerID(String(repeating: "a", count: 65)),
                     "only an ID Docker printed is handed back to it")
        suite.expect(Support.dockerCandidates(home: "/Users/me").contains("/Users/me/.orbstack/bin/docker")
                        && Support.dockerCandidates(home: "/Users/me").first == "/usr/local/bin/docker",
                     "the CLI is found where Docker Desktop, Homebrew and OrbStack put it")
    }

    private static func ollama(_ suite: TestSuite) {
        typealias Support = NotchWorkloadSupport
        let json = """
        {"models":[
          {"name":"qwen2.5:7b","model":"qwen2.5:7b","size":4100000000,"size_vram":4100000000,
           "expires_at":"2026-10-19T14:38:31.837531224-07:00"},
          {"name":"llama3.1:8b","model":"llama3.1:8b","size":5600000000,"size_vram":5600000000,
           "expires_at":"2318-11-01T10:00:00.5Z"},
          {"model":"","size":1}
        ]}
        """
        let models = Support.models(ps: Data(json.utf8))
        suite.expect(models?.map(\.name) == ["llama3.1:8b", "qwen2.5:7b"] && models?.first?.size == 5_600_000_000,
                     "loaded models read largest first, and a nameless one is skipped")
        suite.expect(Support.models(ps: Data(#"{"models":[]}"#.utf8)) == []
                        && Support.models(ps: Data("404 page not found".utf8)) == nil,
                     "no models loaded is an empty list, and another server's answer is none")
        let expiry = Support.date("2026-10-19T14:38:31.837531224-07:00")
        suite.expect(expiry == Date(timeIntervalSince1970: 1_792_445_911) && Support.date("2026-10-19T21:38:31Z") == expiry,
                     "Go's nine fractional digits and its offsets read as the same moment")
        let qwen = models?.last, llama = models?.first
        let now = Date(timeIntervalSince1970: 1_792_445_911 - 240)
        suite.expect(qwen.flatMap { Support.remaining($0, now: now) } == 240
                        && llama.flatMap { Support.remaining($0, now: now) } == nil,
                     "a model counts down to its unload, and one kept for good does not")
        suite.expect(Support.remaining(NotchOllamaModel(name: "x", size: 1, expiresAt: now.addingTimeInterval(-5)), now: now) == 0,
                     "a model past its time reads as leaving now")
        let english = Locale(identifier: "en_US")
        suite.expect(Support.timeLeft(240, locale: english) == "4 min" && Support.timeLeft(10, locale: english) == "1 min"
                        && Support.timeLeft(7200, locale: english).hasPrefix("2"),
                     "the time left rounds up to whole minutes, never down to none")
        let body = (try? JSONSerialization.jsonObject(with: Support.unloadBody("llama3.1:8b"))) as? [String: Any]
        suite.expect(body?["model"] as? String == "llama3.1:8b" && (body?["keep_alive"] as? Int) == 0 && body?.count == 2,
                     "unloading sends what ollama stop sends")
    }

    private static func page(_ suite: TestSuite) {
        suite.expect(NotchModule.workloads.symbol == "shippingbox"
                        && Set(NotchModule.allCases.map(\.shortcutKey)).count == NotchModule.allCases.count,
                     "the page has its own mark and its own key")
        let defaults = UserDefaults(suiteName: "vorss.tests.notch-workloads")!
        defaults.removePersistentDomain(forName: "vorss.tests.notch-workloads")
        defer { defaults.removePersistentDomain(forName: "vorss.tests.notch-workloads") }
        defaults.set(false, forKey: AppFeature.notchWorkloads.availabilityKey)
        suite.expect(!NotchModule.workloads.isAvailable(in: defaults), "the page waits until the feature is installed")
        defaults.set(true, forKey: AppFeature.notchWorkloads.availabilityKey)
        suite.expect(NotchModule.workloads.isAvailable(in: defaults) && AppFeature.notchWorkloads.permissions.isEmpty
                        && !AppFeature.notchWorkloads.installedByDefault,
                     "installing it adds the page, asks for nothing, and it ships uninstalled")
        suite.expect(AppLanguage.allCases.allSatisfy { language in
            let text = FeatureStrings.notchWorkloads(language)
            let lines = Mirror(reflecting: text).children.compactMap { $0.value as? String }
            return lines.count == 14 && lines.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                && text.confirmStop("db").contains("db") && text.unloadsIn("4 min").contains("4 min")
                && !FeatureStrings.notchEditor(language).summary(.workloads).isEmpty
        }, "every language has every line of the page")
    }
}
