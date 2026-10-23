// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Running Docker containers and the Ollama models held in memory, read only
/// while the island's page is open. Docker is asked through its own CLI, so
/// whichever engine and context the person uses answers; Ollama through its
/// local server.
final class NotchWorkloadService: ObservableObject {
    static let shared = NotchWorkloadService()

    @Published private(set) var docker = NotchWorkloadState.unknown
    @Published private(set) var containers: [NotchDockerContainer] = []
    @Published private(set) var ollama = NotchWorkloadState.unknown
    @Published private(set) var models: [NotchOllamaModel] = []
    /// Containers and models asked to stop that are still on their way out.
    @Published private(set) var stopping: Set<String> = []

    private let queue = DispatchQueue(label: "com.vorssaint.notch.workloads", qos: .utility)
    /// A stop can take Docker ten seconds; readings go on meanwhile.
    private let actions = DispatchQueue(label: "com.vorssaint.notch.workloads.actions", qos: .userInitiated)
    private var viewers = 0
    private var reading = false
    private var next: DispatchWorkItem?
    private let home = FileManager.default.homeDirectoryForCurrentUser.path

    /// The page came into view. Each `begin` is paired with an `end`.
    func begin() {
        dispatchPrecondition(condition: .onQueue(.main))
        viewers += 1
        if viewers == 1 { refresh() }
    }

    func end() {
        dispatchPrecondition(condition: .onQueue(.main))
        viewers = max(0, viewers - 1)
        if viewers == 0 { next?.cancel(); next = nil }
    }

    /// The feature went away; nothing reads until the page opens again.
    func stop() {
        viewers = 0
        next?.cancel()
        next = nil
    }

    func refresh() {
        dispatchPrecondition(condition: .onQueue(.main))
        next?.cancel()
        next = nil
        guard !reading else { return }
        reading = true
        queue.async { [weak self] in
            guard let self else { return }
            let docker = self.readDocker()
            let ollama = self.readOllama()
            DispatchQueue.main.async {
                self.reading = false
                if self.docker != docker.state { self.docker = docker.state }
                if self.containers != docker.containers { self.containers = docker.containers }
                if self.ollama != ollama.state { self.ollama = ollama.state }
                if self.models != ollama.models { self.models = ollama.models }
                self.scheduleNext()
            }
        }
    }

    private func scheduleNext() {
        guard viewers > 0 else { return }
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        next = work
        DispatchQueue.main.asyncAfter(deadline: .now() + NotchWorkloadSupport.interval, execute: work)
    }

    /// `docker stop`: the container gets its usual grace period to shut down.
    func stop(_ container: NotchDockerContainer) {
        guard NotchWorkloadSupport.isContainerID(container.id), let cli = dockerCLI(),
              stopping.insert(container.id).inserted else { return }
        actions.async { [weak self] in
            let result = Shell.run(cli, ["stop", container.id], timeout: 30)
            DispatchQueue.main.async {
                guard let self else { return }
                self.stopping.remove(container.id)
                if result.status != 0 { NSSound.beep() }
                self.refresh()
            }
        }
    }

    /// Unloads the model, as `ollama stop` does. Ollama keeps running and
    /// loads it again the next time something asks for it.
    func unload(_ model: NotchOllamaModel) {
        guard stopping.insert(model.id).inserted else { return }
        actions.async { [weak self] in
            var ok = Self.post("api/generate", body: NotchWorkloadSupport.unloadBody(model.name))
            // An embedding model cannot generate; its own endpoint unloads it.
            if !ok { ok = Self.post("api/embed", body: NotchWorkloadSupport.unloadBody(model.name)) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.stopping.remove(model.id)
                if !ok { NSSound.beep() }
                self.refresh()
            }
        }
    }

    // MARK: Reading

    private func dockerCLI() -> String? {
        NotchWorkloadSupport.dockerCandidates(home: home).first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func readDocker() -> (state: NotchWorkloadState, containers: [NotchDockerContainer]) {
        guard let cli = dockerCLI() else { return (.missing, []) }
        let ps = Shell.run(cli, ["ps", "--no-trunc", "--format", "{{json .}}"], timeout: 5)
        // The CLI is there but its engine is not: Docker Desktop quit, or
        // Colima stopped.
        guard ps.status == 0 else { return (.stopped, []) }
        let containers = NotchWorkloadSupport.containers(ps: ps.output)
        guard !containers.isEmpty else { return (.running, []) }
        let stats = Shell.run(cli, ["stats", "--no-stream", "--no-trunc", "--format", "{{json .}}"], timeout: 10)
        let memory = stats.status == 0 ? NotchWorkloadSupport.memory(stats: stats.output) : [:]
        return (.running, NotchWorkloadSupport.merge(containers, memory: memory))
    }

    private func readOllama() -> (state: NotchWorkloadState, models: [NotchOllamaModel]) {
        if let data = Self.get("api/ps"), let models = NotchWorkloadSupport.models(ps: data) {
            return (.running, models)
        }
        let installed = NotchWorkloadSupport.ollamaCandidates(home: home).contains {
            FileManager.default.fileExists(atPath: $0)
        }
        return (installed ? .stopped : .missing, [])
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 5
        configuration.connectionProxyDictionary = [:]
        return URLSession(configuration: configuration)
    }()

    private static func get(_ path: String) -> Data? {
        send(URLRequest(url: NotchWorkloadSupport.ollamaURL.appending(path: path)))
    }

    private static func post(_ path: String, body: Data) -> Bool {
        var request = URLRequest(url: NotchWorkloadSupport.ollamaURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 10
        return send(request) != nil
    }

    /// The body of a successful answer. Called off the main thread only.
    private static func send(_ request: URLRequest) -> Data? {
        let done = DispatchSemaphore(value: 0)
        var body: Data?
        session.dataTask(with: request) { data, response, _ in
            if let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) { body = data ?? Data() }
            done.signal()
        }.resume()
        done.wait()
        return body
    }
}
