// La galleria del design system su macOS.
//
// Serve a una cosa sola: guardare. Un glifo portato male non fallisce la
// compilazione — fa un disegno leggermente sbagliato, per sempre. Questa
// finestra sta accanto alla pagina `1a` dell'artefatto Claude Design e si
// confronta a occhio.
//
//   swift run AnteprimaMac

import AppKit
import FlowBridgeShared
import SwiftUI

let glifi: [(LineaVivaIcon.Glyph, String)] = [
    (.dictate, "Dictate"), (.waveform, "Waveform"), (.commands, "Comandi"),
    (.polish, "Polish"), (.insert, "Insert"), (.copy, "Copia"),
    (.history, "History"), (.stats, "Stats"), (.vocab, "Vocab"),
    (.engine, "Engine"), (.language, "Lingua"), (.settings, "Settings"),
    (.privacy, "Privacy"), (.onDevice, "On-device"), (.airplane, "Airplane"),
    (.share, "Share"), (.stop, "Stop"), (.close, "Close"), (.next, "Next"),
]

/// I tre toni non sono decorativi: verde solo privacy, rosso solo stop.
func tono(_ g: LineaVivaIcon.Glyph) -> LineaVivaChip.Tone {
    switch g {
    case .privacy, .onDevice, .airplane: return .green
    case .stop: return .orange
    default: return .violet
    }
}

struct Galleria: View {
    @State private var live = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("LINEA VIVA · 19 GLIFI")
                    .font(.system(size: 11, weight: .bold)).tracking(1.4)
                    .foregroundStyle(FlowPalette.textSecondary)

                LazyVGrid(columns: Array(repeating: GridItem(.fixed(74)), count: 7), spacing: 16) {
                    ForEach(Array(glifi.enumerated()), id: \.offset) { _, voce in
                        VStack(spacing: 6) {
                            LineaVivaChip(voce.0, tone: tono(voce.0))
                            Text(voce.1.uppercased())
                                .font(.system(size: 8.5, weight: .semibold)).tracking(0.6)
                                .foregroundStyle(FlowPalette.textSecondary)
                        }
                    }
                }

                Divider().overlay(FlowPalette.hairline)

                HStack {
                    Text(live ? "LISTENING" : "READY TO BRIDGE")
                        .font(.system(size: 11, weight: .bold)).tracking(1.4)
                        .foregroundStyle(live ? FlowPalette.stateLive : FlowPalette.accent)
                    Spacer()
                    Toggle("Live", isOn: $live).toggleStyle(.switch)
                }
                MeshWaveformView(live: live, level: live ? 0.6 : 0)
                    .frame(height: 110)

                Text("Il nastro e' l'unica immagine del marchio. Armoniche 20.1 / 42.7 / 71.3, envelope sin^1.15, 54 linee, crest ogni 9a.")
                    .font(.system(size: 12))
                    .foregroundStyle(FlowPalette.textSecondary)
            }
            .padding(28)
        }
        .frame(minWidth: 620, minHeight: 560)
        .background(FlowPalette.surfacePage)
    }
}

final class Delegato: NSObject, NSApplicationDelegate {
    var finestra: NSWindow?
    func applicationDidFinishLaunching(_ n: Notification) {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 640),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = "FlowBridge — design system su macOS"
        w.contentView = NSHostingView(rootView: Galleria())
        w.center(); w.makeKeyAndOrderFront(nil)
        finestra = w
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegato = Delegato()
app.delegate = delegato
app.setActivationPolicy(.regular)
app.run()
