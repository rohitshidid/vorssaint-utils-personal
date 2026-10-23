// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Files shared by link, newest first: each one's time left, downloads and
/// a download under way, with its address to copy or scan, more time, a
/// password, and a way to stop it. Above them, how long new links last.
struct NotchLinksView: View {
    @ObservedObject var service: NotchService
    let size: CGSize
    @ObservedObject private var links = NotchLinkService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var codeFor: UUID?
    @Environment(\.notchSettingsPreview) private var preview
    private var text: NotchLinkStrings { FeatureStrings.notchLinks(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            status
            if links.links.isEmpty {
                NotchEmptyView(symbol: NotchLinkSupport.symbol, message: text.empty)
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        // The time left counts down between changes.
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            VStack(spacing: 6) {
                                ForEach(links.links) { row($0, now: context.date) }
                            }
                        }
                    }
                }
                .scrollIndicators(.automatic)
                Text(text.awake)
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // A QR code's popover holds the island open while it shows.
        .onChange(of: codeFor != nil) { _, showing in if !preview { service.keepFileInteractionOpen(showing) } }
        .onDisappear { if !preview, codeFor != nil { service.keepFileInteractionOpen(false) } }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(NotchLinkExpiry.allCases) { choice in
                    Button { links.expiry = choice } label: {
                        if choice == links.expiry { Label(title(choice), systemImage: "checkmark") }
                        else { Text(title(choice)) }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "clock").font(.system(size: 10, weight: .medium))
                    Text("\(text.newLinks): \(title(links.expiry))").lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 10).frame(height: 24)
                .background(.white.opacity(0.08), in: Capsule())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            Spacer(minLength: 0)
            if links.links.count > 1 {
                Button(text.stopAll, role: .destructive) { links.stopAll() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.red.opacity(0.9))
            }
        }
        .padding(.horizontal, 4)
    }

    private func title(_ choice: NotchLinkExpiry) -> String {
        switch choice {
        case .untilStopped: return text.untilStopped
        case .oneDownload: return text.oneDownload
        default: return NotchLinkSupport.duration(choice.duration ?? 0, locale: l10n.language.formattingLocale())
        }
    }

    // MARK: Tunnel

    @ViewBuilder private var status: some View {
        switch links.tunnel {
        case .missing:
            banner(text.missing, symbol: "exclamationmark.triangle.fill", tint: .orange) {
                Button(links.canInstall ? text.install : text.getCloudflared) { links.installCloudflared() }
            }
        case .installing:
            banner(text.installing, symbol: nil, tint: .secondary) { EmptyView() }
        case .failed:
            banner(text.failed, symbol: "wifi.exclamationmark", tint: .orange) {
                Button(text.tryAgain) { links.retry() }
            }
        case .off, .starting, .ready:
            EmptyView()
        }
    }

    private func banner<Action: View>(_ message: String, symbol: String?, tint: Color,
                                      @ViewBuilder action: () -> Action) -> some View {
        HStack(spacing: 8) {
            if let symbol { Image(systemName: symbol).foregroundStyle(tint) }
            else { ProgressView().controlSize(.small) }
            Text(message).font(.system(size: 11)).foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            action().controlSize(.small)
        }
        .padding(10)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Rows

    private func row(_ link: NotchLink, now: Date) -> some View {
        let address = links.url(for: link)
        return HStack(spacing: 8) {
            Image(systemName: link.password == nil ? "doc.fill" : "lock.fill")
                .font(.system(size: 13))
                .foregroundStyle(.cyan.opacity(0.9))
                .frame(width: 18)
                .accessibilityLabel(link.password == nil ? "" : text.passwordProtected)
            VStack(alignment: .leading, spacing: 3) {
                Text(link.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1).truncationMode(.middle)
                detail(link, address: address, now: now)
                if let progress = link.progress {
                    ProgressView(value: progress).progressViewStyle(.linear).controlSize(.mini).tint(.cyan)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            NotchIconButton(symbol: links.copiedID == link.id ? "checkmark" : "doc.on.doc", title: text.copy) {
                links.copy(link.id)
            }
            .disabled(address == nil)
            NotchIconButton(symbol: "qrcode", title: text.qrCode) { codeFor = link.id }
                .disabled(address == nil)
                .popover(isPresented: Binding(get: { codeFor == link.id }, set: { if !$0 { codeFor = nil } })) {
                    if let address { code(address) }
                }
            more(link)
            NotchIconButton(symbol: "stop.fill", title: text.stop) { links.stop(link.id) }
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .frame(minHeight: 48)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func detail(_ link: NotchLink, address: URL?, now: Date) -> some View {
        let line: String = {
            if links.copiedID == link.id { return text.copied }
            if address == nil { return text.creating }
            if let progress = link.progress {
                return text.downloading(progress.formatted(.percent.precision(.fractionLength(0))))
            }
            var parts = [NotchLinkSupport.size(link.size)]
            if link.oneDownload { parts.append(text.endsAfterDownload) }
            else if let end = link.expiresAt {
                parts.append(text.endsIn(NotchLinkSupport.timeLeft(until: end, now: now,
                                                                   locale: l10n.language.formattingLocale())))
            } else { parts.append(text.untilStoppedDetail) }
            return parts.joined(separator: " · ")
        }()
        HStack(spacing: 6) {
            if address == nil, links.tunnel == .starting || link.phase == .preparing {
                ProgressView().controlSize(.mini)
            }
            Text(line)
                .foregroundStyle(links.copiedID == link.id ? Color.green : Color.secondary)
                .lineLimit(1).truncationMode(.tail)
            if link.downloads > 0 {
                Label("\(link.downloads)", systemImage: "arrow.down")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(text.downloads): \(link.downloads)")
            }
        }
        .font(.system(size: 10)).monospacedDigit()
    }

    private func more(_ link: NotchLink) -> some View {
        Menu {
            if link.expiresAt != nil, !link.oneDownload {
                Menu(text.extend) {
                    ForEach(NotchLinkExpiry.extensions) { choice in
                        Button(extensionTitle(choice)) { links.extend(link.id, by: choice) }
                    }
                }
            }
            if link.password == nil {
                Button(text.addPassword) { askPassword(for: link) }
            } else {
                Button(text.removePassword) { links.setPassword(nil, for: link.id) }
            }
            Divider()
            Button(text.stop, role: .destructive) { links.stop(link.id) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 28, height: 28)
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(text.more)
        .accessibilityLabel(text.more)
    }

    private func extensionTitle(_ choice: NotchLinkExpiry) -> String {
        guard let duration = choice.duration else { return text.untilStopped }
        return "+" + NotchLinkSupport.duration(duration, locale: l10n.language.formattingLocale(), style: .short)
    }

    /// Asked just above the island, like the island's other questions.
    private func askPassword(for link: NotchLink) {
        DispatchQueue.main.async {
            let field = NSSecureTextField(string: "")
            field.placeholderString = text.passwordPlaceholder
            field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
            let alert = NSAlert()
            alert.messageText = text.passwordTitle(link.name)
            alert.informativeText = text.passwordMessage
            alert.accessoryView = field
            alert.addButton(withTitle: text.setPassword)
            alert.addButton(withTitle: l10n.s.uninstallerCancel).keyEquivalent = "\u{1b}"
            alert.window.initialFirstResponder = field
            guard NotchIslandAlert.run(alert, above: service.presentationWindow) == .alertFirstButtonReturn,
                  !field.stringValue.isEmpty else { return }
            links.setPassword(field.stringValue, for: link.id)
        }
    }

    // MARK: QR code

    private func code(_ address: URL) -> some View {
        VStack(spacing: 10) {
            if let image = Self.qrCode(address.absoluteString) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 180, height: 180)
                    .padding(10)
                    .background(.white, in: RoundedRectangle(cornerRadius: 10))
            }
            Text(address.host ?? address.absoluteString)
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: 200)
        }
        .padding(14)
    }

    static func qrCode(_ string: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        let representation = NSCIImageRep(ciImage: output)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }
}
