import FlowBridgeShared
import SwiftUI

/// Magic first, explanation second. The first page runs the real five-second
/// voice loop; the next two pages reveal the system surfaces and the privacy
/// contract without turning onboarding into a manual.
struct OnboardingView: View {
    let onFinished: () -> Void

    @ObservedObject private var coordinator = FlowBridgeCoordinator.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var page = 0
    @State private var revealedPage = 0
    @State private var microphoneGranted = false
    @State private var microphoneDenied = false
    @State private var demoStarted = false
    @State private var demoReadyPulse = 0

    var body: some View {
        ZStack {
            RoomBackground(
                intensity: page == 0 ? 0.58 : 0.36,
                listens: isRecording,
                accent: trialPhase.primary,
                secondaryAccent: trialPhase.secondary
            )

            TabView(selection: $page) {
                voiceScene.tag(0)
                everywhereScene.tag(1)
                trustScene.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .interactiveDismissDisabled()
        }
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

    // MARK: - 1. Product proof

    private var voiceScene: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FlowTheme.space20) {
                Spacer(minLength: FlowTheme.space40)

                staggered(0, page: 0) {
                    Text("VOICE FIRST").flowEyebrow()
                }

                staggered(1, page: 0) {
                    Text("Say it.\nWatch it become useful.")
                        .font(FlowTheme.hero(38, weight: .semibold))
                        .tracking(-1.2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                staggered(2, page: 0) {
                    VStack(spacing: 0) {
                        LivingVoiceField(
                            state: coordinator.state,
                            elapsed: coordinator.recordingElapsed,
                            pausedAt: coordinator.pausedAt,
                            statusMessage: trialStatus,
                            processingStage: coordinator.processingStage,
                            readyPulse: demoReadyPulse
                        ) {
                            beginVoiceTrial()
                        }

                        if let trialText, !trialText.isEmpty {
                            LinearGradient(
                                colors: [.clear, trialPhase.primary.opacity(0.35), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(height: 1)
                            .padding(.horizontal, FlowTheme.space16)

                            Text("“\(trialText)”")
                                .font(FlowTheme.serifFlavor(18))
                                .lineLimit(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(FlowTheme.space20)
                                .transition(
                                    reduceMotion
                                        ? .opacity
                                        : .opacity.combined(with: .scale(scale: 0.985, anchor: .top))
                                )
                        }
                    }
                    .flowVoiceSurface(tint: trialPhase.primary, secondaryTint: trialPhase.secondary)
                    .animation(FlowMotion.settle, value: trialText)
                }

                if microphoneDenied {
                    staggered(3, page: 0) {
                        Label("Microphone access is needed for the live trial. You can enable it later in Settings.", systemImage: "mic.slash")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(FlowTheme.space16)
                            .flowCard(radius: FlowTheme.radiusRow)
                    }
                }

                Spacer(minLength: FlowTheme.space24)

                staggered(4, page: 0) {
                    Button {
                        if trialFinished || microphoneDenied {
                            withAnimation(FlowMotion.state) { page = 1 }
                        } else {
                            beginVoiceTrial()
                        }
                    } label: {
                        Label(voiceCTA, systemImage: trialFinished ? "arrow.right" : "mic.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .tint(FlowTheme.accent)
                    .disabled(isRecording)
                }

                Button("Skip the trial") {
                    withAnimation(FlowMotion.state) { page = 1 }
                }
                .font(.footnote.weight(.medium))
                .frame(maxWidth: .infinity)
                .foregroundStyle(.secondary)

                Spacer(minLength: 64)
            }
            .padding(.horizontal, FlowTheme.phoneInset)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - 2. System surfaces

    private var everywhereScene: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FlowTheme.space20) {
                Spacer(minLength: FlowTheme.space40)

                staggered(0, page: 1) {
                    Text("NO APP HUNTING").flowEyebrow()
                }

                staggered(1, page: 1) {
                    Text("FlowBridge lives\nwhere your hand already is.")
                        .font(FlowTheme.hero(36, weight: .semibold))
                        .tracking(-1)
                        .fixedSize(horizontal: false, vertical: true)
                }

                staggered(2, page: 1) {
                    SystemBridgeMap()
                }

                staggered(3, page: 1) {
                    Text("Set the Action Button to Controls → FlowBridge Dictation. The same one-tap entry is available on the Lock Screen and in Control Center.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: FlowTheme.space24)

                staggered(4, page: 1) {
                    Button {
                        withAnimation(FlowMotion.state) { page = 2 }
                    } label: {
                        Label("See the privacy contract", systemImage: "shield.lefthalf.filled")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .tint(FlowTheme.accent)
                }

                Spacer(minLength: 64)
            }
            .padding(.horizontal, FlowTheme.phoneInset)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - 3. Trust

    private var trustScene: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FlowTheme.space20) {
                Spacer(minLength: FlowTheme.space40)

                staggered(0, page: 2) {
                    Text("TRUST YOU CAN VERIFY").flowEyebrow()
                }

                staggered(1, page: 2) {
                    Text("Your voice is yours.\nThe controls make that visible.")
                        .font(FlowTheme.hero(36, weight: .semibold))
                        .tracking(-1)
                        .fixedSize(horizontal: false, vertical: true)
                }

                staggered(2, page: 2) {
                    VStack(spacing: 0) {
                        TrustRow(icon: "iphone", title: "On-device by default", detail: "Speech is processed locally on this iPhone.")
                        Divider().padding(.leading, 56)
                        TrustRow(icon: "cloud", title: "Cloud only by choice", detail: "A cloud engine appears only after you add a key and select it.")
                        Divider().padding(.leading, 56)
                        TrustRow(icon: "person.crop.circle.badge.xmark", title: "No account", detail: "History and vocabulary stay in the shared local container.")
                        Divider().padding(.leading, 56)
                        TrustRow(icon: "keyboard", title: "Keyboard is optional", detail: "Enable it later; clipboard delivery already works everywhere.")
                    }
                    .flowCard()
                }

                staggered(3, page: 2) {
                    Label("Try Airplane Mode after setup. Dictation keeps working.", systemImage: "airplane")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(FlowTheme.accent)
                }

                Spacer(minLength: FlowTheme.space24)

                staggered(4, page: 2) {
                    Button(action: finish) {
                        Label("Start using FlowBridge", systemImage: "waveform.path")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .tint(FlowTheme.accent)
                }

                Spacer(minLength: 64)
            }
            .padding(.horizontal, FlowTheme.phoneInset)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Trial

    private var isRecording: Bool {
        if case .recording = coordinator.state { return true }
        return false
    }

    private var trialPhase: FlowVoicePhase {
        .resolve(
            state: coordinator.state,
            processingStage: coordinator.processingStage,
            pausedAt: coordinator.pausedAt
        )
    }

    private var trialFinished: Bool {
        if case .ready = coordinator.state, demoStarted { return true }
        return false
    }

    private var trialText: String? {
        if let live = coordinator.liveTranscript?.text, !live.isEmpty { return live }
        if trialFinished { return coordinator.lastTranscript?.text }
        return nil
    }

    private var trialStatus: String? {
        if microphoneDenied { return "Microphone access is off."
        }
        if trialFinished { return "That text is already on your clipboard."
        }
        if demoStarted && isRecording { return "Keep talking. This trial stops after five seconds."
        }
        return "Tap the field or the button below to try the real loop."
    }

    private var voiceCTA: String {
        if trialFinished { return "Continue"
        }
        if microphoneDenied { return "Continue without trial"
        }
        if demoStarted { return "Listening…"
        }
        return "Try with my voice"
    }

    private func beginVoiceTrial() {
        guard !isRecording else { return }
        Task {
            if !microphoneGranted {
                microphoneGranted = await coordinator.requestMicrophonePermission()
                microphoneDenied = !microphoneGranted
            }
            guard microphoneGranted else { return }

            demoStarted = true
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

    private func staggered(_ index: Int, page scenePage: Int, @ViewBuilder content: () -> some View) -> some View {
        StaggeredReveal(
            revealed: revealedPage == scenePage,
            delay: Double(index) * 0.07,
            content: content
        )
    }
}

private struct SystemBridgeMap: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: FlowTheme.space16) {
            HStack(spacing: FlowTheme.space12) {
                Capsule(style: .continuous)
                    .fill(.black)
                    .frame(width: 186, height: 50)
                    .overlay {
                        HStack(spacing: FlowTheme.space8) {
                            Image(systemName: "waveform")
                                .foregroundStyle(FlowTheme.recordingGradient)
                                .symbolEffect(.variableColor.iterative, options: reduceMotion ? .nonRepeating : .repeating)
                            Text("0:12")
                                .font(FlowTheme.numeric(13))
                                .foregroundStyle(.white)
                            Spacer(minLength: 0)
                            Image(systemName: "stop.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        .padding(.horizontal, FlowTheme.space16)
                    }
                Text("DYNAMIC\nISLAND")
                    .font(FlowTheme.fieldLabel(10))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
            }

            LinearGradient(
                colors: [FlowTheme.accent.opacity(0.5), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: 1, height: 28)

            GlassEffectContainer(spacing: FlowTheme.space12) {
                HStack(spacing: FlowTheme.space12) {
                    systemNode("button.vertical.left.press.fill", "Action")
                    systemNode("lock.fill", "Lock")
                    systemNode("switch.2", "Control")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, FlowTheme.space24)
        .flowCard()
    }

    private func systemNode(_ symbol: String, _ label: String) -> some View {
        VStack(spacing: FlowTheme.space8) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .frame(width: 52, height: 52)
                .flowGlass(interactive: true)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct TrustRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: FlowTheme.space12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(FlowTheme.accent)
                .frame(width: 36, height: 36)
                .background(FlowTheme.accent.opacity(0.10), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(FlowTheme.space16)
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
            .offset(y: revealed || reduceMotion ? 0 : 10)
            .animation(.smooth(duration: 0.38).delay(revealed ? delay : 0), value: revealed)
    }
}
