// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// What the closed island reads off shared links.
struct NotchLinkReading: Equatable {
    let progress: Double?
    let nextEnd: Date?

    init(_ links: NotchLinkService) {
        progress = links.progress
        nextEnd = links.nextEnd
    }

    func text(now: Date, language: AppLanguage) -> String? {
        NotchLinkSupport.compactReading(progress: progress, nextEnd: nextEnd, now: now,
                                        locale: Locale(identifier: language.rawValue))
    }

    static func status(_ links: NotchLinkService, language: AppLanguage) -> String {
        let text = FeatureStrings.notchLinks(language)
        if let progress = links.progress {
            return text.downloading(progress.formatted(.percent.precision(.fractionLength(0))))
        }
        guard let end = links.nextEnd else { return text.untilStoppedDetail }
        return text.endsIn(NotchLinkSupport.timeLeft(until: end, now: Date(), locale: language.formattingLocale()))
    }
}

/// The closed island while links are shared: the link's mark left of the
/// camera, and on the right a download's progress while one runs, or the
/// time the next link to end has left, or infinity when none of them ends.
/// Both open the Links page.
struct NotchLinkStrip: View {
    @ObservedObject var service: NotchService
    /// Where the island draws it: its own strip as of the last update, or
    /// another display's when the island shows on every display.
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var links = NotchLinkService.shared
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        // The last link ending clears the reading before the strip has left.
        NotchStripHold(NotchLinkReading(links), shows: links.isActive) { reading in
            // A countdown changes once a minute; progress comes with each reading.
            TimelineView(.periodic(from: .now, by: 60)) { context in
                strip(reading.text(now: context.date, language: l10n.language))
            }
        }
    }

    private func strip(_ reading: String?) -> some View {
        let geometry = displayGeometry ?? service.compactActivityGeometry
        let height = geometry.compactActivityContentHeight
        let wing = geometry.compactActivityWingWidth
        let iconSize = NotchTimerSupport.stripIconSize(height: height)
        let textSize = NotchTimerSupport.stripTextSize(height: height)
        return Button { service.openActivity(.links) } label: {
            HStack(spacing: 0) {
                Group {
                    if wing >= 28 {
                        Image(systemName: NotchLinkSupport.symbol)
                            .font(.system(size: iconSize, weight: .semibold))
                    }
                }
                .padding(.leading, geometry.compactActivityEdgeInset(boxHeight: iconSize, radius: iconSize / 2))
                .frame(width: wing, height: height, alignment: .leading)
                Color.clear.frame(width: geometry.compactActivityCameraGap)
                Group {
                    if wing >= 42 {
                        if let reading {
                            Text(reading)
                                .font(.system(size: textSize, weight: .medium)).monospacedDigit()
                                .lineLimit(1).minimumScaleFactor(0.65)
                                // A reading that gains or loses a character
                                // resizes the wings; the service measures the same.
                                .onChange(of: NotchAgentSupport.readingShape(reading)) { _, _ in
                                    DispatchQueue.main.async { service.refreshPresentation() }
                                }
                        } else {
                            Image(systemName: NotchLinkSupport.openSymbol)
                                .font(.system(size: textSize, weight: .medium))
                        }
                    }
                }
                // Digits carry no descenders, so their ink is about the cap height.
                .padding(.trailing, geometry.compactActivityEdgeInset(boxHeight: textSize * 0.72, radius: 0))
                .frame(width: wing, height: height, alignment: .trailing)
            }
            .foregroundStyle(.cyan)
            .frame(height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, geometry.compactActivityHorizontalPadding)
        .padding(.top, geometry.compactActivityTopPadding)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(FeatureStrings.notchLinks(l10n.language).title)
        .accessibilityValue(NotchLinkReading.status(links, language: l10n.language))
        .accessibilityHint(FeatureStrings.notch(l10n.language).open)
        .accessibilityIdentifier("notch.links")
    }
}
