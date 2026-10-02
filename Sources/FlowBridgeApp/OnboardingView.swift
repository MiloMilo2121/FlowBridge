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
    @State private var cloudKey = ""

    var body: some View {
        TabView(selection: $page) {
            cloudScene.tag(0)
            speakScene.tag(1)
            triggerScene.tag(2)
            keyboardScene.tag(3)
        }
        .tabViewStyle(.page)
        .background { AuroraBackground() }
        .interactiveDismissDisabled()
    }

    private var cloudScene: some View {
        scene(
            glyph: .language,
            eyebrow: "Choose where speech is processed",
            eyebrowTone: .accent,
            title: "Your voice, your choice.",
            message: "For live cloud dictation, FlowBridge sends microphone audio to AssemblyAI's EU service while you speak. Enter your own API key. The diary syncs through your iCloud Drive account. You can choose local dictation instead."
        ) {
            VStack(spacing: 12) {
                SecureField("AssemblyAI API key", text: $cloudKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .textFieldStyle(.roundedBorder)
                Button("I agree · use AssemblyAI streaming") {
                    KeychainStore.saveCloudAPIKey(cloudKey)
                    UserDefaults.standard.set(true, forKey: FlowBridgeConstants.cloudConsentAcceptedKey)
                    CloudGate.setCloudEngineEnabled(true)
                    EnginePreference.set(.cloud)
                    withAnimation { page = 1 }
                }
                .buttonStyle(FlowCTAButtonStyle())
                .disabled(cloudKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Use local dictation") {
                    CloudGate.setCloudEngineEnabled(false)
                    EnginePreference.set(.whisper)
                    withAnimation { page = 1 }
                }
                .font(.footnote)
            }
        }
    }

    private var speakScene: some View {
        scene(
            glyph: .dictate,
            eyebrow: "Microphone permission",
            eyebrowTone: .privacy,
            title: "Speak.",
            message: "FlowBridge records only when you start a dictation. AssemblyAI receives live audio if you chose cloud; local mode keeps processing on this iPhone."
        ) {
            Button {
                Task {
                    microphoneGranted = await FlowBridgeCoordinator.shared.requestMicrophonePermission()
                    withAnimation { page = 2 }
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
                withAnimation { page = 3 }
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
            message: "The keyboard types normally without Full Access. To insert FlowBridge transcripts, Full Access lets it read the app's shared container. The keyboard extension itself has no network access."
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
