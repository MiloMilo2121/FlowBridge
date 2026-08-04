// Il nastro armonico e' l'unica immagine del marchio: sta nel layer condiviso,
// non dentro un target di una sola piattaforma. iOS e la console macOS devono
// disegnare lo stesso identico tracciato — le armoniche 20.1/42.7/71.3 e
// l'envelope sin^1.15 vengono dal design system, non dal caso.
#if canImport(UIKit) || canImport(AppKit)
import SwiftUI

/// The signature: a mesh of drifting voice-lines, ported 1:1 from the
/// "Mesh Waveform" design reference.
///
/// 54 phase-shifted lines sampled 96 times across the width, tapered by a
/// sin^1.15 envelope; every 9th line is a brighter crest. Ready state
/// drifts slowly in violet; live runs 3× faster in orange and is driven by
/// the real microphone energy (`level`), interpolated render-side so a
/// ~24Hz signal still reads as continuous. All lines batch into two stroke
/// calls per frame. Under Reduce Motion the timeline pauses and a single
/// static frame is drawn.
public struct MeshWaveformView: View {
    var live: Bool
    var level: Float = 0
    var lines: Int = 54
    var speed: Double = 1
    var paused: Bool = false

    /// `live` cambia colore e velocita': viola in attesa, arancio in cattura.
    /// `level` e' l'energia reale del microfono, 0…1.
    public init(live: Bool, level: Float = 0, lines: Int = 54,
                speed: Double = 1, paused: Bool = false) {
        self.live = live
        self.level = level
        self.lines = lines
        self.speed = speed
        self.paused = paused
    }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clock = MeshClock()

    public var body: some View {
        TimelineView(.animation(minimumInterval: live ? 1 / 60 : 1 / 30, paused: paused || reduceMotion)) { timeline in
            Canvas { context, size in
                let (t, drive) = clock.advance(
                    to: timeline.date,
                    speed: speed * (live ? 1.6 : 0.55),
                    targetLevel: live ? Double(max(0, min(1, level))) : 0.5,
                    frozen: paused || reduceMotion
                )
                draw(&context, size: size, t: t, drive: drive)
            }
        }
        .accessibilityHidden(true)
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, t: Double, drive: Double) {
        let width = size.width
        let height = size.height
        let mid = height / 2
        let dark = colorScheme == .dark
        let amp = height * 0.42 * (live ? 1 : 0.8)

        var hairline = Path()
        hairline.move(to: CGPoint(x: 0, y: mid))
        hairline.addLine(to: CGPoint(x: width, y: mid))
        context.stroke(hairline, with: .color(FlowPalette.meshHairline(dark: dark)), lineWidth: 1)

        let samples = 96
        var basePath = Path()
        var crestPath = Path()

        for k in 0..<max(1, lines) {
            let lineT = t + Double(k) * 0.048
            let sway = 0.72 + 0.28 * sin(Double(k) * 0.37 + t * 0.5)
            var isFirst = true
            let isCrest = k % 9 == 0

            for i in 0...samples {
                let u = Double(i) / Double(samples)
                let envelope = pow(max(0, sin(.pi * u)), 1.15)
                let v = voice(u * 1.05, lineT, drive) * sway
                let point = CGPoint(x: width * u, y: mid + v * amp * envelope)
                if isFirst {
                    if isCrest { crestPath.move(to: point) } else { basePath.move(to: point) }
                    isFirst = false
                } else {
                    if isCrest { crestPath.addLine(to: point) } else { basePath.addLine(to: point) }
                }
            }
        }

        let base = FlowPalette.meshBase(live: live, dark: dark)
        let crest = FlowPalette.meshCrest(live: live, dark: dark)
        context.stroke(basePath, with: .color(base.opacity(0.10)), style: StrokeStyle(lineWidth: 0.55))
        context.stroke(crestPath, with: .color(crest.opacity(0.38)), style: StrokeStyle(lineWidth: 1.1))
    }

    /// The voice signal: a syllable envelope (slow sines + the mic drive)
    /// gating three incommensurate harmonics — speech-like, never periodic.
    private func voice(_ u: Double, _ t: Double, _ d: Double) -> Double {
        let syllable = 0.30 + 0.70 * max(0, 0.55 * sin(t * 2.1 + u * 3.0) + 0.35 * sin(t * 0.9 + 1.7) + d * 0.9 - 0.25)
        let harmonics = 0.52 * sin(u * 20.1 + t * 1.15)
            + 0.30 * sin(u * 42.7 - t * 1.65 + 1.2)
            + 0.18 * sin(u * 71.3 + t * 0.75 + 2.4)
        return syllable * harmonics
    }
}

/// Render-side integrator: accumulates phase so speed changes never jump,
/// and eases the published mic level toward its target so a low-rate signal
/// animates smoothly at 60fps. Mutated only inside Canvas rendering.
private final class MeshClock {
    private var t: Double = 5
    private var lastDate: Date?
    private var level: Double = 0.5

    func advance(to date: Date, speed: Double, targetLevel: Double, frozen: Bool) -> (t: Double, drive: Double) {
        guard !frozen else { return (t, 0.5) }
        let dt = min(0.1, max(0, date.timeIntervalSince(lastDate ?? date)))
        lastDate = date
        t += dt * speed
        // Rise fast on speech onset, release a touch slower — reads as natural.
        let rate = targetLevel > level ? 14.0 : 8.0
        level += (targetLevel - level) * min(1, dt * rate)
        return (t, 0.25 + level * 0.75)
    }
}
#endif
