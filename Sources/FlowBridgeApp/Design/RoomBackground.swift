import FlowBridgeShared
import SwiftUI

/// The room every screen sits in. Dark: a deep near-black base with a slow
/// violet aurora breathing behind the orb — hue never moves (violet means
/// "listening"; intensity is the only thing allowed to react). Light: the
/// system background with one quiet violet wash — the full aurora reads
/// dirty on white.
///
/// `intensity` is the single reactive scalar (idle 0.35 → ready 0.75);
/// when `listens` is true the aurora additionally reads the mic level per
/// frame (same discipline as the Orb: no @Published storm).
struct RoomBackground: View {
    var intensity: Double = 0.35
    var listens: Bool = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [FlowTheme.roomTop, FlowTheme.roomBottom],
                startPoint: .top,
                endPoint: .bottom
            )

            if showsAurora {
                if scheme == .dark {
                    AuroraLayer(
                        intensity: cappedIntensity,
                        listens: listens,
                        frozen: reduceMotion
                    )
                } else {
                    // Light: one wash, no motion.
                    RadialGradient(
                        colors: [FlowTheme.accent.opacity(0.05 + 0.04 * cappedIntensity), .clear],
                        center: UnitPoint(x: 0.5, y: 0.30),
                        startRadius: 0,
                        endRadius: 440
                    )
                }
            }
        }
        .ignoresSafeArea()
        .animation(FlowMotion.drift, value: intensity)
    }

    private var showsAurora: Bool {
        !reduceTransparency
    }

    private var cappedIntensity: Double {
        contrast == .increased ? min(intensity, 0.2) : intensity
    }
}

/// The breathing violet field: a 3×3 mesh whose two accent knots drift on
/// incommensurate sine periods (23/31/41s) so the motion never visibly
/// loops. Peak opacity stays ≤0.14 — `.secondary` text keeps its contrast
/// anywhere on the room.
private struct AuroraLayer: View {
    let intensity: Double
    let listens: Bool
    let frozen: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: frozen ? nil : (listens ? 1 / 30 : 1 / 12), paused: frozen && !listens)) { timeline in
            let t = frozen ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let level = listens ? Double(AudioLevelMeter.shared.latestLevel) : 0
            let energy = min(1, intensity + 0.35 * level)

            MeshGradient(
                width: 3,
                height: 3,
                points: knotPositions(t: t),
                colors: knotColors(energy: energy)
            )
        }
    }

    private func knotPositions(t: TimeInterval) -> [SIMD2<Float>] {
        // Two live knots (violet, behind/above the orb's resting position);
        // the rest anchor the mesh at the borders.
        let ax = Float(0.32 + 0.06 * sin(2 * .pi * t / 23))
        let ay = Float(0.34 + 0.05 * sin(2 * .pi * t / 31))
        let bx = Float(0.72 + 0.06 * sin(2 * .pi * t / 41 + 1.7))
        let by = Float(0.52 + 0.05 * sin(2 * .pi * t / 29 + 0.6))

        return [
            [0, 0], [0.5, 0], [1, 0],
            [0, 0.5], [ax, ay], [1, 0.5],
            [0, 1], [bx, by], [1, 1],
        ]
    }

    private func knotColors(energy: Double) -> [Color] {
        let violet = FlowTheme.accent.opacity(min(0.14, 0.16 * energy))
        let deep = FlowTheme.accentDeep.opacity(min(0.10, 0.12 * energy))
        return [
            .clear, .clear, .clear,
            .clear, violet, .clear,
            .clear, deep, .clear,
        ]
    }
}
