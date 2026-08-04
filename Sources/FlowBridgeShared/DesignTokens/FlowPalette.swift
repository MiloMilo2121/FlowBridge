// I token vivono dove c'e' una libreria di UI — UIKit su iOS, AppKit su macOS.
// Il framework condiviso si compila anche su Linux per la CI, dove questo file
// sparisce per intero.
//
// La differenza fra le due piattaforme sta tutta in `ColorePiattaforma.swift`:
// qui sotto ci sono solo i token, che non sanno su cosa girano.
#if canImport(UIKit) || canImport(AppKit)
import SwiftUI

/// FlowBridge design tokens — single source of truth for every target.
///
/// Ported from the flowbridge-design-system (Claude Design): violet is the
/// bridge/primary hue, orange is live capture, green appears only for
/// privacy/done, red only for stop/destructive. Light and dark variants
/// resolve through dynamic `UIColor` providers so the app, widgets, and
/// Live Activity can never diverge again (this file replaces the two
/// hardcoded state-color maps that disagreed on `transcribing`).
public enum FlowPalette {
    // MARK: Violet ramp (bridge / primary)

    public static let violet300 = fixed(0xB3A4F2)
    public static let violet400 = fixed(0x9483EF)
    public static let violet500 = fixed(0x7C66F2)
    public static let violet600 = fixed(0x6A52E4)
    public static let violet700 = fixed(0x5940C8)

    // MARK: Orange ramp (live capture / attention)

    public static let orange300 = fixed(0xF9AE62)
    public static let orange400 = fixed(0xFB8C2E)
    public static let orange500 = fixed(0xF2740D)
    public static let orange600 = fixed(0xE05F04)

    // MARK: Green (privacy / done) — never used for anything else

    public static let green500 = fixed(0x34C759)
    public static let green600 = fixed(0x1F9D45)

    // MARK: Red (stop / destructive) — never used for anything else

    public static let red500 = fixed(0xFF3B30)
    public static let red600 = fixed(0xE0281D)

    // MARK: Semantic state tokens (shared by app UI and Live Activity)

    public static let stateReady = violet500
    public static let stateLive = orange500
    public static let statePrivate = green500
    public static let stateStop = red500
    public static let stateFailed = orange600

    // MARK: Adaptive accent + text

    public static let accent = adaptive(light: 0x7C66F2, dark: 0x8B77F6)
    public static let accentStrong = adaptive(light: 0x6A52E4, dark: 0x9C8BF8)
    public static let textBody = adaptive(light: 0x0B0A10, dark: 0xF4F2FA)
    public static let textSecondary = adaptive(light: 0x75737E, dark: 0xA5A2B3)
    public static let textTertiary = adaptive(light: 0xA09EA9, dark: 0x6E6B7E)

    // MARK: Surfaces + glass

    public static let surfacePage = adaptive(light: 0xF6F5FA, dark: 0x0D0C13)
    public static let surfaceCard = adaptive(light: 0xFFFFFF, dark: 0x1C1A26)
    public static let glassBackground = adaptive(
        light: 0xFFFFFF, lightAlpha: 0.56, dark: 0x1C1A26, darkAlpha: 0.55
    )
    public static let glassBorder = adaptive(
        light: 0xFFFFFF, lightAlpha: 0.72, dark: 0xFFFFFF, darkAlpha: 0.10
    )
    public static let glassHighlight = adaptive(
        light: 0xFFFFFF, lightAlpha: 0.85, dark: 0xFFFFFF, darkAlpha: 0.08
    )
    public static let hairline = adaptive(
        light: 0x141028, lightAlpha: 0.08, dark: 0xFFFFFF, darkAlpha: 0.10
    )

    // MARK: Icon chips (40pt tinted squares behind Linea Viva glyphs)

    public static let chipVioletBackground = adaptive(
        light: 0xEAE5FB, dark: 0x7C66F2, darkAlpha: 0.20
    )
    public static let chipVioletForeground = adaptive(light: 0x6A52E4, dark: 0xB3A4F2)
    public static let chipGreenBackground = adaptive(
        light: 0xDFF7E4, dark: 0x34C759, darkAlpha: 0.16
    )
    public static let chipGreenForeground = adaptive(light: 0x1F9D45, dark: 0x4ED077)
    public static let chipOrangeBackground = adaptive(
        light: 0xFDE7D2, dark: 0xF2740D, darkAlpha: 0.16
    )
    public static let chipOrangeForeground = adaptive(light: 0xE05F04, dark: 0xF9AE62)

    // MARK: CTA gradients

    public static let gradientAccent = LinearGradient(
        colors: [fixed(0x8B77F6), fixed(0x6F58EC)],
        startPoint: .top, endPoint: .bottom
    )
    public static let gradientLive = LinearGradient(
        colors: [fixed(0xFB8C2E), fixed(0xEF6A0A)],
        startPoint: .top, endPoint: .bottom
    )
    public static let gradientStop = LinearGradient(
        colors: [fixed(0xFF3B30), fixed(0xE0281D)],
        startPoint: .top, endPoint: .bottom
    )

    // MARK: Mesh waveform strokes (from the Mesh Waveform reference)

    public static func meshBase(live: Bool, dark: Bool) -> Color {
        if live {
            return dark ? fixed(0xF9AE62) : fixed(0xF2740D)
        }
        return dark ? fixed(0xB3A4F2) : fixed(0x7C66F2)
    }

    public static func meshCrest(live: Bool, dark: Bool) -> Color {
        if live {
            return dark ? fixed(0xFDE7D2) : fixed(0xB84E06)
        }
        return dark ? fixed(0xE4DEFF) : fixed(0x5940C8)
    }

    public static func meshHairline(dark: Bool) -> Color {
        dark ? fixed(0xF4F2FA).opacity(0.45) : fixed(0x0B0A10).opacity(0.40)
    }

    // MARK: Builders

    private static func fixed(_ hex: UInt32) -> Color {
        FlowColore.fisso(hex)
    }

    private static func adaptive(
        light: UInt32, lightAlpha: CGFloat = 1,
        dark: UInt32, darkAlpha: CGFloat = 1
    ) -> Color {
        FlowColore.adattivo(
            chiaro: light, alphaChiaro: lightAlpha,
            scuro: dark, alphaScuro: darkAlpha
        )
    }
}

// La tastiera e' una extension UIKit e non esiste su macOS: questi token
// restano dove sono utili.
#if canImport(UIKit)

/// UIKit-facing tokens for the keyboard extension (UIKit surface).
public enum FlowPaletteUIKit {
    public static let accent = dynamicColor(light: 0x7C66F2, dark: 0x8B77F6)
    public static let keyboardBackground = dynamicColor(light: 0xDCDAE3, dark: 0x242230)
    public static let key = dynamicColor(light: 0xFFFFFF, dark: 0x3A3844)

    private static func dynamicColor(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: 1)
                : UIColor(hex: light, alpha: 1)
        }
    }
}

#endif
#endif
