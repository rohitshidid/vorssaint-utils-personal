// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CryptoKit
import Foundation
import Network

/// A shared file as the server knows it.
struct NotchLinkRoute {
    let id: UUID
    let token: String
    let name: String
    let file: URL
    let size: UInt64
    var expiresAt: Date?
    var oneDownload: Bool
    var password: NotchLinkPassword?
}

/// What happens to the files the server hands out.
enum NotchLinkServerEvent {
    case began(connection: UUID, link: UUID, total: UInt64)
    case progress(connection: UUID, sent: UInt64)
    /// `finished` when the bytes reached the end of the file.
    case ended(connection: UUID, link: UUID, finished: Bool)
    /// A link for one download that just gave it.
    case spent(link: UUID)
}

/// Serves dropped files to the tunnel on this Mac's loopback interface only,
/// so nothing on the network reaches it except through the tunnel. It
/// answers a link's page and its download, and nothing else: no listing, no
/// other path, every response closing its connection.
final class NotchLinkServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.vorssaint.links.server", qos: .userInitiated)
    private var listener: NWListener?
    private var routes: [String: NotchLinkRoute] = [:]
    private var attempts: [String: Int] = [:]
    private var open: [ObjectIdentifier: NWConnection] = [:]
    private var strings: NotchLinkStrings
    private var language: String
    private var locale: Locale
    /// Signs the cookie a right password leaves; new each time the server starts.
    private let secret = SymmetricKey(size: .bits256)
    private let events: (NotchLinkServerEvent) -> Void

    /// A connection that sends no request in this long is closed.
    private static let idleTimeout: TimeInterval = 20
    private static let maximumConnections = 64
    private static let progressInterval: TimeInterval = 0.25

    init(strings: NotchLinkStrings, language: AppLanguage, events: @escaping (NotchLinkServerEvent) -> Void) {
        self.strings = strings
        self.language = language.rawValue
        locale = language.formattingLocale()
        self.events = events
    }

    /// Calls back on the main queue with the port, or nil when it could not listen.
    func start(_ ready: @escaping (UInt16?) -> Void) {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        guard let listener = try? NWListener(using: parameters) else {
            DispatchQueue.main.async { ready(nil) }
            return
        }
        var answered = false
        let answer: (UInt16?) -> Void = { port in
            guard !answered else { return }
            answered = true
            DispatchQueue.main.async { ready(port) }
        }
        listener.stateUpdateHandler = { [weak listener] state in
            switch state {
            case .ready: answer(listener?.port?.rawValue)
            case .failed, .cancelled: answer(nil)
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        self.listener = listener
        listener.start(queue: queue)
    }

    func stop() {
        queue.async { [self] in
            listener?.cancel()
            listener = nil
            routes = [:]
            // A download under way ends with its link.
            open.values.forEach { $0.cancel() }
            open = [:]
        }
    }

    func update(_ routes: [NotchLinkRoute], strings: NotchLinkStrings, language: AppLanguage) {
        let locale = language.formattingLocale()
        queue.async { [self] in
            self.routes = Dictionary(routes.map { ($0.token, $0) }, uniquingKeysWith: { first, _ in first })
            attempts = attempts.filter { self.routes[$0.key] != nil }
            self.strings = strings
            self.language = language.rawValue
            self.locale = locale
        }
    }

    // MARK: Connections

    private func accept(_ connection: NWConnection) {
        guard listener != nil, open.count < Self.maximumConnections else { connection.cancel(); return }
        let key = ObjectIdentifier(connection)
        open[key] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed: self?.open[key]?.cancel()
            case .cancelled: self?.open[key] = nil
            default: break
            }
        }
        connection.start(queue: queue)
        let idle = DispatchWorkItem { [weak connection] in connection?.cancel() }
        queue.asyncAfter(deadline: .now() + Self.idleTimeout, execute: idle)
        readHead(connection, buffer: Data(), idle: idle)
    }

    private func readHead(_ connection: NWConnection, buffer: Data, idle: DispatchWorkItem) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: NotchLinkSupport.maximumHead) { [weak self] data, _, complete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                idle.cancel()
                let rest = buffer[end.upperBound...]
                guard let request = NotchLinkSupport.request(head: buffer[..<end.lowerBound]) else {
                    self.respond(connection, status: 400, body: Data())
                    return
                }
                self.readBody(connection, request: request, body: Data(rest))
            } else if buffer.count >= NotchLinkSupport.maximumHead || complete || error != nil {
                idle.cancel()
                connection.cancel()
            } else {
                self.readHead(connection, buffer: buffer, idle: idle)
            }
        }
    }

    private func readBody(_ connection: NWConnection, request: NotchLinkRequest, body: Data) {
        let length = request.contentLength
        guard length <= NotchLinkSupport.maximumBody else {
            respond(connection, status: 413, body: Data())
            return
        }
        guard body.count < length else {
            handle(request, body: body.prefix(length), on: connection)
            return
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: length - body.count) { [weak self] data, _, complete, error in
            guard let self else { return }
            var body = body
            if let data { body.append(data) }
            if body.count >= length { self.handle(request, body: body, on: connection) }
            else if complete || error != nil { connection.cancel() }
            else { self.readBody(connection, request: request, body: body) }
        }
    }

    // MARK: Requests

    private func handle(_ request: NotchLinkRequest, body: Data, on connection: NWConnection) {
        let route = NotchLinkSupport.route(request.path)
        let token: String
        switch route {
        case .robots:
            respond(connection, status: 200, body: Data("User-agent: *\nDisallow: /\n".utf8),
                    type: "text/plain; charset=utf-8", method: request.method)
            return
        case .unknown:
            respondPage(connection, .ended, status: 404, method: request.method)
            return
        case let .page(value), let .download(value):
            token = value
        }
        guard let link = routes[token] else {
            respondPage(connection, .ended, status: 404, method: request.method)
            return
        }
        if let end = link.expiresAt, end <= Date() {
            routes[token] = nil
            respondPage(connection, .ended, status: 410, method: request.method)
            return
        }
        let unlocked = link.password == nil
            || request.cookies[NotchLinkSupport.cookieName(token)] == NotchLinkSupport.pass(token: token, secret: secret)
        let size = NotchLinkSupport.size(link.size)
        switch (route, request.method) {
        case (.page, "POST"):
            guard let password = link.password else {
                redirect(connection, to: "/\(token)", cookie: nil)
                return
            }
            let tries = attempts[token, default: 0]
            guard tries < NotchLinkSupport.maximumAttempts else {
                respondPage(connection, .tooManyAttempts, status: 429, method: request.method)
                return
            }
            if password.matches(NotchLinkSupport.formValue("password", in: body) ?? "") {
                attempts[token] = 0
                let cookie = "\(NotchLinkSupport.cookieName(token))=\(NotchLinkSupport.pass(token: token, secret: secret)); "
                    + "Path=/\(token); Max-Age=86400; HttpOnly; Secure; SameSite=Lax"
                redirect(connection, to: "/\(token)", cookie: cookie)
            } else {
                attempts[token] = tries + 1
                let page: NotchLinkPage = tries + 1 >= NotchLinkSupport.maximumAttempts ? .tooManyAttempts
                    : .password(name: link.name, size: size, error: strings.pageWrongPassword)
                respondPage(connection, page, status: 401, method: request.method)
            }
        case (.page, "GET"), (.page, "HEAD"):
            guard unlocked else {
                respondPage(connection, attempts[token, default: 0] >= NotchLinkSupport.maximumAttempts
                                ? .tooManyAttempts : .password(name: link.name, size: size, error: nil),
                            status: 200, method: request.method)
                return
            }
            respondPage(connection, .download(token: token, name: link.name, size: size,
                                              availability: availability(link)),
                        status: 200, method: request.method)
        case (.download, "GET"), (.download, "HEAD"):
            guard unlocked else {
                redirect(connection, to: "/\(token)", cookie: nil)
                return
            }
            send(link, request: request, on: connection)
        default:
            respond(connection, status: 405, body: Data(), extra: [("Allow", "GET, HEAD, POST")])
        }
    }

    private func availability(_ link: NotchLinkRoute) -> String {
        if link.oneDownload { return strings.pageOneDownload }
        guard let end = link.expiresAt else { return strings.pageUntilStopped }
        return strings.pageAvailable(NotchLinkSupport.timeLeft(until: end, now: Date(), locale: locale))
    }

    private func send(_ link: NotchLinkRoute, request: NotchLinkRequest, on connection: NWConnection) {
        let range = NotchLinkSupport.range(request.header("range"), size: link.size)
        let span: ClosedRange<UInt64>?
        switch range {
        case .unsatisfiable:
            respond(connection, status: 416, body: Data(), extra: [("Content-Range", "bytes */\(link.size)")])
            return
        case .whole: span = link.size > 0 ? 0...(link.size - 1) : nil
        case let .part(part): span = part
        }
        guard let handle = try? FileHandle(forReadingFrom: link.file) else {
            routes[link.token] = nil
            respondPage(connection, .ended, status: 410, method: request.method)
            return
        }
        let length = span.map { $0.upperBound - $0.lowerBound + 1 } ?? 0
        var headers: [(String, String)] = [
            ("Content-Type", "application/octet-stream"),
            ("Content-Length", String(length)),
            ("Content-Disposition", NotchLinkSupport.contentDisposition(link.name)),
            ("Accept-Ranges", "bytes"),
        ]
        if case let .part(part) = range {
            headers.append(("Content-Range", "bytes \(part.lowerBound)-\(part.upperBound)/\(link.size)"))
        }
        var status = 200
        if case .part = range { status = 206 }
        let head = NotchLinkSupport.head(status: status, headers: headers)
        guard request.method == "GET", let span else {
            try? handle.close()
            finish(connection, head)
            return
        }
        do { try handle.seek(toOffset: span.lowerBound) } catch {
            try? handle.close()
            connection.cancel()
            return
        }
        let id = UUID()
        let reachesEnd = span.upperBound == link.size - 1
        let linkID = link.id, token = link.token, oneDownload = link.oneDownload
        events(.began(connection: id, link: linkID, total: link.size))
        // The share of the file sent so far counts from where this part
        // starts, so a resumed download picks up its progress where it was.
        let transfer = Transfer(id: id, handle: handle, remaining: length, sent: span.lowerBound, lastReport: .distantPast)
        connection.send(content: head, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            guard error == nil else { self.end(transfer, link: linkID, finished: false, connection: connection); return }
            self.stream(transfer, on: connection) { finished in
                let finished = finished && reachesEnd
                self.end(transfer, link: linkID, finished: finished, connection: connection)
                guard finished, oneDownload, self.routes[token] != nil else { return }
                // A link for one download stops answering the moment it gave it.
                self.routes[token] = nil
                self.events(.spent(link: linkID))
            }
        })
    }

    private final class Transfer {
        let id: UUID
        let handle: FileHandle
        var remaining: UInt64
        var sent: UInt64
        var lastReport: Date

        init(id: UUID, handle: FileHandle, remaining: UInt64, sent: UInt64, lastReport: Date) {
            self.id = id
            self.handle = handle
            self.remaining = remaining
            self.sent = sent
            self.lastReport = lastReport
        }
    }

    /// One chunk at a time, the next read only once the last has gone out,
    /// so a slow recipient never fills memory with a file.
    private func stream(_ transfer: Transfer, on connection: NWConnection, done: @escaping (Bool) -> Void) {
        guard transfer.remaining > 0 else { done(true); return }
        let count = Int(min(UInt64(NotchLinkSupport.chunkSize), transfer.remaining))
        guard let chunk = try? transfer.handle.read(upToCount: count), !chunk.isEmpty else { done(false); return }
        connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            guard error == nil else { done(false); return }
            transfer.remaining -= UInt64(chunk.count)
            transfer.sent += UInt64(chunk.count)
            let now = Date()
            if now.timeIntervalSince(transfer.lastReport) >= Self.progressInterval {
                transfer.lastReport = now
                self.events(.progress(connection: transfer.id, sent: transfer.sent))
            }
            self.stream(transfer, on: connection, done: done)
        })
    }

    private func end(_ transfer: Transfer, link: UUID, finished: Bool, connection: NWConnection) {
        try? transfer.handle.close()
        events(.ended(connection: transfer.id, link: link, finished: finished))
        if finished { close(connection) } else { connection.cancel() }
    }

    // MARK: Responses

    private func respondPage(_ connection: NWConnection, _ page: NotchLinkPage, status: Int, method: String) {
        let html = NotchLinkSupport.page(page, strings: strings, language: language)
        respond(connection, status: status, body: Data(html.utf8), type: "text/html; charset=utf-8", method: method,
                extra: [("Content-Security-Policy", NotchLinkSupport.pagePolicy)])
    }

    private func redirect(_ connection: NWConnection, to path: String, cookie: String?) {
        var headers = [("Location", path), ("Content-Length", "0")]
        if let cookie { headers.append(("Set-Cookie", cookie)) }
        finish(connection, NotchLinkSupport.head(status: 303, headers: headers))
    }

    private func respond(_ connection: NWConnection, status: Int, body: Data, type: String? = nil,
                         method: String = "GET", extra: [(String, String)] = []) {
        var headers = [("Content-Length", String(body.count))]
        if let type { headers.append(("Content-Type", type)) }
        headers += extra
        var data = NotchLinkSupport.head(status: status, headers: headers)
        if method != "HEAD" { data.append(body) }
        finish(connection, data)
    }

    private func finish(_ connection: NWConnection, _ data: Data) {
        connection.send(content: data, completion: .contentProcessed { [weak self] _ in self?.close(connection) })
    }

    private func close(_ connection: NWConnection) {
        connection.send(content: nil, contentContext: .finalMessage, isComplete: true,
                        completion: .contentProcessed { _ in connection.cancel() })
    }
}
