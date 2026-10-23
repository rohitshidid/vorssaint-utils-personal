// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CryptoKit
import Foundation
import Security

enum FanControlIdentifiers {
    static let teamID = "3D485NHW29"

    #if VORSSAINT_DEVELOPMENT
    static let appBundleID = "com.vorssaint.utils.dev"
    #else
    static let appBundleID = "com.vorssaint.utils"
    #endif

    static let helperID = "\(appBundleID).fan-control"
    static let plistName = "\(helperID).plist"

    static let appCodeRequirement = codeRequirement(for: appBundleID)
    static let helperCodeRequirement = codeRequirement(for: helperID)

    /// A Developer ID build trusts only the team. A local build signed with
    /// its own certificate trusts only that certificate, which the app and its
    /// helper share, so the two still reach each other and nothing else can.
    private static func codeRequirement(for identifier: String) -> String {
        guard let root = localSigningRoot else {
            return "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\" and identifier \"\(identifier)\""
        }
        return "identifier \"\(identifier)\" and certificate root = H\"\(root)\""
    }

    static var signedLocally: Bool { localSigningRoot != nil }

    /// The SHA-1 of the root certificate this process is signed with, when
    /// Apple did not issue it. Nil for Developer ID and ad-hoc signatures.
    private static let localSigningRoot: String? = {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var information: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation),
                                            &information) == errSecSuccess,
              let certificates = (information as? [String: Any])?[kSecCodeInfoCertificates as String]
                as? [SecCertificate],
              let root = certificates.last else { return nil }
        var apple: SecRequirement?
        if SecRequirementCreateWithString("anchor apple generic" as CFString, [], &apple) == errSecSuccess,
           let apple, SecCodeCheckValidity(code, [], apple) == errSecSuccess { return nil }
        return Insecure.SHA1.hash(data: SecCertificateCopyData(root) as Data)
            .map { String(format: "%02x", $0) }.joined()
    }()
}

@objc protocol FanControlXPCProtocol {
    func status(withReply reply: @escaping (Data) -> Void)
    func startMaximumCooling(withReply reply: @escaping (Data) -> Void)
    func applyConfiguration(_ configuration: Data, withReply reply: @escaping (Data) -> Void)
    func heartbeat(withReply reply: @escaping (Data) -> Void)
    func restoreAutomatic(withReply reply: @escaping (Data) -> Void)
}

enum FanControlIPC {
    static func encode(_ response: FanControlResponse) -> Data {
        // Every value in this closed response model is JSON encodable. Keeping
        // one deterministic fallback avoids ever violating the XPC reply shape.
        (try? JSONEncoder().encode(response))
            ?? Data(#"{"succeeded":false,"snapshot":{"fans":[],"isCooling":false},"error":"controlFailed"}"#.utf8)
    }

    static func decode(_ data: Data) -> FanControlResponse? {
        try? JSONDecoder().decode(FanControlResponse.self, from: data)
    }

    static func encode(_ configuration: FanControlConfiguration) -> Data? {
        try? JSONEncoder().encode(configuration)
    }

    static func decodeConfiguration(_ data: Data) -> FanControlConfiguration? {
        guard let configuration = try? JSONDecoder().decode(FanControlConfiguration.self,
                                                              from: data),
              FanControlPolicy.validConfiguration(configuration) else { return nil }
        return configuration
    }
}
