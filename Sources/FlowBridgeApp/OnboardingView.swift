import FlowBridgeShared
import SwiftUI

/// Four scenes, ninety seconds: speak first, wire the Action Button, enable
/// the keyboard (with the Full Access warning explained honestly), then try
/// a real five-second dictation — the first run ends on the product's magic
/// moment. Permission prompts stay contextual; every scene reveals with a
/// staggered rise that Reduce Motion flattens to a fade.
struct OnboardingView: View {
    let onFinished: () -> Void

    @ObservedObject private var coordinator = FlowBridgeCoordinator.shared
    @State private var page = 0
    @State private var revealedPage = 0
    @State private var microphoneGranted = false
    @State private var demoStarted = false
    @State private var demoReadyPulse = 0

    var body: some View {
        ZStack {
            RoomBackground()
            tabs
        }
    }

    private var tabs: some View {
        TabView(selection: $page) {
            speakScene.tag(0)
            triggerScene.tag(1)
            keyboardScene.tag(2)
            tryScene.tag(3)
        }
        .tabViewStyle(.page)
        .interactiveDismissDisabled()
        .onChange(of: page) { _, newPage in
            revealedPage = -1
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(60))
                revealedPage = newPage
            }
        }
        .onChange(of: coordinator.state) { _, newState in
            if case .ready = newState, demoStarted {
                demoReadyPulse += 1
            }
        }
    }

    // MARK: - Scenes

    private var speakScene: some View {
        scene(page: 0, symbol: "waveform.circle.fill", title: "Speak.", message: "FlowBridge turns your voice into clean text, entirely on this iPhone. No cloud, no account. Try it: allow the microphone and say something.") {
            Button {
                Task {
                    microphoneGranted = await FlowBridgeCoordinator.shared.requestMicrophonePermission()
                    withAnimation(FlowMotion.state) { page = 1 }
                }
            } label: {
                Label(microphoneGranted ? "Microphone ready" : "Allow microphone", systemImage: "mic.fill")
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(FlowTheme.accent)
        } symbolView: {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(FlowTheme.accentGradient)
                .symbolEffect(.variableColor.iterative, options: .repeating)
        }
    }

    private var triggerScene: some View {
        scene(page: 1, symbol: "button.vertical.left.press.fill", title: "Your button.", message: "Map the Action Button to FlowBridge and dictation starts with one press — without opening the app, with a live waveform in the Dynamic Island. Settings → Action Button → Controls → FlowBridge Dictation. No Action Button? Back Tap or the Lock Screen control work the same way.") {
            Button {
                withAnimation(FlowMotion.state) { page = 2 }
            } label: {
                Text("Done — next")
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(FlowTheme.accent)
        } symbolView: {
            Image(systemName: "button.vertical.left.press.fill")
                .font(.system(size: 72))
                .foregroundStyle(FlowTheme.accentGradient)
                .symbolEffect(.pulse, options: .repeating)
        }
    }

    private var keyboardScene: some View {
        scene(page: 2, symbol: "keyboard.fill", title: "Your keyboard (optional).", message: "The FlowBridge keyboard inserts what you dictate right where you're typing. iOS shows a scary Full Access warning when you enable it. What we actually do: read your transcript from this device's shared container. What we cannot do: send it anywhere — the app has no network path for your voice, ever.") {
            VStack(spacing: FlowTheme.space8) {
                Button {
                    withAnimation(FlowMotion.state) { page = 3 }
                } label: {
                    Text("Enable later in Settings")
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(FlowTheme.accent)

                Button("Skip — clipboard works too") {
                    withAnimation(FlowMotion.state) { page = 3 }
                }
                .font(.footnote)
            }
        } symbolView: {
            Image(systemName: "keyboard.fill")
                .font(.system(size: 72))
                .foregroundStyle(FlowTheme.accentGradient)
                .symbolEffect(.bounce, value: page == 2)
        }
    }

    /// The magic-moment page: a real dictation, five seconds, live words.
    private var tryScene: some View {
        VStack(spacing: FlowTheme.space16) {
            Spacer()

            staggered(0) {
                Text("Try it now.")
                    .font(FlowTheme.serifFlavor(40, weight: .medium))
            }

            staggered(1) {
                OrbView(state: coordinator.state, diameter: 150, readyPulse: demoReadyPulse) {
                    runDemo()
                }
            }

            staggered(2) {
                Group {
                    if let snapshot = coordinator.liveTranscript, !snapshot.text.isEmpty {
                        Text(snapshot.text)
                            .font(.title3.weight(.medium))
                            .lineLimit(2)
                            .truncationMode(.head)
                    } else if demoStarted, let last = coordinator.lastTranscript, case .ready = coordinator.state {
                        Text("“\(last.text)” — copied. That's the whole flow.")
                            .font(.title3.weight(.medium))
                            .lineLimit(3)
                    } else if microphoneGranted {
                        Text(demoStarted ? "Listening — five seconds, say anything." : "Tap the orb and say anything. It stops by itself.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Microphone not enabled — you can allow it anytime from the first dictation.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
                .multilineTextAlignment(.center)
                .animation(FlowMotion.state, value: coordinator.liveTranscript?.text)
            }

            Spacer()

            staggered(3) {
                Button(action: finish) {
                    Text("Start using FlowBridge")
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(FlowTheme.accent)
            }
            .padding(.bottom, 48)
        }
        .padding(24)
    }

    // MARK: - Scene scaffolding

    private func scene(
        page scenePage: Int,
        symbol: String,
        title: String,
        message: String,
        @ViewBuilder actions: () -> some View,
        @ViewBuilder symbolView: () -> some View
    ) -> some View {
        VStack(spacing: FlowTheme.space20) {
            Spacer()
            staggered(0, page: scenePage) { symbolView() }
            staggered(1, page: scenePage) {
                Text(title)
                    .font(FlowTheme.serifFlavor(40, weight: .medium))
            }
            staggered(2, page: scenePage) {
                Text(message)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            staggered(3, page: scenePage) { actions() }
                .padding(.bottom, 48)
        }
        .padding(24)
    }

    /// Staggered reveal: opacity + a 12pt rise, delayed per element. With
    /// Reduce Motion the rise disappears and only the fade remains.
    private func staggered(_ index: Int, page scenePage: Int? = nil, @ViewBuilder content: () -> some View) -> some View {
        StaggeredReveal(
            revealed: revealedPage == (scenePage ?? page),
            delay: Double(index) * 0.08,
            content: content
        )
    }

    private func runDemo() {
        guard !demoStarted || !coordinator.state.isBusyWithoutStop else { return }
        demoStarted = true
        Task {
            await coordinator.toggleRecording()
            guard case .recording = coordinator.state else { return }
            try? await Task.sleep(for: .seconds(5))
            if case .recording = coordinator.state {
                await coordinator.toggleRecording()
            }
        }
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: FlowBridgeConstants.onboardingCompletedKey)
        onFinished()
    }
}

private struct StaggeredReveal<Content: View>: View {
    let revealed: Bool
    let delay: Double
    @ViewBuilder let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed || reduceMotion ? 0 : 12)
            .animation(.smooth(duration: 0.4).delay(revealed ? delay : 0), value: revealed)
    }
}
