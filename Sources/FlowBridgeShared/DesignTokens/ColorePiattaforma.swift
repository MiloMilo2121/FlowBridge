// Il colore, scritto una volta per due piattaforme.
//
// I token di FlowPalette erano tutti chiusi dentro `#if canImport(UIKit)` —
// 167 righe su 167 — perche' il colore dinamico chiaro/scuro su iOS si fa con
// `UIColor { traits in }`. Su macOS quella condizione e' falsa e spariva
// l'intera palette: il design system non esisteva proprio, e con lui le 19
// icone e i colori del mesh waveform.
//
// AppKit ha l'equivalente esatto — `NSColor(name:dynamicProvider:)` — che come
// UIColor risolve al momento del disegno, non alla creazione. Quindi il
// chiaro/scuro automatico continua a funzionare da solo su entrambe, e chi
// dichiara i token non deve piu' sapere su che sistema gira.
//
// Qui dentro c'e' l'unica differenza fra le due piattaforme. Tutto il resto del
// design system e' geometria e numeri, che non hanno patria.

#if canImport(UIKit) || canImport(AppKit)

import SwiftUI

#if canImport(UIKit)
import UIKit
public typealias ColoreNativo = UIColor
#else
import AppKit
public typealias ColoreNativo = NSColor
#endif

public enum FlowColore {
    /// Un colore che non cambia col tema.
    public static func fisso(_ hex: UInt32, alpha: CGFloat = 1) -> Color {
        colore(ColoreNativo(hex: hex, alpha: alpha))
    }

    /// Un colore che si risolve sul tema corrente, al momento del disegno.
    ///
    /// Non e' un `if` valutato una volta all'avvio: entrambe le piattaforme
    /// tengono la chiusura e la richiamano quando l'aspetto cambia. E' per
    /// questo che passare da chiaro a scuro non richiede di ricostruire niente.
    public static func adattivo(
        chiaro: UInt32, alphaChiaro: CGFloat = 1,
        scuro: UInt32, alphaScuro: CGFloat = 1
    ) -> Color {
        #if canImport(UIKit)
        return colore(UIColor { tratti in
            tratti.userInterfaceStyle == .dark
                ? UIColor(hex: scuro, alpha: alphaScuro)
                : UIColor(hex: chiaro, alpha: alphaChiaro)
        })
        #else
        return colore(NSColor(name: nil) { aspetto in
            aspetto.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(hex: scuro, alpha: alphaScuro)
                : NSColor(hex: chiaro, alpha: alphaChiaro)
        })
        #endif
    }

    private static func colore(_ nativo: ColoreNativo) -> Color {
        #if canImport(UIKit)
        return Color(uiColor: nativo)
        #else
        return Color(nsColor: nativo)
        #endif
    }
}

public extension ColoreNativo {
    convenience init(hex: UInt32, alpha: CGFloat) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

#endif
