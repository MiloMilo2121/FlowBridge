import FlowBridgeShared
import SwiftUI

/// The shareable recap: rendered on-device by `ImageRenderer`, never by a
/// server. 4:5 dark card in the brand room style.
struct RecapCardView: View {
    let stats: DictationStatsStore.Stats
    let streak: Int

    var body: some View {
        VStack(alignment: .leading, spacing: FlowTheme.space16) {
            HStack(spacing: FlowTheme.space8) {
                Image(systemName: "waveform")
                    .font(.headline)
                    .foregroundStyle(FlowTheme.accentGradient)
                Text("FlowBridge")
                    .font(.headline)
                    .foregroundStyle(.white)
            }

            Spacer()

            Text("\(Int(stats.timeSavedMinutes.rounded()))")
                .font(FlowTheme.numeric(96, weight: .bold))
                .foregroundStyle(FlowTheme.accentGradient)
            Text("minutes given back by speaking\ninstead of typing")
                .font(.title3.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))

            HStack(spacing: FlowTheme.space12) {
                recapChip("\(stats.words)", "words")
                recapChip("\(stats.sessions)", "dictations")
                if streak > 1 {
                    recapChip("\(streak)", "day streak")
                }
            }
            .padding(.top, FlowTheme.space8)

            Spacer()

            Text("100% on-device · no cloud · no account")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(FlowTheme.space28)
        .frame(width: 360, height: 450, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.063, green: 0.059, blue: 0.102), // #100F1A
                    Color(red: 0.043, green: 0.043, blue: 0.071), // #0B0B12
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .environment(\.colorScheme, .dark)
    }

    private func recapChip(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(FlowTheme.numeric(20, weight: .semibold))
                .foregroundStyle(.white)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, FlowTheme.space12)
        .padding(.vertical, FlowTheme.space8)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: FlowTheme.radiusControl, style: .continuous))
    }
}
