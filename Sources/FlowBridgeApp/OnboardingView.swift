import FlowBridgeShared
import SwiftUI

/// Three scenes, ninety seconds: speak first, wire the Action Button, then
/// (optionally) enable the keyboard — with the Full Access warning explained
/// honestly. Permission prompts are contextual: the microphone one appears at
/// the moment of the first tap, never as a wall.
struct OnboardingView: View {
    let onFinished: () -> Void

    @State private var page = 0
    @State private var microphoneGranted = false

    var body: some View {
        TabView(selection: $page) {
            speakScene.tag(0)
            triggerScene.tag(1)
            keyboardScene.tag(2)
        }
        .tabViewStyle(.page)
        .background { AuroraBackground() }
        .interactiveDismissDisabled()
    }

    private var speakScene: some View {
        scene(
            glyph: .dictate,
            eyebrow: "On-device · Private",
            eyebrowTone: .privacy,
            title: "Speak.",
            message: "FlowBridge turns your voice into clean text, entirely on this iPhone. No cloud, no account. Try it: allow the microphone and say something."
        ) {
            Button {
                Task {
                    microphoneGranted = await FlowBridgeCoordinator.shared.requestMicrophonePermission()
                    withAnimation { page = 1 }
                }
            } label: {
                HStack(spacing: 10) {
                    LineaVivaIcon(.dictate)
                        .frame(width: 20, height: 20)
                    Text(microphoneGranted ? "Microphone ready" : "Allow microphone")
                }
            }
            .buttonStyle(FlowCTAButtonStyle())
        }
    }

    private var triggerScene: some View {
        scene(
            glyph: .waveform,
            eyebrow: "Zero friction",
            eyebrowTone: .accent,
            title: "Your button.",
            message: "Map the Action Button to FlowBridge and dictation starts with one press — without opening the app, with live progress in the Dynamic Island. Settings → Action Button → Controls → FlowBridge Dictation. No Action Button? Back Tap or the Lock Screen control work the same way."
        ) {
            Button {
                withAnimation { page = 2 }
            } label: {
                Text("Done — next")
            }
            .buttonStyle(FlowCTAButtonStyle())
        }
    }

    private var keyboardScene: some View {
        scene(
            glyph: .insert,
            eyebrow: "Optional",
            eyebrowTone: .accent,
            title: "Your keyboard.",
            message: "The FlowBridge keyboard inserts what you dictate right where you're typing. iOS shows a scary Full Access warning when you enable it. What we actually do: read your transcript from this device's shared container. What we cannot do: send it anywhere — the app has no network path for your voice, ever."
        ) {
            VStack(spacing: 10) {
                Button {
                    finish()
                } label: {
                    Text("Enable later in Settings")
                }
                .buttonStyle(FlowCTAButtonStyle())

                Button("Skip — clipboard works too", action: finish)
                    .font(.footnote)
                    .foregroundStyle(FlowPalette.textSecondary)
            }
        }
    }

    private func scene(
        glyph: LineaVivaIcon.Glyph,
        eyebrow: String,
        eyebrowTone: CapsLabel.Tone,
        title: String,
        message: String,
        @ViewBuilder actions: () -> some View
    ) -> some View {
        VStack(spacing: FlowTheme.Spacing.stack) {
            Spacer()
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(FlowPalette.chipVioletBackground)
                .frame(width: 132, height: 132)
                .overlay {
                    LineaVivaIcon(glyph)
                        .foregroundStyle(FlowPalette.chipVioletForeground)
                        .frame(width: 88, height: 88)
                }
                .accessibilityHidden(true)
            CapsLabel(text: eyebrow, tone: eyebrowTone)
                .padding(.top, 6)
            Text(title)
                .font(.largeTitle.bold())
                .foregroundStyle(FlowPalette.textBody)
            Text(message)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(FlowPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            actions()
                .padding(.bottom, 64)
        }
        .padding(24)
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: FlowBridgeConstants.onboardingCompletedKey)
        onFinished()
    }
}
