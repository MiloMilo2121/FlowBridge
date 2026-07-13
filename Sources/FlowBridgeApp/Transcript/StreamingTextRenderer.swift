import SwiftUI

/// Per-word arrival stamp carried through the Text layout to the renderer.
struct WordStampAttribute: TextAttribute {
    let arrival: Date
    let isVolatile: Bool
}

/// Draw-time word arrival: layout is computed once per string change (the
/// glyphs' final resting positions), the renderer merely draws young runs
/// faded/risen during their first 420ms — so the layout can never dance,
/// by construction. The volatile tail breathes; a caret pulses after the
/// last run.
struct StreamingTextRenderer: TextRenderer {
    /// Fed per-frame by a TimelineView; the renderer itself stores nothing.
    var now: TimeInterval
    /// Condensing: everything settles, no arrivals, no caret.
    var frozen: Bool
    /// Reduce Motion: fade-only arrivals, solid caret.
    var reduceMotion: Bool
    var accent: Color

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        var lastRun: Text.Layout.Run?

        for line in layout {
            for run in line {
                lastRun = run
                var runContext = context
                let stamp = run[WordStampAttribute.self]

                if let stamp {
                    if stamp.isVolatile {
                        let breathe = frozen ? 0.55 : 0.55 + 0.07 * sin(2 * .pi * now / 1.6)
                        runContext.opacity = breathe
                    }
                    if !frozen {
                        let age = now - stamp.arrival.timeIntervalSinceReferenceDate
                        if age >= 0, age < 0.42 {
                            let p = age / 0.42
                            let eased = p * p * (3 - 2 * p)
                            runContext.opacity *= max(0.001, eased)
                            if !reduceMotion {
                                runContext.translateBy(x: 0, y: (1 - eased) * 7)
                            }
                        }
                    }
                }
                runContext.draw(run)
            }
        }

        // Trailing caret: a 2pt beam pulsing after the last glyph run —
        // positioned from typographic bounds, never from layout hacks.
        if !frozen, let last = lastRun {
            let bounds = last.typographicBounds.rect
            let pulse = reduceMotion ? 0.7 : 0.5 + 0.5 * sin(2 * .pi * now / 1.6)
            let caret = CGRect(
                x: bounds.maxX + 3,
                y: bounds.minY + 2,
                width: 2,
                height: max(4, bounds.height - 4)
            )
            context.fill(
                Path(roundedRect: caret, cornerRadius: 1),
                with: .color(accent.opacity(0.30 + 0.45 * pulse))
            )
        }
    }
}
