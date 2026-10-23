// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CryptoKit
import Foundation

/// Files shared by link: what the server reads and answers, the tunnel's
/// address, the time links last, and the island's page and reading.
enum NotchLinkTests {
    static func run(_ suite: TestSuite) {
        requests(suite)
        responses(suite)
        tunnel(suite)
        time(suite)
        page(suite)
        server(suite)
    }

    private typealias Support = NotchLinkSupport

    private static func requests(_ suite: TestSuite) {
        let tokens = (0..<50).map { _ in Support.newToken() }
        suite.expect(Set(tokens).count == 50 && tokens.allSatisfy { Support.isToken(Substring($0)) },
                     "every link gets its own 22-character token of URL-safe characters")
        let token = tokens[0]
        suite.expect(Support.route("/\(token)") == .page(token: token) && Support.route("/\(token)/") == .page(token: token)
                        && Support.route("/\(token)/download") == .download(token: token)
                        && Support.route("/robots.txt") == .robots,
                     "a token's path is its page, and /download under it is its file")
        suite.expect([ "/", "/favicon.ico", "/\(token)/other", "/\(token)/download/x", "/../\(token)",
                       "/\(token.dropLast())", "/\(token)x" ].allSatisfy { Support.route($0) == .unknown },
                     "any other path is no link at all")
        let head = Data("GET /\(token)/download?x=1 HTTP/1.1\r\nHost: a.trycloudflare.com\r\nRange: bytes=10-\r\nCookie: a=1; vl_x=2\r\nContent-Length: 12".utf8)
        let request = Support.request(head: head)
        suite.expect(request?.method == "GET" && request?.path == "/\(token)/download" && request?.header("RANGE") == "bytes=10-"
                        && request?.cookies == ["a": "1", "vl_x": "2"] && request?.contentLength == 12,
                     "a request reads its method, path without query, headers and cookies")
        suite.expect(Support.request(head: Data("GET / FTP/1.0".utf8)) == nil
                        && Support.request(head: Data("GET nothing HTTP/1.1".utf8)) == nil
                        && Support.request(head: Data("GET / HTTP/1.1\r\nbroken header".utf8)) == nil
                        && Support.request(head: Data(repeating: 65, count: Support.maximumHead + 1)) == nil,
                     "anything that is not a plain HTTP/1 request is turned away")
        suite.expect(Support.range(nil, size: 100) == .whole && Support.range("bytes=0-", size: 100) == .whole
                        && Support.range("bytes=10-19", size: 100) == .part(10...19)
                        && Support.range("bytes=90-", size: 100) == .part(90...99)
                        && Support.range("bytes=-5", size: 100) == .part(95...99)
                        && Support.range("bytes=50-500", size: 100) == .part(50...99)
                        && Support.range("bytes=100-", size: 100) == .unsatisfiable
                        && Support.range("bytes=0-1,5-6", size: 100) == .whole
                        && Support.range("bytes=x-y", size: 100) == .whole
                        && Support.range("bytes=20-10", size: 100) == .whole,
                     "one range resumes a download; several, or one that does not parse, get the whole file")
        suite.expect(Support.formValue("password", in: Data("a=1&password=open+s%C3%A9same%26".utf8)) == "open sésame&"
                        && Support.formValue("password", in: Data("a=1".utf8)) == nil,
                     "a form's password reads as the browser sent it")
        let password = NotchLinkPassword("hunter2")
        suite.expect(password.matches("hunter2") && !password.matches("hunter3") && !password.matches("")
                        && NotchLinkPassword("hunter2").hash != password.hash,
                     "a password is kept salted and hashed, and only it unlocks the link")
        let key = SymmetricKey(size: .bits256)
        suite.expect(Support.pass(token: token, secret: key) == Support.pass(token: token, secret: key)
                        && Support.pass(token: token, secret: key) != Support.pass(token: tokens[1], secret: key)
                        && Support.pass(token: token, secret: key) != Support.pass(token: token, secret: SymmetricKey(size: .bits256)),
                     "the proof of a password belongs to one link and one run of the server")
    }

