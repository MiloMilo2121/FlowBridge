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
                        Button("Done") { dismiss() }
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FlowTheme.space16) {
                chips

                streakCard

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
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(FlowTheme.accent)
                }
            }
            .padding(FlowTheme.space20)
        }
        .task { reload() }
        .onChange(of: range) { _, _ in reload() }
    }

    // MARK: - Cards

    private var chips: some View {
        Grid(horizontalSpacing: FlowTheme.space12, verticalSpacing: FlowTheme.space12) {
            GridRow {
                chip(value: "\(Int(stats.timeSavedMinutes.rounded()))", unit: "min given back", icon: "hourglass")
                chip(value: "\(stats.words)", unit: "words", icon: "text.word.spacing")
            }
            GridRow {
                chip(value: "\(stats.sessions)", unit: "dictations", icon: "waveform")
                chip(value: stats.wordsPerMinute.formatted(.number.precision(.fractionLength(0))), unit: "wpm", icon: "speedometer")
            }
        }
    }

    private func chip(value: String, unit: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: FlowTheme.space4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(FlowTheme.accent)
            Text(value)
                .font(FlowTheme.numeric(24, weight: .bold))
                .contentTransition(.numericText())
            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(FlowTheme.space16)
        .flowCard()
    }

    private var streakCard: some View {
        HStack(spacing: FlowTheme.space16) {
            VStack(alignment: .leading, spacing: FlowTheme.space4) {
                HStack(spacing: FlowTheme.space4) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(FlowTheme.accent)
                    Text(streak > 0 ? "Day \(streak) in a row" : "Start your streak")
                        .font(.headline)
                        .contentTransition(.numericText())
                }
                Text("One dictation a day keeps the keyboard away.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(week, id: \.day) { day in
                    Circle()
                        .fill(day.sessions > 0 ? AnyShapeStyle(FlowTheme.accentGradient) : AnyShapeStyle(Color.secondary.opacity(0.25)))
                        .frame(width: 10, height: 10)
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
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel()
                        .font(.caption2)
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
