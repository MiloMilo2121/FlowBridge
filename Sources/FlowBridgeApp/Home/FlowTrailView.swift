import FlowBridgeShared
import SwiftUI
import UIKit

/// Fills the home below the recorder: the "time given back" strip and the
/// most recent dictations — the flow you've already banked. Reuses the
/// existing stats + history stores; no new persistence.
struct FlowTrailView: View {
    @EnvironmentObject private var coordinator: FlowBridgeCoordinator
    var openHistory: () -> Void

    @State private var stats = DictationStatsStore.Stats()
    @State private var recents: [TranscriptRecord] = []

    var body: some View {
        VStack(spacing: FlowTheme.Spacing.stack) {
            if isEmpty {
                emptyCard
            } else {
                statsStrip
                recentSection
            }
        }
        .task { await reload() }
        .onChange(of: coordinator.lastTranscript?.id) { _, _ in
            // `withAnimation`'s body is non-escaping, so the async reload has
            // to be wrapped in a Task; only the apply step is animated.
            Task { await reload(animated: true) }
        }
    }

    private var isEmpty: Bool { stats.sessions == 0 && recents.isEmpty }

    /// `TranscriptHistoryStore` is an actor, so reading it suspends: keep the
    /// animation decision at the apply step rather than around the read.
    private func reload(animated: Bool = false) async {
        let entries = await coordinator.history?.all() ?? []
        let newStats = coordinator.stats?.stats() ?? DictationStatsStore.Stats()
        let newRecents = Array(entries.prefix(3).map(\.record))
        if animated {
            withAnimation(FlowTheme.Motion.base) {
                stats = newStats
                recents = newRecents
            }
        } else {
            stats = newStats
            recents = newRecents
        }
    }

    // MARK: Stats strip

    private var statsStrip: some View {
        VStack(alignment: .leading, spacing: FlowTheme.Spacing.m) {
            CapsLabel(text: "Time given back", glyph: .stats)
            HStack(spacing: 0) {
                StatTile(
                    value: stats.timeSavedMinutes.formatted(.number.precision(.fractionLength(0))),
                    unit: "min", label: "given back", hero: true
                )
                divider
                StatTile(value: "\(stats.words)", label: "words")
                divider
                StatTile(value: "\(stats.sessions)", label: "dictations")
            }
        }
        .glassCard()
    }

    private var divider: some View {
        Rectangle()
            .fill(FlowPalette.hairline)
            .frame(width: 1, height: 34)
    }

    // MARK: Recent

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: FlowTheme.Spacing.s) {
            HStack {
                CapsLabel(text: "Recent", glyph: .history)
                Spacer()
                Button(action: openHistory) {
                    Text("See all")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(FlowPalette.accent)
                }
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(recents.enumerated()), id: \.element.id) { index, record in
                    if index > 0 {
                        Rectangle().fill(FlowPalette.hairline).frame(height: 1).padding(.leading, 46)
                    }
                    RecentRow(record: record, copy: copy)
                }
            }
            .glassCard(padding: FlowTheme.Spacing.s)
        }
    }

    private func copy(_ record: TranscriptRecord) {
        UIPasteboard.general.string = record.text
        HapticPlayer.transcriptReady()
    }

    // MARK: Empty

    private var emptyCard: some View {
        VStack(spacing: FlowTheme.Spacing.s) {
            LineaVivaIcon(.waveform)
                .foregroundStyle(FlowPalette.accent.opacity(0.7))
                .frame(width: 30, height: 30)
            Text("Your flow starts here")
                .font(.headline)
                .foregroundStyle(FlowPalette.textBody)
            Text("Tap Record and speak — your words and the time you save land here.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(FlowPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, FlowTheme.Spacing.m)
        .glassCard()
    }
}

private struct StatTile: View {
    let value: String
    var unit: String? = nil
    let label: String
    var hero: Bool = false

    var body: some View {
        VStack(spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(hero ? .title : .title3, design: .rounded).weight(hero ? .bold : .semibold))
                    .foregroundStyle(hero ? FlowPalette.accent : FlowPalette.textBody)
                    .contentTransition(.numericText())
                if let unit {
                    Text(unit)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(FlowPalette.textTertiary)
                }
            }
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .kerning(0.6)
                .foregroundStyle(FlowPalette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

private struct RecentRow: View {
    let record: TranscriptRecord
    let copy: (TranscriptRecord) -> Void

    var body: some View {
        Button {
            copy(record)
        } label: {
            HStack(spacing: FlowTheme.Spacing.m) {
                LineaVivaChip(.history, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.text)
                        .font(.subheadline.italic())
                        .fontDesign(.serif)
                        .foregroundStyle(FlowPalette.textBody)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(record.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(FlowPalette.textTertiary)
                }
                Spacer(minLength: 0)
                LineaVivaIcon(.copy)
                    .foregroundStyle(FlowPalette.textTertiary)
                    .frame(width: 15, height: 15)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copy dictation: \(record.text)")
    }
}
