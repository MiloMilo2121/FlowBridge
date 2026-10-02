// I glifi sono `Shape` puri: geometria, niente di specifico di una
// piattaforma. Restano fuori solo da Linux, dove non c'e' SwiftUI.
#if canImport(UIKit) || canImport(AppKit)
import SwiftUI

/// The «Linea Viva» proprietary icon set (replaces SF Symbols in chrome).
///
/// Construction rules from the design source: 24×24 grid, continuous 1.9pt
/// stroke with round caps and joins, and exactly one "wave gesture" per
/// glyph — three breathing bars or a single undulating line — as the set's
/// waveform signature. Rendered as a `Shape` so any `foregroundStyle` works;
/// the stroke is pre-converted to a fill and scales with the frame.
public struct LineaVivaIcon: Shape {
    public enum Glyph: Sendable {
        case dictate      // mic built from three bars + cradle + stem
        case waveform     // five bars
        case commands     // speech bubble + bars
        case polish       // twin sparkles
        case insert       // arrow into split baseline
        case copy         // clipboard + bars
        case history      // circular arrow + clock hands
        case stats        // four bars
        case vocab        // open book + wave accent
        case engine       // chip + bars
        case language     // globe + wavy equator
        case settings     // two sliders
        case privacy      // shield + bars
        case onDevice     // lock + bars
        case airplane     // airplane silhouette
        case share        // arrow out of tray
        case stop         // filled rounded square
        case close        // ×
        case next         // chevron
    }

    private let glyph: Glyph

    public init(_ glyph: Glyph) {
        self.glyph = glyph
    }

    public func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        let raw = Self.glyphPath(glyph)
        let transform = CGAffineTransform(
            translationX: rect.midX - 12 * scale,
            y: rect.midY - 12 * scale
        ).scaledBy(x: scale, y: scale)
        let placed = raw.applying(transform)

