// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import ServiceManagement

/// Where the protected helper runs from. macOS launches a daemon kept inside
/// the app only when Apple issued its certificate, so a Developer build signed
/// with a local certificate installs it as a system daemon instead, after an
/// administrator password, once per helper change.
struct FanControlRegistration {
    private let bundled = SMAppService.daemon(plistName: FanControlIdentifiers.plistName)

    static var installsSystemDaemon: Bool {
        #if VORSSAINT_DEVELOPMENT
        return FanControlIdentifiers.signedLocally
        #else
        return false
        #endif
    }

    private static let helperPath = "/Library/PrivilegedHelperTools/\(FanControlIdentifiers.helperID)"
    private static let plistPath = "/Library/LaunchDaemons/\(FanControlIdentifiers.plistName)"

    var status: SMAppService.Status {
        guard Self.installsSystemDaemon else { return bundled.status }
        let files = FileManager.default
        return files.fileExists(atPath: Self.plistPath) && files.fileExists(atPath: Self.helperPath)
            ? .enabled : .notRegistered
    }

    func register() throws {
        guard Self.installsSystemDaemon else { return try bundled.register() }
        // The registration kept inside the app holds the same label.
        if bundled.status != .notRegistered, bundled.status != .notFound { try? bundled.unregister() }
        try Self.install()
    }

    func unregister() throws {
        guard Self.installsSystemDaemon else { return try bundled.unregister() }
        guard status == .enabled else { return }
        let id = FanControlIdentifiers.helperID
        try Self.runAsAdministrator("""
            /bin/launchctl bootout system/\(id) 2>/dev/null; \
            /bin/rm -f \(Self.quoted(Self.plistPath)) \(Self.quoted(Self.helperPath))
            """)
    }

    /// Puts the helper this build carries in place of the registered one.
    func replace(completion: @escaping (Error?) -> Void) {
        guard Self.installsSystemDaemon else {
            bundled.unregister { error in
                guard error == nil else { return completion(error) }
                do { try bundled.register(); completion(nil) } catch { completion(error) }
            }
            return
        }
        do { try Self.install(); completion(nil) } catch { completion(error) }
    }

    private static func install() throws {
        let contents = Bundle.main.bundleURL.appendingPathComponent("Contents")
        let helper = contents.appendingPathComponent("Library/LaunchServices/\(FanControlIdentifiers.helperID)")
        let source = contents.appendingPathComponent("Library/LaunchDaemons/\(FanControlIdentifiers.plistName)")
        guard var plist = NSDictionary(contentsOf: source) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        plist.removeValue(forKey: "BundleProgram")
        plist["Program"] = helperPath
        let staged = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(FanControlIdentifiers.plistName)-\(UUID().uuidString)")
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: staged)
        defer { try? FileManager.default.removeItem(at: staged) }
        let id = FanControlIdentifiers.helperID
        // A helper just stopped can hold its label for a moment, so loading retries.
        try runAsAdministrator("""
            /bin/launchctl bootout system/\(id) 2>/dev/null; \
            /bin/mkdir -p /Library/PrivilegedHelperTools && \
            /usr/bin/install -o root -g wheel -m 755 \(quoted(helper.path)) \(quoted(helperPath)) && \
            /usr/bin/install -o root -g wheel -m 644 \(quoted(staged.path)) \(quoted(plistPath)) && \
            for attempt in 1 2 3 4 5; do \
            /bin/launchctl bootstrap system \(quoted(plistPath)) && exit 0; /bin/sleep 1; done; exit 1
            """)
    }

    private static func runAsAdministrator(_ command: String) throws {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "do shell script \"\(escaped)\" with administrator privileges"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.userCancelled) }
    }

    private static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