    private static func responses(_ suite: TestSuite) {
        let head = String(decoding: Support.head(status: 206, headers: [("Content-Length", "10")]), as: UTF8.self)
        suite.expect(head.hasPrefix("HTTP/1.1 206 Partial Content\r\n") && head.hasSuffix("\r\n\r\n")
                        && head.contains("Connection: close") && head.contains("Cache-Control: no-store")
                        && head.contains("X-Robots-Tag: noindex"),
                     "every response closes its connection and is kept nowhere")
        let disposition = Support.contentDisposition("Résumé \"final\".pdf")
        suite.expect(disposition == #"attachment; filename="R_sum_ _final_.pdf"; filename*=UTF-8''R%C3%A9sum%C3%A9%20%22final%22.pdf"#,
                     "the file saves under its own name, with a plain one for older browsers")
        suite.expect(Support.escapeHTML(#"<b>"Tom" & 'Jerry'</b>"#) == "&lt;b&gt;&quot;Tom&quot; &amp; &#39;Jerry&#39;&lt;/b&gt;",
                     "a file's name never becomes markup")
    }

    private static func tunnel(_ suite: TestSuite) {
        let log = """
        2026-10-20T05:00:10Z INF Requesting new quick Tunnel on trycloudflare.com...
        2026-10-20T05:00:14Z INF +--------------------------------------------------------------------------------------------+
        2026-10-20T05:00:14Z INF |  https://another-jonathan-harvard-berkeley.trycloudflare.com                               |
        """
        suite.expect(Support.tunnelURL(in: log)?.absoluteString == "https://another-jonathan-harvard-berkeley.trycloudflare.com"
                        && Support.tunnelURL(in: "https://evil.example.com") == nil
                        && !Support.tunnelIsConnected(log)
                        && Support.tunnelIsConnected(log + "\nINF Registered tunnel connection connIndex=0"),
                     "the tunnel's address and its first connection read from cloudflared's log")
        let arguments = Support.tunnelArguments(port: 51234, config: "/tmp/links/cloudflared.yml")
        suite.expect(arguments == ["tunnel", "--config", "/tmp/links/cloudflared.yml", "--no-autoupdate",
                                   "--url", "http://127.0.0.1:51234"]
                        && !Support.tunnelConfig.contains("tunnel:"),
                     "the tunnel points at the loopback server with a configuration of its own")
        suite.expect(Support.cloudflaredCandidates(home: "/Users/me").first == "/opt/homebrew/bin/cloudflared"
                        && Support.cloudflaredCandidates(home: "/Users/me").contains("/usr/local/bin/cloudflared"),
                     "cloudflared is found where Homebrew puts it")
        suite.expect(Support.resolverURL(host: "a-b.trycloudflare.com")?.absoluteString
                        == "https://cloudflare-dns.com/dns-query?name=a-b.trycloudflare.com&type=A",
                     "the new address is checked at Cloudflare's own resolver")
        suite.expect(Support.resolves(Data(#"{"Status":0,"Answer":[{"name":"a","type":1,"data":"104.16.231.132"}]}"#.utf8))
                        && !Support.resolves(Data(#"{"Status":3}"#.utf8))
                        && !Support.resolves(Data(#"{"Status":0,"Answer":[]}"#.utf8))
                        && !Support.resolves(Data("nope".utf8)),
                     "the address counts as known once the resolver answers with it")
    }

    private static func time(_ suite: TestSuite) {
        suite.expect(NotchLinkExpiry.quarterHour.duration == 900 && NotchLinkExpiry.hour.duration == 3600
                        && NotchLinkExpiry.oneDownload.duration == 86_400 && NotchLinkExpiry.untilStopped.duration == nil
                        && NotchLinkExpiry.stored(nil) == .hour && NotchLinkExpiry.stored("day") == .day
                        && NotchLinkExpiry.stored("forever") == .hour,
                     "a new link lasts an hour unless the person chose otherwise, and one for a download ends within a day")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        suite.expect(Support.extended(now.addingTimeInterval(600), by: .hour, now: now) == now.addingTimeInterval(4200)
                        && Support.extended(now.addingTimeInterval(-60), by: .quarterHour, now: now) == now.addingTimeInterval(900)
                        && Support.extended(now, by: .untilStopped, now: now) == nil,
                     "more time adds to what a link has left, and a link about to end gets it from now")
        let english = Locale(identifier: "en_US")
        suite.expect(Support.timeLeft(until: now.addingTimeInterval(230), now: now, locale: english) == "4 min"
                        && Support.timeLeft(until: now.addingTimeInterval(5), now: now, locale: english) == "1 min"
                        && Support.duration(900, locale: english) == "15 minutes" && Support.duration(3600, locale: english) == "1 hour"
                        && Support.duration(86_400, locale: english) == "1 day",
                     "times read in whole minutes, never down to none")
        suite.expect(Support.compactReading(progress: 0.437, nextEnd: now.addingTimeInterval(600), now: now, locale: english) == "43%"
                        && Support.compactReading(progress: nil, nextEnd: now.addingTimeInterval(45 * 60), now: now, locale: english) == "45m"
                        && Support.compactReading(progress: nil, nextEnd: nil, now: now, locale: english) == nil,
                     "the closed island reads a download's progress, else the next link's time left")
        let a = URL(fileURLWithPath: "/tmp/a/Report.pdf"), b = URL(fileURLWithPath: "/tmp/b/Report.pdf")
        let folder = URL(fileURLWithPath: "/tmp/Photos", isDirectory: true)
        suite.expect(Support.archiveName(for: [a, b, folder]) == "Report +2.zip" && Support.archiveName(for: [folder]) == "Photos.zip"
                        && Support.stagedNames(for: [a, b, folder]) == ["Report.pdf", "Report 2.pdf", "Photos"],
                     "several files travel as one archive named after the first, each under a name of its own")
    }

    private static func page(_ suite: TestSuite) {
        let strings = FeatureStrings.notchLinks(.enUS)
        let html = Support.page(.download(token: "TOKEN", name: "<script>x</script>.pdf", size: "2 MB",
                                          availability: "Available for 4 min"),
                                strings: strings, language: "en-US")
        suite.expect(html.contains("&lt;script&gt;x&lt;/script&gt;.pdf") && !html.contains("<script")
                        && html.contains(#"href="/TOKEN/download""#) && html.contains("Available for 4 min"),
                     "the recipient's page names the file safely and links to its download")
        let locked = Support.page(.password(name: "a.pdf", size: "1 KB", error: strings.pageWrongPassword),
                                  strings: strings, language: "en-US")
        suite.expect(locked.contains(#"type="password""#) && locked.contains(strings.pageWrongPassword) && !locked.contains("/download"),
                     "a locked link shows a password field and no way to the file")
        suite.expect(Support.pagePolicy.contains("default-src 'none'") && Support.pagePolicy.contains("frame-ancestors 'none'"),
                     "the page runs no script and loads nothing")
        suite.expect(NotchModule.links.symbol == "link" && Set(NotchModule.allCases.map(\.shortcutKey)).count == NotchModule.allCases.count
                        && NotchCompactActivity.links.module == .links,
                     "the page has its own mark and its own key, and the closed island's reading opens it")
        suite.expect(NotchSupport.compactActivities(timer: false, downloads: true, links: true, agents: true,
                                                    calendar: false, music: true, keepAwake: true)
                        == [.downloads, .links, .agents, .music, .keepAwake],
                     "shared links follow downloads among the closed island's activities")
        suite.expect(NotchFileToolsSupport.dropChoices(shelf: true, link: true, media: true) == [.shelf, .link, .media]
                        && NotchFileToolsSupport.dropChoices(shelf: true, link: false, media: true) == [.shelf, .media]
                        && NotchFileToolsSupport.dropChoices(shelf: true, link: true, media: false) == [.shelf, .link],
                     "the shelf comes first, then Get link, then Optimize")
        suite.expect(NotchFileToolsSupport.dropChoices(shelf: false, link: true, media: true) == [.link, .media]
                        && NotchFileToolsSupport.dropChoices(shelf: false, link: true, media: false) == [.link],
                     "with the shelf off, Get link and Optimize still take files")
        let geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1440, height: 900), safeAreaTop: 32, cameraWidth: 180)
        let size = geometry.expandedSize(module: .files)
        let choices = NotchFileToolsSupport.dropChoices(shelf: true, link: true, media: true)
        let columns = choices.indices.map { NotchFileToolsSupport.dropArea($0, of: 3, in: geometry, size: size) }
        suite.expect(zip(columns, choices).allSatisfy { area, choice in
                        NotchFileToolsSupport.dropChoice(at: CGPoint(x: area.midX, y: area.midY), among: choices,
                                                         in: geometry, size: size) == choice
                     }
                     && NotchFileToolsSupport.dropChoice(at: CGPoint(x: size.width / 2, y: 2), among: choices,
                                                         in: geometry, size: size) == .shelf
                     && NotchFileToolsSupport.dropArea(1, of: 2, in: geometry, size: size)
                        == NotchFileToolsSupport.mediaDropArea(in: geometry, size: size),
                     "each column takes the drop over it, and the header goes to the shelf")
        let linkOnly = NotchFileToolsSupport.dropChoices(shelf: false, link: true, media: false)
        suite.expect([CGPoint(x: size.width / 2, y: 2), CGPoint(x: 40, y: size.height / 2)].allSatisfy {
                        NotchFileToolsSupport.dropChoice(at: $0, among: linkOnly, in: geometry, size: size) == .link
                     },
                     "without the shelf, Get link alone takes the whole page")
        let island = CGRect(x: 100, y: 800, width: 200, height: 40)
        suite.expect(NotchSupport.distance(from: CGPoint(x: 150, y: 820), to: island) == 0
                        && NotchSupport.distance(from: CGPoint(x: 150, y: 760), to: island) == 40
                        && NotchSupport.distance(from: CGPoint(x: 330, y: 760), to: island) == 50,
                     "a dragged file's distance runs to the island's nearest edge, and over it is none")
        suite.expect(NotchSupport.sanitizedDragProximity(-5) == 0 && NotchSupport.sanitizedDragProximity(500) == 200
                        && NotchSupport.sanitizedDragProximity(.nan) == NotchSupport.defaultDragProximity
                        && NotchSupport.sanitizedDragProximity(80) == 80,
                     "the opening distance stays between over the island and 200 points")
        let defaults = UserDefaults(suiteName: "vorss.tests.notch-links")!
        defaults.removePersistentDomain(forName: "vorss.tests.notch-links")
        defer { defaults.removePersistentDomain(forName: "vorss.tests.notch-links") }
        defaults.set(120.0, forKey: DefaultsKey.notchDragProximity)
        suite.expect(NotchSupport.dragProximity(in: defaults) == 0,
                     "with files kept out of the island, nothing opens as a file comes near")
        defaults.set(false, forKey: AppFeature.notchLinks.availabilityKey)
        suite.expect(!NotchModule.links.isAvailable(in: defaults) && !NotchSupport.routes(.shareLink, in: defaults),
                     "the page and its alerts wait until the feature is installed")
        defaults.set(true, forKey: AppFeature.notchLinks.availabilityKey)
        suite.expect(NotchModule.links.isAvailable(in: defaults) && AppFeature.notchLinks.permissions.isEmpty
                        && !AppFeature.notchLinks.installedByDefault,
                     "installing it adds the page, asks for nothing, and it ships uninstalled")
        let english = Mirror(reflecting: strings).children.count
        suite.expect(AppLanguage.allCases.allSatisfy { language in
            let text = FeatureStrings.notchLinks(language)
            let lines = Mirror(reflecting: text).children.compactMap { $0.value as? String }
            return lines.count == english && lines.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                && text.passwordTitle("a.pdf").contains("a.pdf") && text.endsIn("4 min").contains("4 min")
                && text.downloading("43%").contains("43%") && text.pageAvailable("4 min").contains("4 min")
                && !FeatureStrings.notchEditor(language).summary(.links).isEmpty
        }, "every language has every line of the page, the island and the recipient's page")
    }

    // MARK: Server

    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var events: [NotchLinkServerEvent] = []
        func add(_ event: NotchLinkServerEvent) { lock.lock(); events.append(event); lock.unlock() }
        var all: [NotchLinkServerEvent] { lock.lock(); defer { lock.unlock() }; return events }
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    private static func fetch(_ session: URLSession, _ url: URL, method: String = "GET",
                              headers: [String: String] = [:], body: Data? = nil) -> (status: Int, headers: [String: String], data: Data)? {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let done = DispatchSemaphore(value: 0)
        var result: (Int, [String: String], Data)?
        session.dataTask(with: request) { data, response, _ in
            if let response = response as? HTTPURLResponse {
                let fields = Dictionary(uniqueKeysWithValues: response.allHeaderFields.map { ("\($0.key)".lowercased(), "\($0.value)") })
                result = (response.statusCode, fields, data ?? Data())
            }
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 10)
        return result
    }

    private static func server(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("vorss-links-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("data.bin")
        let content = Data((0..<600_000).map { UInt8($0 % 251) })
        try? content.write(to: file)
        let recorder = Recorder()
        let strings = FeatureStrings.notchLinks(.enUS)
        let server = NotchLinkServer(strings: strings, language: .enUS) { recorder.add($0) }
        var port: UInt16?
        var answered = false
        server.start { port = $0; answered = true }
        let deadline = Date().addingTimeInterval(5)
        while !answered, Date() < deadline { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05)) }
        defer { server.stop() }
        guard let port else {
            suite.expect(false, "the link server listens on the loopback interface")
            return
        }
        let open = NotchLinkRoute(id: UUID(), token: Support.newToken(), name: "Report é.bin", file: file,
                                  size: UInt64(content.count), expiresAt: Date().addingTimeInterval(600),
                                  oneDownload: false, password: nil)
        let locked = NotchLinkRoute(id: UUID(), token: Support.newToken(), name: "secret.bin", file: file,
                                    size: UInt64(content.count), expiresAt: nil, oneDownload: false,
                                    password: NotchLinkPassword("letmein"))
        let once = NotchLinkRoute(id: UUID(), token: Support.newToken(), name: "once.bin", file: file,
                                  size: UInt64(content.count), expiresAt: nil, oneDownload: true, password: nil)
        let ended = NotchLinkRoute(id: UUID(), token: Support.newToken(), name: "old.bin", file: file,
                                   size: UInt64(content.count), expiresAt: Date().addingTimeInterval(-1),
                                   oneDownload: false, password: nil)
        server.update([open, locked, once, ended], strings: strings, language: .enUS)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        let base = URL(string: "http://127.0.0.1:\(port)")!

        let page = fetch(session, base.appendingPathComponent(open.token))
        let html = page.map { String(decoding: $0.data, as: UTF8.self) } ?? ""
        suite.expect(page?.status == 200 && html.contains("Report é.bin") && html.contains("/\(open.token)/download")
                        && page?.headers["content-security-policy"] == Support.pagePolicy,
                     "a link's page names its file and links to the download")
        let whole = fetch(session, base.appendingPathComponent(open.token).appendingPathComponent("download"))
        suite.expect(whole?.status == 200 && whole?.data == content
                        && whole?.headers["content-type"] == "application/octet-stream"
                        && whole?.headers["content-disposition"]?.contains("filename*=UTF-8''Report%20%C3%A9.bin") == true,
                     "the download is the whole file, saved under its name")
        let part = fetch(session, base.appendingPathComponent(open.token).appendingPathComponent("download"),
                         headers: ["Range": "bytes=500000-"])
        suite.expect(part?.status == 206 && part?.data == content.suffix(100_000)
                        && part?.headers["content-range"] == "bytes 500000-599999/600000",
                     "a download picks up where it stopped")
        let unknown = fetch(session, base.appendingPathComponent(Support.newToken()))
        let elsewhere = fetch(session, base.appendingPathComponent("etc").appendingPathComponent("passwd"))
        let late = fetch(session, base.appendingPathComponent(ended.token).appendingPathComponent("download"))
        suite.expect(unknown?.status == 404 && elsewhere?.status == 404 && late?.status == 410
                        && String(decoding: late?.data ?? Data(), as: UTF8.self).contains(strings.pageEnded),
                     "an unknown, made-up or ended link gets the page that says it has ended")

        let lockedPage = fetch(session, base.appendingPathComponent(locked.token))
        let lockedFile = fetch(session, base.appendingPathComponent(locked.token).appendingPathComponent("download"))
        suite.expect(lockedPage?.status == 200 && String(decoding: lockedPage?.data ?? Data(), as: UTF8.self).contains(#"type="password""#)
                        && lockedFile?.status == 303 && lockedFile?.data.isEmpty == true,
                     "a locked link asks for its password and keeps its file back")
        let wrong = fetch(session, base.appendingPathComponent(locked.token), method: "POST",
                          headers: ["Content-Type": "application/x-www-form-urlencoded"], body: Data("password=nope".utf8))
        let right = fetch(session, base.appendingPathComponent(locked.token), method: "POST",
                          headers: ["Content-Type": "application/x-www-form-urlencoded"], body: Data("password=letmein".utf8))
        let cookie = right?.headers["set-cookie"]?.components(separatedBy: ";").first ?? ""
        let unlocked = fetch(session, base.appendingPathComponent(locked.token).appendingPathComponent("download"),
                             headers: ["Cookie": cookie])
        suite.expect(wrong?.status == 401 && right?.status == 303 && right?.headers["set-cookie"]?.contains("HttpOnly; Secure") == true
                        && unlocked?.status == 200 && unlocked?.data == content,
                     "the right password unlocks the file for that browser, and a wrong one does not")
        for _ in 0..<NotchLinkSupport.maximumAttempts {
            _ = fetch(session, base.appendingPathComponent(locked.token), method: "POST", body: Data("password=guess".utf8))
        }
        let blocked = fetch(session, base.appendingPathComponent(locked.token), method: "POST", body: Data("password=letmein".utf8))
        suite.expect(blocked?.status == 429, "too many wrong passwords and the link refuses even the right one")

        let first = fetch(session, base.appendingPathComponent(once.token).appendingPathComponent("download"))
        Thread.sleep(forTimeInterval: 0.2)
        let second = fetch(session, base.appendingPathComponent(once.token).appendingPathComponent("download"))
        let events = recorder.all
        suite.expect(first?.status == 200 && first?.data == content && second?.status == 404
                        && events.contains { if case .spent(once.id) = $0 { return true }; return false },
                     "a link for one download stops answering once it gave it")
        let finished = events.filter { if case .ended(_, _, true) = $0 { return true }; return false }.count
        suite.expect(finished == 4 && events.contains { if case .began(_, open.id, 600_000) = $0 { return true }; return false },
                     "each download that reached the end of the file counts, a resumed one too")
    }
}
