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
        .interactiveDismissDisabled()
    }

    private var speakScene: some View {
        scene(
            symbol: "waveform.circle.fill",
            title: "Speak.",
            message: "FlowBridge turns your voice into clean text, entirely on this iPhone. No cloud, no account. Try it: allow the microphone and say something."
        ) {
            Button {
                Task {
                    microphoneGranted = await FlowBridgeCoordinator.shared.requestMicrophonePermission()
                    withAnimation { page = 1 }
                }
            } label: {
                Label(microphoneGranted ? "Microphone ready" : "Allow microphone", systemImage: "mic.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var triggerScene: some View {
        scene(
            symbol: "button.vertical.left.press.fill",
            title: "Your button.",
            message: "Map the Action Button to FlowBridge and dictation starts with one press — without opening the app, with live progress in the Dynamic Island. Settings → Action Button → Controls → FlowBridge Dictation. No Action Button? Back Tap or the Lock Screen control work the same way."
        ) {
            Button {
                withAnimation { page = 2 }
            } label: {
                Text("Done — next")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var keyboardScene: some View {
        scene(
            symbol: "keyboard.fill",
            title: "Your keyboard (optional).",
            message: "The FlowBridge keyboard inserts what you dictate right where you're typing. iOS shows a scary Full Access warning when you enable it. What we actually do: read your transcript from this device's shared container. What we cannot do: send it anywhere — the app has no network path for your voice, ever."
        ) {
            VStack(spacing: 10) {
                Button {
                    finish()
                } label: {
                    Text("Enable later in Settings")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button("Skip — clipboard works too", action: finish)
                    .font(.footnote)
            }
        }
    }

    private func scene(
        symbol: String,
        title: String,
        message: String,
        @ViewBuilder actions: () -> some View
    ) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 72))
                .foregroundStyle(.tint)
            Text(title)
                .font(.largeTitle.bold())
            Text(message)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            actions()
                .padding(.bottom, 48)
        }
        .padding(24)
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: FlowBridgeConstants.onboardingCompletedKey)
        onFinished()
    }
}