        if glyph == .stop {
            return placed
        }
        return placed.strokedPath(StrokeStyle(lineWidth: 1.9 * scale, lineCap: .round, lineJoin: .round))
    }

    // MARK: Glyph geometry (24×24 space, ported 1:1 from the design SVGs)

    private static func glyphPath(_ glyph: Glyph) -> Path {
        var p = Path()
        switch glyph {
        case .dictate:
            bar(&p, x: 9.7, from: 8.5, to: 13.5)
            bar(&p, x: 12, from: 6.5, to: 15.5)
            bar(&p, x: 14.3, from: 8.5, to: 13.5)
            p.move(to: .init(x: 7, y: 12.5))
            p.addArc(center: .init(x: 12, y: 12.5), radius: 5,
                     startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
            bar(&p, x: 12, from: 18, to: 21)
        case .waveform:
            bar(&p, x: 5, from: 10, to: 14)
            bar(&p, x: 8.5, from: 7.5, to: 16.5)
            bar(&p, x: 12, from: 5, to: 19)
            bar(&p, x: 15.5, from: 8.5, to: 15.5)
            bar(&p, x: 19, from: 10.5, to: 13.5)
        case .commands:
            p.addRoundedRect(in: .init(x: 4, y: 4.5, width: 16, height: 11.5), cornerSize: .init(width: 4, height: 4))
            p.move(to: .init(x: 8.5, y: 16))
            p.addLine(to: .init(x: 8.5, y: 19.2))
            p.addLine(to: .init(x: 12, y: 16))
            bar(&p, x: 9.5, from: 8, to: 12.5)
            bar(&p, x: 12, from: 7, to: 13.5)
            bar(&p, x: 14.5, from: 8.5, to: 12)
        case .polish:
            p.move(to: .init(x: 12, y: 4.5))
            p.addCurve(to: .init(x: 16.9, y: 9.5), control1: .init(x: 12.45, y: 7.5), control2: .init(x: 13.9, y: 9.05))
            p.addCurve(to: .init(x: 12, y: 14.5), control1: .init(x: 13.9, y: 9.95), control2: .init(x: 12.45, y: 11.5))
            p.addCurve(to: .init(x: 7.1, y: 9.5), control1: .init(x: 11.55, y: 11.5), control2: .init(x: 10.1, y: 9.95))
            p.addCurve(to: .init(x: 12, y: 4.5), control1: .init(x: 10.1, y: 9.05), control2: .init(x: 11.55, y: 7.5))
            p.closeSubpath()
            p.move(to: .init(x: 18, y: 14.5))
            p.addCurve(to: .init(x: 20.75, y: 17.3), control1: .init(x: 18.25, y: 16.2), control2: .init(x: 19.05, y: 17.05))
            p.addCurve(to: .init(x: 18, y: 20.1), control1: .init(x: 19.05, y: 17.55), control2: .init(x: 18.25, y: 18.4))
            p.addCurve(to: .init(x: 15.25, y: 17.3), control1: .init(x: 17.75, y: 18.4), control2: .init(x: 16.95, y: 17.55))
            p.addCurve(to: .init(x: 18, y: 14.5), control1: .init(x: 16.95, y: 17.05), control2: .init(x: 17.75, y: 16.2))
            p.closeSubpath()
        case .insert:
            bar(&p, x: 12, from: 5.5, to: 14.5)
            p.move(to: .init(x: 9, y: 11.5))
            p.addLine(to: .init(x: 12, y: 14.5))
            p.addLine(to: .init(x: 15, y: 11.5))
            p.move(to: .init(x: 4, y: 19))
            p.addLine(to: .init(x: 9, y: 19))
            p.move(to: .init(x: 15, y: 19))
            p.addLine(to: .init(x: 20, y: 19))
        case .copy:
            p.move(to: .init(x: 9, y: 3.5))
            p.addLine(to: .init(x: 17, y: 3.5))
            p.addArc(center: .init(x: 17, y: 6), radius: 2.5,
                     startAngle: .degrees(270), endAngle: .degrees(360), clockwise: false)
            p.addLine(to: .init(x: 19.5, y: 14))
            p.addRoundedRect(in: .init(x: 4.5, y: 7.5, width: 11, height: 13), cornerSize: .init(width: 2.5, height: 2.5))
            bar(&p, x: 8, from: 12.5, to: 15.5)
            bar(&p, x: 10, from: 11.5, to: 16.5)
            bar(&p, x: 12, from: 13, to: 15)
        case .history:
            p.move(to: .init(x: 12, y: 4))
            p.addArc(center: .init(x: 12, y: 12), radius: 8,
                     startAngle: .degrees(270), endAngle: .degrees(0), clockwise: true)
            p.move(to: .init(x: 12, y: 1.5))
            p.addLine(to: .init(x: 9.5, y: 4))
            p.addLine(to: .init(x: 12, y: 6.5))
            p.move(to: .init(x: 12, y: 8.5))
            p.addLine(to: .init(x: 12, y: 12))
            p.addLine(to: .init(x: 14.8, y: 13.7))
        case .stats:
            bar(&p, x: 5.5, from: 15.5, to: 19.5)
            bar(&p, x: 10, from: 11.5, to: 19.5)
            bar(&p, x: 14.5, from: 14, to: 19.5)
            bar(&p, x: 19, from: 8.5, to: 19.5)
        case .vocab:
            p.move(to: .init(x: 12, y: 6.3))
            p.addCurve(to: .init(x: 4.5, y: 4.9), control1: .init(x: 10, y: 4.7), control2: .init(x: 7.3, y: 4.4))
            p.addLine(to: .init(x: 4.5, y: 18.3))
            p.addCurve(to: .init(x: 12, y: 19.7), control1: .init(x: 7.3, y: 17.8), control2: .init(x: 10, y: 18.1))
            p.addCurve(to: .init(x: 19.5, y: 18.3), control1: .init(x: 14, y: 18.1), control2: .init(x: 16.7, y: 17.8))
            p.addLine(to: .init(x: 19.5, y: 4.9))
            p.addCurve(to: .init(x: 12, y: 6.3), control1: .init(x: 16.7, y: 4.4), control2: .init(x: 14, y: 4.7))
            p.closeSubpath()
            p.move(to: .init(x: 12, y: 6.3))
            p.addLine(to: .init(x: 12, y: 19.7))
            p.move(to: .init(x: 14.8, y: 10.5))
            p.addCurve(to: .init(x: 18, y: 10.5), control1: .init(x: 15.8, y: 9.6), control2: .init(x: 17, y: 9.6))
        case .engine:
            p.addRoundedRect(in: .init(x: 7, y: 7, width: 10, height: 10), cornerSize: .init(width: 2.5, height: 2.5))
            bar(&p, x: 9.5, from: 4.2, to: 7)
            bar(&p, x: 14.5, from: 4.2, to: 7)
            bar(&p, x: 9.5, from: 17, to: 19.8)
            bar(&p, x: 14.5, from: 17, to: 19.8)
            hbar(&p, y: 9.5, from: 4.2, to: 7)
            hbar(&p, y: 14.5, from: 4.2, to: 7)
            hbar(&p, y: 9.5, from: 17, to: 19.8)
            hbar(&p, y: 14.5, from: 17, to: 19.8)
            bar(&p, x: 10.3, from: 10.8, to: 13.2)
            bar(&p, x: 12, from: 9.8, to: 14.2)
            bar(&p, x: 13.7, from: 10.8, to: 13.2)
        case .language:
            p.addEllipse(in: .init(x: 4, y: 4, width: 16, height: 16))
            p.move(to: .init(x: 12, y: 4))
            p.addCurve(to: .init(x: 12, y: 20), control1: .init(x: 9.1, y: 6.1), control2: .init(x: 9.1, y: 17.9))
            p.move(to: .init(x: 12, y: 4))
            p.addCurve(to: .init(x: 12, y: 20), control1: .init(x: 14.9, y: 6.1), control2: .init(x: 14.9, y: 17.9))
            p.move(to: .init(x: 4.6, y: 11.2))
            p.addCurve(to: .init(x: 12, y: 11.2), control1: .init(x: 7, y: 10.2), control2: .init(x: 9.5, y: 10.2))
            p.addCurve(to: .init(x: 19.4, y: 11.2), control1: .init(x: 14.5, y: 12.2), control2: .init(x: 17, y: 12.2))
        case .settings:
            hbar(&p, y: 8.5, from: 4, to: 7)
            p.addEllipse(in: .init(x: 7.5, y: 6.2, width: 4.6, height: 4.6))
            hbar(&p, y: 8.5, from: 12.6, to: 20)
            hbar(&p, y: 15.5, from: 4, to: 11.4)
            p.addEllipse(in: .init(x: 11.9, y: 13.2, width: 4.6, height: 4.6))
            hbar(&p, y: 15.5, from: 17, to: 20)
        case .privacy:
            p.move(to: .init(x: 12, y: 3.2))
            p.addLine(to: .init(x: 19, y: 5.8))
            p.addLine(to: .init(x: 19, y: 11.2))
            p.addCurve(to: .init(x: 12, y: 20.5), control1: .init(x: 19, y: 15.8), control2: .init(x: 16, y: 18.8))
            p.addCurve(to: .init(x: 5, y: 11.2), control1: .init(x: 8, y: 18.8), control2: .init(x: 5, y: 15.8))
            p.addLine(to: .init(x: 5, y: 5.8))
            p.closeSubpath()
            bar(&p, x: 9.8, from: 10.4, to: 13.1)
            bar(&p, x: 12, from: 9.2, to: 14.3)
            bar(&p, x: 14.2, from: 10.4, to: 13.1)
        case .onDevice:
            p.addRoundedRect(in: .init(x: 5.5, y: 10.5, width: 13, height: 9), cornerSize: .init(width: 3, height: 3))
            p.move(to: .init(x: 8.5, y: 10.5))
            p.addLine(to: .init(x: 8.5, y: 8.2))
            p.addArc(center: .init(x: 12, y: 8.2), radius: 3.5,
                     startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            p.addLine(to: .init(x: 15.5, y: 10.5))
            bar(&p, x: 10.2, from: 13.6, to: 16.2)
            bar(&p, x: 12, from: 12.8, to: 17)
            bar(&p, x: 13.8, from: 13.6, to: 16.2)
        case .airplane:
            p.move(to: .init(x: 12, y: 3.6))
            p.addLine(to: .init(x: 12, y: 10.2))
            p.addLine(to: .init(x: 19.6, y: 13.5))
            p.addLine(to: .init(x: 19.6, y: 15.5))
            p.addLine(to: .init(x: 12, y: 13.5))
            p.addLine(to: .init(x: 12, y: 17.3))
            p.addLine(to: .init(x: 14.4, y: 19.2))
            p.addLine(to: .init(x: 14.4, y: 20.8))
            p.addLine(to: .init(x: 12, y: 20))
            p.addLine(to: .init(x: 9.6, y: 20.8))
            p.addLine(to: .init(x: 9.6, y: 19.2))
            p.addLine(to: .init(x: 12, y: 17.3))
            p.addLine(to: .init(x: 12, y: 13.5))
            p.addLine(to: .init(x: 4.4, y: 15.5))
            p.addLine(to: .init(x: 4.4, y: 13.5))
            p.addLine(to: .init(x: 12, y: 10.2))
            p.closeSubpath()
        case .share:
            bar(&p, x: 12, from: 3.2, to: 13.5)
            p.move(to: .init(x: 8.6, y: 6.4))
            p.addLine(to: .init(x: 12, y: 3))
            p.addLine(to: .init(x: 15.4, y: 6.4))
            p.move(to: .init(x: 7.5, y: 10.5))
            p.addLine(to: .init(x: 6, y: 10.5))
            p.addArc(center: .init(x: 6, y: 12.5), radius: 2,
                     startAngle: .degrees(270), endAngle: .degrees(180), clockwise: true)
            p.addLine(to: .init(x: 4, y: 18.5))
            p.addArc(center: .init(x: 6, y: 18.5), radius: 2,
                     startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
            p.addLine(to: .init(x: 18, y: 20.5))
            p.addArc(center: .init(x: 18, y: 18.5), radius: 2,
                     startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true)
            p.addLine(to: .init(x: 20, y: 12.5))
            p.addArc(center: .init(x: 18, y: 12.5), radius: 2,
                     startAngle: .degrees(360), endAngle: .degrees(270), clockwise: true)
            p.addLine(to: .init(x: 16.5, y: 10.5))
        case .stop:
            p.addRoundedRect(in: .init(x: 7, y: 7, width: 10, height: 10), cornerSize: .init(width: 2.6, height: 2.6))
        case .close:
            p.move(to: .init(x: 6.8, y: 6.8))
            p.addLine(to: .init(x: 17.2, y: 17.2))
            p.move(to: .init(x: 17.2, y: 6.8))
            p.addLine(to: .init(x: 6.8, y: 17.2))
        case .next:
            p.move(to: .init(x: 9.7, y: 5.7))
            p.addLine(to: .init(x: 16, y: 12))
            p.addLine(to: .init(x: 9.7, y: 18.3))
        }
        return p
    }

    private static func bar(_ p: inout Path, x: CGFloat, from y0: CGFloat, to y1: CGFloat) {
        p.move(to: .init(x: x, y: y0))
        p.addLine(to: .init(x: x, y: y1))
    }

    private static func hbar(_ p: inout Path, y: CGFloat, from x0: CGFloat, to x1: CGFloat) {
        p.move(to: .init(x: x0, y: y))
        p.addLine(to: .init(x: x1, y: y))
    }
}

/// The 40pt tinted chip behind a Linea Viva glyph (design: radius 12,
/// tint background + colored glyph; violet by default, green strictly for
/// privacy, orange strictly for live).
public struct LineaVivaChip: View {
    public enum Tone: Sendable {
        case violet, green, orange
    }

    private let glyph: LineaVivaIcon.Glyph
    private let tone: Tone
    private let size: CGFloat

    public init(_ glyph: LineaVivaIcon.Glyph, tone: Tone = .violet, size: CGFloat = 40) {
        self.glyph = glyph
        self.tone = tone
        self.size = size
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(background)
            .frame(width: size, height: size)
            .overlay {
                LineaVivaIcon(glyph)
                    .foregroundStyle(foreground)
                    .frame(width: size * 0.55, height: size * 0.55)
            }
    }

    private var background: Color {
        switch tone {
        case .violet: return FlowPalette.chipVioletBackground
        case .green: return FlowPalette.chipGreenBackground
        case .orange: return FlowPalette.chipOrangeBackground
        }
    }

    private var foreground: Color {
        switch tone {
        case .violet: return FlowPalette.chipVioletForeground
        case .green: return FlowPalette.chipGreenForeground
        case .orange: return FlowPalette.chipOrangeForeground
        }
    }
}
#endif
