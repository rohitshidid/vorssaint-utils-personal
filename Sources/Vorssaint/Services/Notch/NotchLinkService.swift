// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import IOKit.pwr_mgt

/// A file shared by link, while it lasts.
struct NotchLink: Identifiable, Equatable {
    enum Phase: Equatable {
        /// A folder or several files are being put in one archive.
        case preparing
        case ready
    }

    let id: UUID
    let token: String
    let name: String
    var file: URL?
    var size: UInt64
    var expiresAt: Date?
    let oneDownload: Bool
    var password: NotchLinkPassword?
    var downloads = 0
    /// The furthest an ongoing download has come, nil while none runs.
    var progress: Double?
    var phase: Phase
}

enum NotchLinkTunnelState: Equatable {
    case off
    /// cloudflared is not installed.
    case missing
    case installing
    case starting
    case ready(URL)
    case failed
}

/// Shares dropped files through a Cloudflare quick tunnel. The files stay on
/// this Mac: a server on the loopback interface hands them to cloudflared,
/// which gives the tunnel a random public address. Nothing outlives the
/// links. The last one to end takes the tunnel, the server and the Mac's
/// wakefulness with it, and quitting ends them all.
final class NotchLinkService: ObservableObject {
    static let shared = NotchLinkService()

    @Published private(set) var links: [NotchLink] = [] {
        didSet { syncRoutes() }
    }
    @Published private(set) var tunnel: NotchLinkTunnelState = .off
    /// The link whose address was just copied, which says so for a moment.
    @Published private(set) var copiedID: UUID?
    @Published var expiry: NotchLinkExpiry {
        didSet { UserDefaults.standard.set(expiry.rawValue, forKey: DefaultsKey.notchLinkExpiry) }
    }

