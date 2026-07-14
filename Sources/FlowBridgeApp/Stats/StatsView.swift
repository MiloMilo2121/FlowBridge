import Charts
import FlowBridgeShared
import SwiftUI

/// The story of the time given back: chips, words-per-day, the WPM trend,
/// the streak — computed on this device, shareable as an image rendered on
/// this device.
struct StatsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            StatsContent()
                .navigationTitle("Statistics")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel("Close")
                    }
                }
        }
    }
}

/// The stats body, embeddable both in the sheet and in Settings navigation.
struct StatsContent: View {
    @EnvironmentObject private var coordinator: FlowBridgeCoordinator

    @State private var range: RangeChoice = .week
    @State private var stats = DictationStatsStore.Stats()
    @State private var days: [DictationStatsStore.DayStat] = []
    @State private var week: [DictationStatsStore.DayStat] = []
    @State private var streak = 0
    @State private var recapImage: Image?

    enum RangeChoice: String, CaseIterable, Identifiable {
        case week = "7 days"
        case month = "28 days"

        var id: String { rawValue }

        var dayCount: Int {
            switch self {
            case .week: return 7
            case .month: return 28
            }
        }
    }

    @ScaledMetric(relativeTo: .largeTitle) private var heroNumeral: CGFloat = 64

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FlowTheme.space16) {
                heroBlock

                statStrip

                rhythmRail

                Picker("Range", selection: $range) {
                    ForEach(RangeChoice.allCases) { choice in
                        Text(choice.rawValue).tag(choice)
                    }
                }
                .pickerStyle(.segmented)

                wordsCard

                wpmCard

                if let recapImage {
                    ShareLink(
                        item: recapImage,
                        preview: SharePreview("FlowBridge recap", image: recapImage)
                    ) {
                        Label("Share recap", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .tint(FlowTheme.accent)
                }
            }
            .padding(FlowTheme.space20)
        }
        .background(RoomBackground())
        .scrollEdgeEffectStyle(.soft, for: .top)
        .task { reload() }
        .onChange(of: range) { _, _ in reload() }
    }

    // MARK: - Hero

    /// The one number this screen exists for, directly on the room.
    private var heroBlock: some View {
        VStack(alignment: .leading, spacing: FlowTheme.space4) {
            Text("Time given back").flowEyebrow()
            HStack(alignment: .firstTextBaseline, spacing: FlowTheme.space4) {
                Text("\(Int(stats.timeSavedMinutes.rounded()))")
                    .font(FlowTheme.numeric(heroNumeral, weight: .bold))
                    .contentTransition(.numericText())
                Text("min")
                    .font(FlowTheme.numeric(20))
                    .foregroundStyle(.secondary)
            }
            Text(heroFlavor)
                .font(FlowTheme.serifFlavor(16))
                .foregroundStyle(.secondary)
        }
    }

    private var heroFlavor: String {
        let minutes = Int(stats.timeSavedMinutes.rounded())
        if minutes < 15 { return "your first minutes back" }
        let hours = Double(minutes) / 60
        if hours < 1.5 { return "about an hour of typing" }
        return "about \(Int(hours.rounded())) hours of typing"
    }

    private var statStrip: some View {
        HStack(spacing: 0) {
            stripCell("\(stats.words)", "words")
            Divider().frame(height: 36)
            stripCell("\(stats.sessions)", "dictations")
            Divider().frame(height: 36)
            stripCell(stats.wordsPerMinute.formatted(.number.precision(.fractionLength(0))), "wpm")
        }
        .padding(FlowTheme.space16)
        .flowCard()
    }

    private func stripCell(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(FlowTheme.numeric(20, weight: .semibold))
                .contentTransition(.numericText())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var rhythmRail: some View {
        HStack(spacing: FlowTheme.space16) {
            VStack(alignment: .leading, spacing: FlowTheme.space4) {
                HStack(spacing: FlowTheme.space4) {
                    Image(systemName: "waveform.path")
                        .foregroundStyle(FlowTheme.accent)
                    Text(streak > 0 ? "\(streak)-day voice rhythm" : "Your voice rhythm")
                        .font(.headline)
                        .contentTransition(.numericText())
                }
                Text("A record, not a target. Use voice when it gives time back.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(week, id: \.day) { day in
                    Capsule(style: .continuous)
                        .fill(day.sessions > 0 ? AnyShapeStyle(FlowTheme.accentGradient) : AnyShapeStyle(Color.secondary.opacity(0.18)))
                        .frame(width: 7, height: day.sessions > 0 ? 24 : 9)
                }
            }
        }
        .padding(FlowTheme.space16)
        .flowCard()
    }

    private var wordsCard: some View {
        VStack(alignment: .leading, spacing: FlowTheme.space12) {
            Text("Words per day")
                .font(.headline)
            Chart(days, id: \.day) { day in
                BarMark(
                    x: .value("Day", shortLabel(for: day.day)),
                    y: .value("Words", day.words)
                )
                .foregroundStyle(FlowTheme.accentGradient)
                .cornerRadius(4)
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(.white.opacity(0.06))
                    AxisValueLabel().font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel().font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .frame(height: 160)
        }
        .padding(FlowTheme.space16)
        .flowCard()
    }

    private var wpmCard: some View {
        VStack(alignment: .leading, spacing: FlowTheme.space12) {
            Text("Speaking speed")
                .font(.headline)
            Chart(activeDays, id: \.day) { day in
                LineMark(
                    x: .value("Day", shortLabel(for: day.day)),
                    y: .value("WPM", day.wordsPerMinute)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(FlowTheme.accent)
                AreaMark(
                    x: .value("Day", shortLabel(for: day.day)),
                    y: .value("WPM", day.wordsPerMinute)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(FlowTheme.accent.opacity(0.1))
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(.white.opacity(0.06))
                    AxisValueLabel().font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel().font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .frame(height: 120)
        }
        .padding(FlowTheme.space16)
        .flowCard()
    }

    /// Days with at least one session — a WPM of 0 is "didn't dictate", not
    /// "spoke infinitely slowly".
    private var activeDays: [DictationStatsStore.DayStat] {
        days.filter { $0.sessions > 0 }
    }

    /// "yyyy-MM-dd" → "dd", enough for a compact axis.
    private func shortLabel(for dayKey: String) -> String {
        String(dayKey.suffix(2))
    }

    private func reload() {
        guard let store = coordinator.stats else { return }
        stats = store.stats()
        days = store.daily(last: range.dayCount)
        week = store.daily(last: 7)
        streak = store.currentStreak()
        renderRecap()
    }

    private func renderRecap() {
        let renderer = ImageRenderer(
            content: RecapCardView(stats: stats, streak: streak)
        )
        renderer.scale = 3
        if let image = renderer.uiImage {
            recapImage = Image(uiImage: image)
        }
    }
}
