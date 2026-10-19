// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The Claude Code folders that get limits cards of their own on the AI page.
struct ClaudeAccountsSettings: View {
    @AppStorage(DefaultsKey.notchAgentsClaudeProfiles) private var saved = ""
    /// Hiding the Limits card stops the checks, so Check limits greys out with it.
    @AppStorage(DefaultsKey.notchAgentsHiddenCards) private var hiddenCards = ""
    @ObservedObject private var service = ClaudeProfileLimitsService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var invalidFolder = false
    private var profiles: [ClaudeAccountProfile] { ClaudeAccountProfile.decode(saved) }
    private var text: ClaudeAccountStrings { FeatureStrings.claudeAccounts(l10n.language) }
    /// The words both agents' account lists share.
    private var shared: CodexAccountStrings { FeatureStrings.codexAccounts(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text.title).font(.subheadline.weight(.medium))
            Text(text.explanation)
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(profiles) { profile in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        TextField(shared.accountName, text: Binding(
                            get: { profiles.first { $0.id == profile.id }?.name ?? profile.name },
                            set: { value in
                                guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                                var updated = profiles
                                if let index = updated.firstIndex(where: { $0.id == profile.id }) {
                                    updated[index].name = String(value.prefix(40))
                                    save(updated)
                                }
                            }))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Claude · " + shared.accountName + ": " + profile.name)
                        Text(profile.directory).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            .truncationMode(.middle).help(profile.directory)
                    }
                    Button { save(profiles.filter { $0.id != profile.id }) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.plain).help(shared.remove).accessibilityLabel(shared.remove)
                }
            }
            HStack {
                Button(shared.find) {
                    var updated = profiles
                    for profile in ClaudeAccountProfile.discover(defaultName: shared.defaultName) where !updated.contains(where: {
                        $0.canonicalDirectory() == profile.canonicalDirectory()
                    }) { updated.append(profile) }
                    save(Array(updated.prefix(ClaudeAccountProfile.maximum)))
                }
                .disabled(profiles.count >= ClaudeAccountProfile.maximum)
                Button(shared.add) { addFolder() }
                    .disabled(profiles.count >= ClaudeAccountProfile.maximum)
                if !profiles.isEmpty {
                    Button(shared.check) { service.refresh(force: true) }
                        .disabled(!service.isEnabled || service.states.allSatisfy(\.checking))
                }
            }
            if profiles.isEmpty {
                Text(text.fallback)
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { service.synchronize() }
        .alert(text.chooseFolder, isPresented: $invalidFolder) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(text.invalidFolder)
        }
    }

    private func save(_ value: [ClaudeAccountProfile]) {
        saved = ClaudeAccountProfile.encode(value)
        service.synchronize()
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let profile = ClaudeAccountProfile(id: UUID().uuidString,
                                           name: ClaudeAccountProfile.name(for: url, defaultName: shared.defaultName),
                                           directory: url.path)
        guard let canonical = profile.canonicalDirectory() else { invalidFolder = true; return }
        guard !profiles.contains(where: { $0.canonicalDirectory() == canonical }) else { return }
        save(profiles + [ClaudeAccountProfile(id: profile.id, name: profile.name, directory: canonical.path)])
    }
}