    private var server: NotchLinkServer?
    private var port: UInt16?
    private var process: Process?
    /// Each start of the tunnel; whatever an earlier one reports is ignored.
    private var attempt = UUID()
    private var log = ""
    private var tunnelURL: URL?
    private var connected = false
    private var resolving = false
    private var pendingCopy: UUID?
    private var transfers: [UUID: (link: UUID, sent: UInt64, total: UInt64)] = [:]
    private var archives: [UUID: NotchArchiveOperation] = [:]
    private var expiryWork: DispatchWorkItem?
    private var copiedWork: DispatchWorkItem?
    private var assertion: IOPMAssertionID?
    private var cleanedUp = false
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 8
        return URLSession(configuration: configuration)
    }()

    /// How long cloudflared has to give an address before it counts as failed.
    private static let startTimeout: TimeInterval = 45
    /// Tries at the public resolver, a second apart, before the link is
    /// handed out anyway.
    private static let resolveTries = 15

    private init() {
        expiry = NotchLinkExpiry.stored(UserDefaults.standard.string(forKey: DefaultsKey.notchLinkExpiry))
    }

    private var strings: NotchLinkStrings { FeatureStrings.notchLinks(L10n.shared.language) }

    var isActive: Bool { !links.isEmpty }

    /// The soonest end among the links that have one.
    var nextEnd: Date? { links.compactMap(\.expiresAt).min() }

    /// The furthest any download has come, while one runs.
    var progress: Double? { links.compactMap(\.progress).max() }

    func url(for link: NotchLink) -> URL? {
        guard link.phase == .ready, case let .ready(base) = tunnel else { return nil }
        return NotchLinkSupport.link(base: base, token: link.token)
    }

    // MARK: Dropping

    /// The island's Get link destination, beside the shelf's.
    var offersDrop: Bool {
        AppFeature.notchLinks.isAvailable && NotchSupport.isEnabled()
            && NotchSupport.modules().contains(.links)
    }

    var canAcceptDrop: Bool { offersDrop && tunnel != .installing }

    /// Files only: text, links and promised files stay with the shelf.
    func linkDropContent(for pasteboard: NSPasteboard) -> [URL]? {
        guard offersDrop,
              !pasteboard.canReadObject(forClasses: [NSFilePromiseReceiver.self], options: nil) else { return nil }
        let urls = ShelfService.shared.fileURLs(from: pasteboard)
        guard !urls.isEmpty, urls.count >= (pasteboard.pasteboardItems?.count ?? 0) else { return nil }
        return urls
    }

    func shareDrop(_ pasteboard: NSPasteboard) -> Bool {
        guard canAcceptDrop, let urls = linkDropContent(for: pasteboard) else { return false }
        return share(urls)
    }

    // MARK: Sharing

    @discardableResult
    func share(_ urls: [URL]) -> Bool {
        let urls = urls.filter(\.isFileURL).map { $0.resolvingSymlinksInPath() }
        guard AppFeature.notchLinks.isAvailable, !urls.isEmpty else { return false }
        cleanUpOnce()
        let values = urls.count == 1
            ? try? urls[0].resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) : nil
        let single = values?.isRegularFile == true
        var link = NotchLink(id: UUID(), token: NotchLinkSupport.newToken(),
                             name: single ? urls[0].lastPathComponent : NotchLinkSupport.archiveName(for: urls),
                             file: single ? urls[0] : nil, size: UInt64(max(0, values?.fileSize ?? 0)),
                             expiresAt: expiry.duration.map { Date().addingTimeInterval($0) },
                             oneDownload: expiry == .oneDownload, password: nil,
                             phase: single ? .ready : .preparing)
        if !single { pack(urls, for: &link) }
        links.insert(link, at: 0)
        pendingCopy = link.id
        ensureTunnel()
        syncPower()
        scheduleExpiry()
        copyPendingLink()
        return true
    }

    /// A folder, or several files gathered in one, as a zip archive in a
    /// folder of the link's own that goes when the link does.
    private func pack(_ urls: [URL], for link: inout NotchLink) {
        let id = link.id
        let name = link.name
        let folder = Self.temporaryRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        let operation = NotchArchiveOperation()
        archives[id] = operation
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let output = folder.appendingPathComponent(name)
            var result: URL?
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                if urls.count == 1 {
                    try operation.archive(urls[0], to: output)
                } else {
                    // Clones on the same volume, so even large files take no
                    // time or space until the archive is made.
                    let stage = folder.appendingPathComponent("stage", isDirectory: true)
                        .appendingPathComponent((name as NSString).deletingPathExtension, isDirectory: true)
                    try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
                    for (url, staged) in zip(urls, NotchLinkSupport.stagedNames(for: urls)) {
                        try FileManager.default.copyItem(at: url, to: stage.appendingPathComponent(staged))
                    }
                    try operation.archive(stage, to: output)
                    try? FileManager.default.removeItem(at: stage.deletingLastPathComponent())
                }
                result = output
            } catch {
                try? FileManager.default.removeItem(at: folder)
            }
            let size = result.flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize } ?? 0
            DispatchQueue.main.async { self?.packed(id, file: result, size: UInt64(max(0, size))) }
        }
    }

    private func packed(_ id: UUID, file: URL?, size: UInt64) {
        archives[id] = nil
        guard let index = links.firstIndex(where: { $0.id == id }) else {
            if let file { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
            return
        }
        guard let file else {
            NSSound.beep()
            stop(id)
            return
        }
        links[index].file = file
        links[index].size = size
        links[index].phase = .ready
        copyPendingLink()
    }

    func stop(_ id: UUID) {
        guard let index = links.firstIndex(where: { $0.id == id }) else { return }
        let link = links.remove(at: index)
        archives.removeValue(forKey: id)?.cancel()
        discardFiles(of: link)
        transfers = transfers.filter { $0.value.link != id }
        if pendingCopy == id { pendingCopy = nil }
        if links.isEmpty { shutDown() } else { scheduleExpiry() }
    }

    func stopAll() {
        links.map(\.id).forEach(stop)
        shutDown()
    }

    /// The feature leaving, or the app quitting, ends every link at once.
    func stop() {
        archives.values.forEach { $0.cancel(immediately: true) }
        archives = [:]
        let ended = links
        links = []
        ended.forEach(discardFiles)
        pendingCopy = nil
        shutDown()
    }

    func syncWithPreferences() {
        guard AppFeature.notchLinks.isAvailable, NotchSupport.isEnabled() else {
            stop()
            return
        }
        cleanUpOnce()
    }

    func extend(_ id: UUID, by choice: NotchLinkExpiry) {
        guard let index = links.firstIndex(where: { $0.id == id }), links[index].expiresAt != nil else { return }
        links[index].expiresAt = choice == .untilStopped ? nil
            : NotchLinkSupport.extended(links[index].expiresAt, by: choice, now: Date())
        scheduleExpiry()
    }

    func setPassword(_ password: String?, for id: UUID) {
        guard let index = links.firstIndex(where: { $0.id == id }) else { return }
        let password = password?.trimmingCharacters(in: .newlines)
        links[index].password = password.flatMap { $0.isEmpty ? nil : NotchLinkPassword($0) }
    }

    func copy(_ id: UUID) {
        guard let link = links.first(where: { $0.id == id }), let url = url(for: link) else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(url.absoluteString, forType: .string)
        copiedID = id
        copiedWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.copiedID = nil }
        copiedWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    /// The newest link goes on the clipboard as soon as it works.
    private func copyPendingLink() {
        guard let id = pendingCopy, let link = links.first(where: { $0.id == id }), url(for: link) != nil else { return }
        pendingCopy = nil
        copy(id)
        NotchService.shared.showLinkNotice(strings.copied, detail: link.name, symbol: "link")
    }

    // MARK: Tunnel

    private var cloudflaredPath: String? {
        NotchLinkSupport.cloudflaredCandidates(home: NSHomeDirectory())
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private var brewPath: String? {
        HomebrewCommandBuilder.candidatePaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    var canInstall: Bool { brewPath != nil }

    func retry() {
        guard !links.isEmpty else { return }
        endTunnel()
        tunnel = .off
        ensureTunnel()
    }

    private func ensureTunnel() {
        guard !links.isEmpty else { return }
        switch tunnel {
        case .starting, .ready, .installing: return
        case .off, .missing, .failed: break
        }
        guard let cloudflared = cloudflaredPath else {
            tunnel = .missing
            return
        }
        tunnel = .starting
        let current = UUID()
        attempt = current
        startServer { [weak self] port in
            guard let self, self.attempt == current else { return }
            guard let port else { self.tunnel = .failed; return }
            self.launch(cloudflared, port: port, attempt: current)
        }
    }

    private func startServer(_ ready: @escaping (UInt16?) -> Void) {
        if server != nil, let port {
            ready(port)
            return
        }
        let server = NotchLinkServer(strings: strings, language: L10n.shared.language) { [weak self] event in
            DispatchQueue.main.async { self?.handle(event) }
        }
        self.server = server
        server.start { [weak self] port in
            guard let self, self.server === server else { return }
            self.port = port
            if port == nil { self.server = nil } else { self.syncRoutes() }
            ready(port)
        }
    }

    private func launch(_ cloudflared: String, port: UInt16, attempt current: UUID) {
        endOrphanedTunnel()
        guard let config = Self.configURL() else {
            tunnel = .failed
            return
        }
        log = ""
        tunnelURL = nil
        connected = false
        resolving = false
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cloudflared)
        process.arguments = NotchLinkSupport.tunnelArguments(port: port, config: config.path)
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async { self?.tunnelLogged(text, attempt: current) }
        }
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.tunnelExited(attempt: current) }
        }
        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            tunnel = .failed
            return
        }
        self.process = process
        UserDefaults.standard.set(Int(process.processIdentifier), forKey: DefaultsKey.notchLinkTunnelPID)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.startTimeout) { [weak self] in
            guard let self, self.attempt == current, self.tunnel == .starting else { return }
            self.endTunnel()
            self.tunnel = .failed
        }
    }

    private func tunnelLogged(_ text: String, attempt current: UUID) {
        guard attempt == current, tunnel == .starting else { return }
        // The address and the first connection come in the first lines;
        // the rest of the log is not kept.
        log = String((log + text).suffix(16 * 1024))
        if tunnelURL == nil { tunnelURL = NotchLinkSupport.tunnelURL(in: log) }
        if !connected { connected = NotchLinkSupport.tunnelIsConnected(log) }
        guard let url = tunnelURL, connected, !resolving else { return }
        resolving = true
        resolve(url, attempt: current, tries: 0)
    }

    /// A brand-new address takes a moment to resolve. Handing it out before
    /// then would have the recipient's resolver remember that it does not
    /// exist, so the link waits until Cloudflare's own resolver knows it.
    private func resolve(_ url: URL, attempt current: UUID, tries: Int) {
        guard let host = url.host, let query = NotchLinkSupport.resolverURL(host: host) else {
            ready(url, attempt: current)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (tries == 0 ? 1.5 : 1)) { [weak self] in
            guard let self, self.attempt == current, self.tunnel == .starting else { return }
            var request = URLRequest(url: query)
            request.setValue("application/dns-json", forHTTPHeaderField: "Accept")
            self.session.dataTask(with: request) { data, _, _ in
                let resolved = data.map(NotchLinkSupport.resolves) ?? false
                DispatchQueue.main.async {
                    guard self.attempt == current, self.tunnel == .starting else { return }
                    if resolved || tries + 1 >= Self.resolveTries { self.ready(url, attempt: current) }
                    else { self.resolve(url, attempt: current, tries: tries + 1) }
                }
            }.resume()
        }
    }

    private func ready(_ url: URL, attempt current: UUID) {
        guard attempt == current else { return }
        tunnel = .ready(url)
        copyPendingLink()
    }

    private func tunnelExited(attempt current: UUID) {
        guard attempt == current else { return }
        process = nil
        UserDefaults.standard.removeObject(forKey: DefaultsKey.notchLinkTunnelPID)
        tunnel = links.isEmpty ? .off : .failed
    }

    private func endTunnel() {
        attempt = UUID()
        if let process, process.isRunning {
            process.terminate()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
        process = nil
        UserDefaults.standard.removeObject(forKey: DefaultsKey.notchLinkTunnelPID)
    }

    /// A tunnel left running by a copy of the app that did not quit
    /// properly serves nothing; it goes before a new one starts.
    private func endOrphanedTunnel() {
        let pid = pid_t(UserDefaults.standard.integer(forKey: DefaultsKey.notchLinkTunnelPID))
        UserDefaults.standard.removeObject(forKey: DefaultsKey.notchLinkTunnelPID)
        guard pid > 0, pid != process?.processIdentifier else { return }
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0,
              String(cString: path).hasSuffix("/cloudflared") else { return }
        kill(pid, SIGTERM)
    }

    private func shutDown() {
        endTunnel()
        server?.stop()
        server = nil
        port = nil
        transfers = [:]
        expiryWork?.cancel()
        expiryWork = nil
        if tunnel != .installing { tunnel = .off }
        syncPower()
    }

    // MARK: cloudflared

    func installCloudflared() {
        guard let brew = brewPath else {
            NSWorkspace.shared.open(NotchLinkSupport.cloudflaredDownload)
            return
        }
        guard tunnel == .missing else { return }
        tunnel = .installing
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: brew)
            process.arguments = ["install", "cloudflared"]
            process.environment = HomebrewEnvironment.forBrew
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            let finished = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in finished.signal() }
            if (try? process.run()) != nil, finished.wait(timeout: .now() + 900) == .timedOut {
                process.terminate()
            }
            DispatchQueue.main.async {
                guard let self, self.tunnel == .installing else { return }
                self.tunnel = .off
                if self.links.isEmpty { return }
                self.ensureTunnel()
                if self.tunnel == .missing { NSSound.beep() }
            }
        }
    }

    // MARK: Server

    private func syncRoutes() {
        let routes = links.compactMap { link -> NotchLinkRoute? in
            guard link.phase == .ready, let file = link.file else { return nil }
            return NotchLinkRoute(id: link.id, token: link.token, name: link.name, file: file, size: link.size,
                                  expiresAt: link.expiresAt, oneDownload: link.oneDownload, password: link.password)
        }
        server?.update(routes, strings: strings, language: L10n.shared.language)
    }

    private func handle(_ event: NotchLinkServerEvent) {
        switch event {
        case let .began(connection, link, total):
            transfers[connection] = (link, 0, total)
            updateProgress(of: link)
        case let .progress(connection, sent):
            guard let transfer = transfers[connection] else { return }
            transfers[connection]?.sent = sent
            updateProgress(of: transfer.link)
        case let .ended(connection, link, finished):
            transfers[connection] = nil
            updateProgress(of: link)
            guard finished, let index = links.firstIndex(where: { $0.id == link }) else { return }
            links[index].downloads += 1
            NotchService.shared.showLinkNotice(strings.downloaded, detail: links[index].name, symbol: "arrow.down.circle.fill")
        case let .spent(link):
            // The notice of its download shows first.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.stop(link) }
        }
    }

    private func updateProgress(of id: UUID) {
        guard let index = links.firstIndex(where: { $0.id == id }) else { return }
        let fractions = transfers.values.filter { $0.link == id && $0.total > 0 }
            .map { min(1, Double($0.sent) / Double($0.total)) }
        let progress = fractions.max()
        // Whole percents are all the island shows.
        if progress.map({ ($0 * 100).rounded(.down) }) != links[index].progress.map({ ($0 * 100).rounded(.down) }) {
            links[index].progress = progress
        }
    }

    // MARK: Time and power

    private func scheduleExpiry() {
        expiryWork?.cancel()
        expiryWork = nil
        guard let next = nextEnd else { return }
        let work = DispatchWorkItem { [weak self] in self?.endExpired() }
        expiryWork = work
        DispatchQueue.main.asyncAfter(wallDeadline: .now() + max(0, next.timeIntervalSinceNow) + 0.2, execute: work)
    }

    private func endExpired() {
        let now = Date()
        links.filter { $0.expiresAt.map { $0 <= now } ?? false }.map(\.id).forEach(stop)
        scheduleExpiry()
    }

    /// A sleeping Mac serves nothing, so it stays awake while a link lasts;
    /// the display can still sleep.
    private func syncPower() {
        if links.isEmpty {
            if let assertion { IOPMAssertionRelease(assertion) }
            assertion = nil
        } else if assertion == nil {
            var id = IOPMAssertionID(0)
            if IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleSystemSleep as CFString,
                                           IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                           strings.awake as CFString, &id) == kIOReturnSuccess {
                assertion = id
            }
        }
    }

    // MARK: Files

    private static var temporaryRoot: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("VorssaintLinks", isDirectory: true)
    }

    /// cloudflared's own configuration, which holds nothing but its updates
    /// turned off, so nothing in ~/.cloudflared is ever read.
    private static func configURL() -> URL? {
        let url = temporaryRoot.appendingPathComponent("cloudflared.yml")
        do {
            try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
            try Data(NotchLinkSupport.tunnelConfig.utf8).write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private func discardFiles(of link: NotchLink) {
        guard let file = link.file, file.path.hasPrefix(Self.temporaryRoot.path + "/") else { return }
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }

    /// Archives from an earlier run, and its tunnel if it is still up.
    private func cleanUpOnce() {
        guard !cleanedUp else { return }
        cleanedUp = true
        endOrphanedTunnel()
        guard links.isEmpty else { return }
        try? FileManager.default.removeItem(at: Self.temporaryRoot)
    }
}
