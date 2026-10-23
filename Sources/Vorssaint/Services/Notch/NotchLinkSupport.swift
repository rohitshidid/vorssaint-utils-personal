// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CryptoKit

/// How long a new link lasts. A link for one download also ends after a day,
/// so one nobody opens does not keep the Mac awake for good.
enum NotchLinkExpiry: String, CaseIterable, Identifiable {
    case quarterHour, hour, fourHours, day, untilStopped, oneDownload

    var id: String { rawValue }

    var duration: TimeInterval? {
        switch self {
        case .quarterHour: return 15 * 60
        case .hour: return 3600
        case .fourHours: return 4 * 3600
        case .day, .oneDownload: return 24 * 3600
        case .untilStopped: return nil
        }
    }

    /// The ways a running link can be given more time.
    static let extensions: [NotchLinkExpiry] = [.quarterHour, .hour, .day, .untilStopped]

    static func stored(_ value: String?) -> NotchLinkExpiry {
        value.flatMap(NotchLinkExpiry.init(rawValue:)) ?? .hour
    }
}

/// A password the recipient types on the link's page. Only its salted hash
/// stays in memory, and only for as long as the link.
struct NotchLinkPassword: Equatable {
    let salt: Data
    let hash: Data

    init(_ password: String, salt: Data = NotchLinkSupport.randomBytes(16)) {
        self.salt = salt
        hash = Self.digest(password, salt: salt)
    }

    func matches(_ attempt: String) -> Bool {
        // Same length every time, so the comparison takes the same time.
        let candidate = Self.digest(attempt, salt: salt)
        return zip(candidate, hash).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0 && candidate.count == hash.count
    }

    private static func digest(_ password: String, salt: Data) -> Data {
        Data(SHA256.hash(data: salt + Data(password.utf8)))
    }
}

/// A request as the link server reads it, after its head.
struct NotchLinkRequest: Equatable {
    let method: String
    let path: String
    let headers: [String: String]

    func header(_ name: String) -> String? { headers[name.lowercased()] }

    var contentLength: Int {
        header("content-length").flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }.map { max(0, $0) } ?? 0
    }

    var cookies: [String: String] {
        var cookies: [String: String] = [:]
        for pair in (header("cookie") ?? "").split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            cookies[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1].trimmingCharacters(in: .whitespaces)
        }
        return cookies
    }
}

/// What a path on the link server asks for.
enum NotchLinkPath: Equatable {
    /// The link's own page: its name, size, time left and a download button.
    case page(token: String)
    case download(token: String)
    case robots
    case unknown
}

/// A requested part of the file, inclusive at both ends.
enum NotchLinkRange: Equatable {
    case whole
    case part(ClosedRange<UInt64>)
    case unsatisfiable
}

/// The recipient's page, in the sender's language.
enum NotchLinkPage: Equatable {
    case download(token: String, name: String, size: String, availability: String)
    case password(name: String, size: String, error: String?)
    case tooManyAttempts
    case ended
}

enum NotchLinkSupport {
    /// The longest request head the server reads before it hangs up.
    static let maximumHead = 16 * 1024
    static let maximumBody = 4 * 1024
    /// Wrong passwords a link takes before it refuses more.
    static let maximumAttempts = 10
    static let chunkSize = 256 * 1024
    static let symbol = "link"
    static let openSymbol = "infinity"

    static func cloudflaredCandidates(home: String) -> [String] {
        ["/opt/homebrew/bin/cloudflared", "/usr/local/bin/cloudflared", home + "/.local/bin/cloudflared"]
    }

    static let cloudflaredDownload = URL(string: "https://github.com/cloudflare/cloudflared/releases/latest")!

    /// Quick tunnels take no account or configuration. The tunnel gets one of
    /// its own that holds nothing, so a named tunnel the person set up in
    /// ~/.cloudflared is never read or started.
    static func tunnelArguments(port: UInt16, config: String) -> [String] {
        ["tunnel", "--config", config, "--no-autoupdate", "--url", "http://127.0.0.1:\(port)"]
    }

    static let tunnelConfig = "no-autoupdate: true\n"

    /// The quick tunnel's address, wherever cloudflared prints it in its log.
    static func tunnelURL(in log: String) -> URL? {
        guard let range = log.range(of: #"https://[a-z0-9-]+\.trycloudflare\.com"#, options: .regularExpression) else {
            return nil
        }
        return URL(string: String(log[range]))
    }

    /// The tunnel takes requests once one of its connections is up.
    static func tunnelIsConnected(_ log: String) -> Bool {
        log.contains("Registered tunnel connection")
    }

