// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Docker containers and Ollama models, largest first, each with the memory
/// it holds and a way to let go of it. A section stays away while its tool
/// is not installed, and says so while it is not running.
struct NotchWorkloadsView: View {
    let size: CGSize
    @ObservedObject private var service = NotchWorkloadService.shared
    @ObservedObject private var l10n = L10n.shared
    private var text: NotchWorkloadStrings { FeatureStrings.notchWorkloads(l10n.language) }

    var body: some View {
        Group {
            if service.docker == .missing, service.ollama == .missing {
                NotchEmptyView(symbol: "shippingbox", message: text.notInstalled)
            } else if service.docker == .unknown, service.ollama == .unknown {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if service.docker != .missing { dockerSection }
                        if service.ollama != .missing { ollamaSection }
                    }
                }
                .scrollIndicators(.automatic)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { service.begin() }
        .onDisappear { service.end() }
    }

    private var dockerSection: some View {
        section("Docker", symbol: "shippingbox", state: service.docker,
                total: service.containers.compactMap(\.memory).reduce(0, +),
                stopped: text.dockerStopped, empty: service.containers.isEmpty ? text.noContainers : nil) {
            ForEach(service.containers) { container in
                row(name: container.name,
                    detail: [container.image, container.status].filter { !$0.isEmpty }.joined(separator: " · "),
                    memory: container.memory, stopping: service.stopping.contains(container.id),
                    action: text.stopContainer) { confirmStop(container) }
            }
        }
    }

    private var ollamaSection: some View {
        section("Ollama", symbol: "brain", state: service.ollama,
                total: service.models.map(\.size).reduce(0, +),
                stopped: text.ollamaStopped, empty: service.models.isEmpty ? text.noModels : nil) {
            // The time left counts down between readings, which only change
            // when a model loads or leaves.
            TimelineView(.periodic(from: .now, by: 15)) { context in
                VStack(spacing: 6) {
                    ForEach(service.models) { model in
                        row(name: model.name, detail: expiry(model, now: context.date), memory: model.size,
                            stopping: service.stopping.contains(model.id),
                            action: text.unloadModel) { service.unload(model) }
                    }
                }
            }
        }
    }

    private func expiry(_ model: NotchOllamaModel, now: Date) -> String {
        guard let left = NotchWorkloadSupport.remaining(model, now: now) else { return text.staysLoaded }
        return text.unloadsIn(NotchWorkloadSupport.timeLeft(left, locale: l10n.language.formattingLocale()))
    }

    private func section<Rows: View>(_ title: String, symbol: String, state: NotchWorkloadState, total: UInt64,
                                     stopped: String, empty: String?,
                                     @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if total > 0 {
                    Text(NotchWorkloadSupport.memory(total))
                        .font(.system(size: 11, weight: .medium)).monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
            .accessibilityElement(children: .combine)
            switch state {
            case .stopped: status(stopped)
            case .unknown: ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 36)
            case .running, .missing:
                if let empty { status(empty) } else { rows() }
            }
        }
    }

    private func status(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.55))
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func row(name: String, detail: String, memory: UInt64?, stopping: Bool, action: String,
                     stop: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1).truncationMode(.middle)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(memory.map(NotchWorkloadSupport.memory) ?? "…")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
            Group {
                if stopping {
                    ProgressView().controlSize(.mini).frame(width: 28, height: 28)
                } else {
                    NotchIconButton(symbol: "stop.fill", title: action, action: stop)
                }
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(minHeight: 44)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    /// The question rises above the island, as the Port manager's does there.
    private func confirmStop(_ container: NotchDockerContainer) {
        DispatchQueue.main.async {
            guard NSAlert.confirmAboveIsland(text.confirmStop(container.name), message: text.confirmStopMessage,
                                             action: text.stop, destructive: true,
                                             cancel: l10n.s.uninstallerCancel) else { return }
            service.stop(container)
        }
    }
}