    /// Cloudflare's own resolver answers over HTTPS, so asking it never
    /// leaves an answer of "no such host" in the Mac's cache.
    static func resolverURL(host: String) -> URL? {
        var components = URLComponents(string: "https://cloudflare-dns.com/dns-query")
        components?.queryItems = [URLQueryItem(name: "name", value: host), URLQueryItem(name: "type", value: "A")]
        return components?.url
    }

    static func resolves(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (object["Status"] as? NSNumber)?.intValue == 0,
              let answers = object["Answer"] as? [[String: Any]] else { return false }
        return !answers.isEmpty
    }

    // MARK: Tokens

    static func randomBytes(_ count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }

    /// 128 random bits: a link nobody was given cannot be guessed.
    static func newToken() -> String { base64URL(randomBytes(16)) }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func isToken(_ text: Substring) -> Bool {
        text.count == 22 && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    static func link(base: URL, token: String) -> URL {
        base.appendingPathComponent(token)
    }

    /// What proves the password was given for this link, kept in a cookie.
    static func pass(token: String, secret: SymmetricKey) -> String {
        base64URL(Data(HMAC<SHA256>.authenticationCode(for: Data(token.utf8), using: secret)))
    }

    static func cookieName(_ token: String) -> String { "vl_" + token.prefix(8) }

    // MARK: Requests

    /// The request line and headers, up to the blank line that ends them.
    static func request(head: Data) -> NotchLinkRequest? {
        guard head.count <= maximumHead, let text = String(data: head, encoding: .utf8) else { return nil }
        var lines = text.components(separatedBy: "\r\n")
        let parts = lines.removeFirst().split(separator: " ")
        guard parts.count == 3, parts[2].hasPrefix("HTTP/1."), parts[1].hasPrefix("/") else { return nil }
        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { return nil }
            headers[line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()]
                = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let target = parts[1]
        let path = target.firstIndex(of: "?").map { target[..<$0] } ?? target
        return NotchLinkRequest(method: String(parts[0]), path: String(path), headers: headers)
    }

    static func route(_ path: String) -> NotchLinkPath {
        if path == "/robots.txt" { return .robots }
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard let token = parts.first, isToken(token) else { return .unknown }
        switch parts.count {
        case 1: return .page(token: String(token))
        case 2 where parts[1] == "download": return .download(token: String(token))
        default: return .unknown
        }
    }

    /// One range of bytes, which is all a browser or a resumed download
    /// asks for; several at once get the whole file.
    static func range(_ header: String?, size: UInt64) -> NotchLinkRange {
        guard let header = header?.trimmingCharacters(in: .whitespaces), header.hasPrefix("bytes="),
              !header.contains(",") else { return .whole }
        let spec = header.dropFirst("bytes=".count)
        guard let dash = spec.firstIndex(of: "-") else { return .whole }
        let first = spec[..<dash].trimmingCharacters(in: .whitespaces)
        let last = spec[spec.index(after: dash)...].trimmingCharacters(in: .whitespaces)
        if first.isEmpty {
            guard let suffix = UInt64(last) else { return .whole }
            guard suffix > 0, size > 0 else { return .unsatisfiable }
            return .part((size - min(suffix, size))...(size - 1))
        }
        guard let start = UInt64(first) else { return .whole }
        guard start < size else { return .unsatisfiable }
        // A range that does not parse is ignored, as if it were never asked for.
        let end = last.isEmpty ? size - 1 : UInt64(last).map { min($0, size - 1) }
        guard let end, end >= start else { return .whole }
        return start == 0 && end == size - 1 ? .whole : .part(start...end)
    }

    /// A form's field, as a browser sends it.
    static func formValue(_ name: String, in body: Data) -> String? {
        guard let text = String(data: body, encoding: .utf8) else { return nil }
        for pair in text.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0] == name else { continue }
            return parts[1].replacingOccurrences(of: "+", with: " ").removingPercentEncoding
        }
        return nil
    }

    // MARK: Responses

    static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 206: return "Partial Content"
        case 303: return "See Other"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 410: return "Gone"
        case 413: return "Payload Too Large"
        case 416: return "Range Not Satisfiable"
        case 429: return "Too Many Requests"
        default: return "Error"
        }
    }

    /// A response head. Every response closes its connection, and none is
    /// kept anywhere along the way.
    static func head(status: Int, headers: [(String, String)]) -> Data {
        var lines = ["HTTP/1.1 \(status) \(reason(status))"]
        lines += headers.map { "\($0.0): \($0.1)" }
        lines += ["Cache-Control: no-store", "X-Content-Type-Options: nosniff", "Referrer-Policy: no-referrer",
                  "X-Robots-Tag: noindex, nofollow", "Connection: close"]
        return Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
    }

    /// The file's name for the browser to save it under: plain ASCII for
    /// those that read nothing else, and the real name beside it.
    static func contentDisposition(_ name: String) -> String {
        let fallback = String(name.unicodeScalars.map { scalar -> Character in
            scalar.isASCII && scalar.value >= 0x20 && scalar.value != 0x7F && scalar != "\"" && scalar != "\\"
                ? Character(scalar) : "_"
        })
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let encoded = name.addingPercentEncoding(withAllowedCharacters: allowed) ?? fallback
        return "attachment; filename=\"\(fallback)\"; filename*=UTF-8''\(encoded)"
    }

    static func escapeHTML(_ text: String) -> String {
        var escaped = ""
        for character in text {
            switch character {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            case ">": escaped += "&gt;"
            case "\"": escaped += "&quot;"
            case "'": escaped += "&#39;"
            default: escaped.append(character)
            }
        }
        return escaped
    }

    /// The page holds no script and loads nothing; its policy says so too.
    static let pagePolicy = "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'"

    static func page(_ page: NotchLinkPage, strings: NotchLinkStrings, language: String) -> String {
        let body: String
        let title: String
        switch page {
        case let .download(token, name, size, availability):
            title = name
            body = """
            <div class="mark">↓</div>
            <h1>\(escapeHTML(name))</h1>
            <p class="meta">\(escapeHTML(size))</p>
            <a class="button" href="/\(escapeHTML(token))/download">\(escapeHTML(strings.pageDownload))</a>
            <p class="note">\(escapeHTML(availability))</p>
            """
        case let .password(name, size, error):
            title = name
            body = """
            <div class="mark">🔒</div>
            <h1>\(escapeHTML(name))</h1>
            <p class="meta">\(escapeHTML(size))</p>
            <form method="post" action="">
            <label for="password">\(escapeHTML(strings.pagePassword))</label>
            <input id="password" name="password" type="password" autocomplete="off" autofocus required>
            \(error.map { "<p class=\"error\">\(escapeHTML($0))</p>" } ?? "")
            <button class="button" type="submit">\(escapeHTML(strings.pageContinue))</button>
            </form>
            """
        case .tooManyAttempts:
            title = strings.pageTooMany
            body = "<div class=\"mark\">⏳</div><h1>\(escapeHTML(strings.pageTooMany))</h1>"
        case .ended:
            title = strings.pageEnded
            body = """
            <div class="mark">⌁</div>
            <h1>\(escapeHTML(strings.pageEnded))</h1>
            <p class="note">\(escapeHTML(strings.pageEndedDetail))</p>
            """
        }
        return """
        <!doctype html>
        <html lang="\(escapeHTML(language))">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="robots" content="noindex, nofollow">
        <title>\(escapeHTML(title))</title>
        <style>
        :root { color-scheme: light dark; --bg: #f5f5f7; --card: #fff; --text: #1d1d1f; --muted: #6e6e73; --accent: #0071e3; --line: #d2d2d7; }
        @media (prefers-color-scheme: dark) { :root { --bg: #000; --card: #1c1c1e; --text: #f5f5f7; --muted: #98989d; --accent: #2997ff; --line: #3a3a3c; } }
        * { box-sizing: border-box; }
        body { margin: 0; min-height: 100vh; display: grid; place-items: center; padding: 16px; background: var(--bg); color: var(--text);
               font: 16px/1.4 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
        main { width: 100%; max-width: 420px; background: var(--card); border-radius: 22px; padding: 32px 24px; text-align: center;
               box-shadow: 0 10px 40px rgba(0,0,0,.08); }
        .mark { font-size: 34px; line-height: 1; margin-bottom: 14px; }
        h1 { font-size: 19px; font-weight: 600; margin: 0 0 6px; overflow-wrap: anywhere; }
        .meta { color: var(--muted); margin: 0 0 22px; font-variant-numeric: tabular-nums; }
        .note { color: var(--muted); font-size: 13px; margin: 18px 0 0; }
        .error { color: #ff453a; font-size: 14px; margin: 10px 0 0; }
        .button { display: block; width: 100%; padding: 13px 16px; border: 0; border-radius: 12px; background: var(--accent); color: #fff;
                  font: inherit; font-weight: 600; text-decoration: none; cursor: pointer; margin-top: 16px; }
        label { display: block; text-align: left; color: var(--muted); font-size: 14px; margin-bottom: 6px; }
        input { width: 100%; padding: 12px 14px; border: 1px solid var(--line); border-radius: 12px; background: transparent; color: inherit; font: inherit; }
        footer { margin-top: 26px; color: var(--muted); font-size: 12px; }
        </style>
        </head>
        <body>
        <main>
        \(body)
        <footer>\(escapeHTML(strings.pageFooter))</footer>
        </main>
        </body>
        </html>
        """
    }

    // MARK: Readings

    static func size(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file)
    }

    /// "15 minutes", "1 hour", "1 day", as the expiry choices read.
    static func duration(_ seconds: TimeInterval, locale: Locale, style: DateComponentsFormatter.UnitsStyle = .full) -> String {
        let formatter = DateComponentsFormatter()
        var calendar = Calendar.current
        calendar.locale = locale
        formatter.calendar = calendar
        formatter.unitsStyle = style
        formatter.allowedUnits = seconds >= 24 * 3600 ? [.day, .hour] : seconds >= 3600 ? [.hour, .minute] : [.minute]
        formatter.maximumUnitCount = seconds >= 3600 ? 1 : 2
        return formatter.string(from: seconds) ?? ""
    }

    /// The time left, rounded up to the minute so the last one never reads as none.
    static func timeLeft(until end: Date, now: Date, locale: Locale) -> String {
        let seconds = max(60, (end.timeIntervalSince(now) / 60).rounded(.up) * 60)
        let formatter = DateComponentsFormatter()
        var calendar = Calendar.current
        calendar.locale = locale
        formatter.calendar = calendar
        formatter.unitsStyle = .short
        formatter.allowedUnits = seconds >= 24 * 3600 ? [.day, .hour] : seconds >= 3600 ? [.hour, .minute] : [.minute]
        formatter.maximumUnitCount = seconds >= 3600 ? 2 : 1
        return formatter.string(from: seconds) ?? ""
    }

    /// When an extension ends: from now for a link that has ended or is
    /// about to, from its own end otherwise.
    static func extended(_ end: Date?, by expiry: NotchLinkExpiry, now: Date) -> Date? {
        guard let duration = expiry.duration else { return nil }
        guard let end else { return nil }
        return max(end, now).addingTimeInterval(duration)
    }

    /// A folder or several files travel as one archive, named after the first.
    static func archiveName(for urls: [URL]) -> String {
        guard let first = urls.first else { return "Files.zip" }
        let base = urls.count == 1 ? first.lastPathComponent : first.deletingPathExtension().lastPathComponent
        return urls.count == 1 ? base + ".zip" : "\(base) +\(urls.count - 1).zip"
    }

    /// Names the items take inside a several-file archive, unique within it.
    static func stagedNames(for urls: [URL]) -> [String] {
        var used = Set<String>()
        return urls.map { url in
            let name = url.lastPathComponent.isEmpty ? "File" : url.lastPathComponent
            var candidate = name
            var number = 2
            while !used.insert(candidate.lowercased()).inserted {
                let ext = (name as NSString).pathExtension
                let stem = (name as NSString).deletingPathExtension
                candidate = ext.isEmpty ? "\(stem) \(number)" : "\(stem) \(number).\(ext)"
                number += 1
            }
            return candidate
        }
    }

    /// The closed island's reading: a download's progress while one runs,
    /// otherwise the time the next link to end has left; nil when every
    /// link lasts until it is stopped.
    static func compactReading(progress: Double?, nextEnd: Date?, now: Date, locale: Locale) -> String? {
        if let progress {
            return "\(Int((min(1, max(0, progress)) * 100).rounded(.down)))%"
        }
        return nextEnd.map { NotchKeepAwakeSupport.compactText(until: $0, now: now, locale: locale) }
    }

    static func showsActivity(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.isEnabled(in: defaults) && AppFeature.notchLinks.isAvailable(in: defaults)
            && defaults.bool(forKey: DefaultsKey.notchLinkActivity)
    }

    /// The wider of the two sides, the link's mark or its reading, drawn as
    /// the strip draws them, with the timer's clearance from the curve and
    /// air beside the camera.
    static func stripWing(reading: String?, in geometry: NotchGeometry) -> CGFloat {
        let provisional = geometry.compactTimerGeometry(showsDownloads: false,
                                                        wing: NotchTimerSupport.stripWingRange.lowerBound)
        let height = provisional.compactActivityContentHeight
        let textSize = NotchTimerSupport.stripTextSize(height: height)
        let right = reading.map {
            (NotchAgentSupport.readingShape($0) as NSString)
                .size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: textSize, weight: .medium)])
                .width.rounded(.up)
        } ?? NotchKeepAwakeSupport.symbolWidth(openSymbol, size: textSize)
        let iconSize = NotchTimerSupport.stripIconSize(height: height)
        let mark = NotchKeepAwakeSupport.symbolWidth(symbol, size: iconSize)
            + provisional.compactActivityEdgeInset(boxHeight: iconSize, radius: iconSize / 2)
        return max(right + provisional.compactActivityEdgeInset(boxHeight: textSize * 0.72, radius: 0), mark)
            + NotchTimerSupport.stripCameraGap
    }
}
