import FlowBridgeShared
import SwiftUI

/// The app is one continuous voice surface. The Living Voice Field and the
/// transcript share a stable container; only the control layer floats above
/// it in Liquid Glass.
struct ContentView: View {
    @EnvironmentObject private var coordinator: FlowBridgeCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showHistory = false
    @State private var showSettings = false
    @State private var showStats = false
    @State private var showPrivacy = false
    @State private var ignitionPulse = 0
    @State private var readyPulse = 0
    @State private var failPulse = 0
    @State private var streakPulse = 0
    @State private var showDayWhisper = false
    @Namespace private var glassNamespace

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: FlowTheme.space16) {
                        flowRail

                        voiceModeLens

                        voiceSurface

                        errorStrip

                        Spacer(minLength: FlowTheme.space20)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: max(0, geometry.size.height - 8), alignment: .top)
                    .padding(.horizontal, FlowTheme.phoneInset)
                    .padding(.top, FlowTheme.space8)
                    .padding(.bottom, FlowTheme.space24)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
            }
            .background(
                RoomBackground(
                    intensity: roomIntensity,
                    listens: isRecording,
                    accent: voicePhase.primary,
                    secondaryAccent: voicePhase.secondary
                )
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                actionDock
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .opacity(chromeOpacity)
                    .allowsHitTesting(!isRecording)
                    .accessibilityLabel("History")
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showPrivacy = true
                    } label: {
                        Image(systemName: "shield.lefthalf.filled")
                            .overlay(alignment: .topTrailing) {
                                Circle()
                                    .fill(cloudActive ? Color.orange : Color.green)
                                    .frame(width: 6, height: 6)
                                    .offset(x: 2, y: -2)
                            }
                    }
                    .opacity(chromeOpacity)
                    .allowsHitTesting(!isRecording)
                    .accessibilityLabel(cloudActive ? "Privacy, cloud mode active" : "Privacy, on-device mode")

                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .opacity(chromeOpacity)
                    .allowsHitTesting(!isRecording)
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showHistory) {
                HistoryView()
                    .presentationBackground(.thinMaterial)
                    .presentationCornerRadius(FlowTheme.radiusSheet)
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .presentationBackground(.thinMaterial)
                    .presentationCornerRadius(FlowTheme.radiusSheet)
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showStats) {
                StatsView()
                    .presentationDetents([.medium, .large])
                    .presentationBackground(.thinMaterial)
                    .presentationCornerRadius(FlowTheme.radiusSheet)
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showPrivacy) {
                PrivacyCockpitView()
                    .presentationDetents([.medium, .large])
                    .presentationBackground(.thinMaterial)
                    .presentationCornerRadius(FlowTheme.radiusSheet)
                    .presentationDragIndicator(.visible)
            }
            .onChange(of: coordinator.state) { _, newState in
                switch newState {
                case .recording:
                    ignitionPulse += 1
                case .ready:
                    readyPulse += 1
                case .failed:
                    failPulse += 1
                default:
                    break
                }
            }
            .onChange(of: coordinator.isNewStreakDay) { _, isNew in
                guard isNew else { return }
                streakPulse += 1
                Task { @MainActor in
                    withAnimation(FlowMotion.state) { showDayWhisper = true }
                    try? await Task.sleep(for: RevealBeat.whisperDwell)
                    withAnimation(FlowMotion.state) { showDayWhisper = false }
                }
            }
        }
    }

    // MARK: - Continuous surface

    private var voiceSurface: some View {
        VStack(spacing: 0) {
            LivingVoiceField(
                state: coordinator.state,
                elapsed: coordinator.recordingElapsed,
                pausedAt: coordinator.pausedAt,
                statusMessage: coordinator.errorPresentation == nil ? coordinator.statusMessage : nil,
                processingStage: coordinator.processingStage,
                voiceMode: coordinator.voiceMode,
                ignitionPulse: ignitionPulse,
                readyPulse: readyPulse,
                failPulse: failPulse
            ) {
                Task { await coordinator.toggleRecording() }
            }

            FlowSeam(tint: voicePhase.primary)
                .padding(.horizontal, FlowTheme.space16)

            TranscriptStageView(
                state: coordinator.state,
                liveTranscript: coordinator.liveTranscript,
                record: coordinator.lastTranscript,
                reveal: coordinator.polishReveal,
                processingStage: coordinator.processingStage,
                vocabularySuggestions: coordinator.vocabularySuggestions,
                suggestedAction: coordinator.suggestedAction,
                actionConfirmation: coordinator.actionConfirmation,
                onAddSuggestion: { coordinator.addVocabularySuggestion($0) },
                onDismissSuggestion: { coordinator.dismissVocabularySuggestion($0) },
                onPerformAction: { Task { await coordinator.performSuggestedAction() } },
                onDismissAction: { coordinator.dismissSuggestedAction() },
                onCopy: { Task { await coordinator.copyLastTranscript() } }
            )
            .padding(.horizontal, FlowTheme.space20)
            .padding(.top, FlowTheme.space16)
            .padding(.bottom, FlowTheme.space20)
        }
        .flowVoiceSurface(tint: voicePhase.primary, secondaryTint: voicePhase.secondary)
        .animation(FlowMotion.fieldMorph, value: stateKey)
    }

    private var flowRail: some View {
        HStack(spacing: FlowTheme.space12) {
            HStack(spacing: FlowTheme.space8) {
                Image(systemName: "waveform.path")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(FlowTheme.accentGradient)
                Text("FlowBridge")
                    .font(.subheadline.weight(.semibold))
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: FlowTheme.space8)

            Button {
                showStats = true
            } label: {
                HStack(spacing: FlowTheme.space8) {
                    Text("\(Int(coordinator.timeSavedMinutes.rounded()))")
                        .font(FlowTheme.numeric(14, weight: .semibold))
                        .contentTransition(reduceMotion ? .opacity : .numericText(value: coordinator.timeSavedMinutes))
                    Text("MIN BACK")
                        .font(FlowTheme.fieldLabel(9))
                        .tracking(0.7)
                        .foregroundStyle(.secondary)
                    if coordinator.streakDays > 1 {
                        Label("\(coordinator.streakDays)", systemImage: "flame.fill")
                            .labelStyle(.titleAndIcon)
                            .font(FlowTheme.numeric(12, weight: .medium))
                            .foregroundStyle(FlowTheme.accent)
                            .symbolEffect(.bounce, value: streakPulse)
                    }
                }
                .frame(minHeight: 44)
                .padding(.horizontal, FlowTheme.space12)
            }
            .buttonStyle(.glass)
            .opacity(isRecording ? 0.35 : 1)
            .allowsHitTesting(!isRecording)
            .animation(FlowMotion.tick.delay(RevealBeat.tickerDelay), value: coordinator.timeSavedMinutes)
            .overlay(alignment: .bottomTrailing) {
                if showDayWhisper {
                    Text("day \(coordinator.streakDays)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(FlowTheme.accent)
                        .offset(y: 18)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 4)))
                }
            }
            .accessibilityLabel("Time given back: \(Int(coordinator.timeSavedMinutes.rounded())) minutes. Opens statistics.")
        }
        .frame(minHeight: 48)
        .animation(FlowMotion.state, value: isRecording)
    }

    /// A persistent intent lens, not another settings picker. Dictate is a
    /// zero-inference text path; Act keeps the exact same capture loop and
    /// adds one optional action only after the words are already safe.
    private var voiceModeLens: some View {
        VStack(spacing: FlowTheme.space8) {
            GlassEffectContainer(spacing: FlowTheme.space8) {
                HStack(spacing: FlowTheme.space8) {
                    voiceModeButton(.dictate)
                    voiceModeButton(.act)
                }
            }

            Text(coordinator.voiceMode.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .contentTransition(.interpolate)
                .animation(FlowMotion.state, value: coordinator.voiceMode)
        }
        .opacity(modeSwitchEnabled ? 1 : 0.48)
    }

    @ViewBuilder
    private func voiceModeButton(_ mode: VoiceMode) -> some View {
        let selected = coordinator.voiceMode == mode
        let label = Label(mode.title, systemImage: mode.symbol)
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 44)

        if selected {
            Button {
                Task { await coordinator.setVoiceMode(mode) }
            } label: {
                label
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(mode.tint)
            .glassEffectID("mode-active-\(mode.rawValue)", in: glassNamespace)
            .disabled(!modeSwitchEnabled)
            .accessibilityHint(mode.detail)
        } else {
            Button {
                Task { await coordinator.setVoiceMode(mode) }
            } label: {
                label
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .glassEffectID("mode-\(mode.rawValue)", in: glassNamespace)
            .disabled(!modeSwitchEnabled)
            .accessibilityHint(mode.detail)
        }
    }

    // MARK: - Control layer

    private var actionDock: some View {
        GlassEffectContainer(spacing: FlowTheme.space12) {
            HStack(spacing: FlowTheme.space12) {
                if canPause {
                    Button {
                        Task {
                            if coordinator.pausedAt == nil {
                                await coordinator.pauseDictation()
                            } else {
                                await coordinator.resumeDictation()
                            }
                        }
                    } label: {
                        Image(systemName: coordinator.pausedAt == nil ? "pause.fill" : "play.fill")
                            .font(.title3.weight(.semibold))
                            .frame(width: 54, height: 54)
                    }
                    .buttonStyle(.glass)
                    .tint(coordinator.pausedAt == nil ? FlowTheme.accent : .green)
                    .glassEffectID("pause", in: glassNamespace)
                    .transition(.scale(scale: 0.82).combined(with: .opacity))
                    .accessibilityLabel(coordinator.pausedAt == nil ? "Pause dictation" : "Resume dictation")
                }

                Button {
                    Task { await coordinator.toggleRecording() }
                } label: {
                    HStack(spacing: FlowTheme.space8) {
                        Image(systemName: coordinator.state.primaryActionSymbol)
                            .contentTransition(.symbolEffect(.replace))
                        Text(coordinator.state.primaryActionTitle)
                            .contentTransition(.opacity)
                    }
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(primaryTint)
                .glassEffectID("primary", in: glassNamespace)
                .disabled(coordinator.state.isBusyWithoutStop)
            }
            .animation(FlowMotion.glassMorph, value: canPause)
            .animation(FlowMotion.glassMorph, value: coordinator.pausedAt)
        }
        .padding(.horizontal, FlowTheme.phoneInset)
        .padding(.top, FlowTheme.space8)
        .padding(.bottom, FlowTheme.space8)
    }

    // MARK: - Failure

    @ViewBuilder
    private var errorStrip: some View {
        if let error = coordinator.errorPresentation {
            HStack(alignment: .top, spacing: FlowTheme.space12) {
                Image(systemName: error.symbol)
                    .font(.title3)
                    .foregroundStyle(FlowTheme.caution)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: FlowTheme.space4) {
                    Text(error.title)
                        .font(.subheadline.weight(.semibold))
                    Text(error.message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let recovery = error.recovery {
                        Button(recovery.title) {
                            performRecovery(recovery)
                        }
                        .font(.footnote.weight(.semibold))
                        .buttonStyle(.glass)
                        .padding(.top, FlowTheme.space4)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    coordinator.dismissError()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .accessibilityLabel("Dismiss error")
            }
            .padding(FlowTheme.space16)
            .flowCard(radius: FlowTheme.radiusRow)
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
    }

    private func performRecovery(_ recovery: FlowBridgeCoordinator.FlowErrorPresentation.Recovery) {
        switch recovery {
        case .openSettings:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        case .tryAgain:
            coordinator.dismissError()
            Task { await coordinator.toggleRecording() }
        case .recoverInterrupted:
            Task { await coordinator.retryInterruptedDictation() }
        }
    }

    // MARK: - State mapping

    private var isRecording: Bool {
        if case .recording = coordinator.state { return true }
        return false
    }

    private var canPause: Bool {
        isRecording && coordinator.canPauseCurrentSession
    }

    private var modeSwitchEnabled: Bool {
        switch coordinator.state {
        case .warming, .transcribing: return false
        case .idle, .recording, .ready, .failed: return true
        }
    }

    private var chromeOpacity: Double {
        isRecording ? 0.28 : 1
    }

    private var cloudActive: Bool {
        FinalPassMode.current == .cloudScribe || EnginePreference.current == .cloudRealtime
    }

    private var primaryTint: Color {
        voicePhase.primary
    }

    private var roomIntensity: Double {
        switch voicePhase {
        case .resting: return 0.30
        case .opening: return 0.48
        case .listening: return 0.66
        case .paused: return 0.40
        case .finalizing: return 0.48
        case .decoding: return 0.58
        case .refining: return 0.68
        case .delivering: return 0.74
        case .delivered: return 0.72
        case .attention: return 0.38
        }
    }

    private var stateKey: String {
        voicePhase.rawValue
    }

    private var voicePhase: FlowVoicePhase {
        .resolve(
            state: coordinator.state,
            processingStage: coordinator.processingStage,
            pausedAt: coordinator.pausedAt
        )
    }
}

private extension VoiceMode {
    var title: String {
        switch self {
        case .dictate: return "Dictate"
        case .act: return "Act"
        }
    }

    var symbol: String {
        switch self {
        case .dictate: return "text.quote"
        case .act: return "sparkles"
        }
    }

    var detail: String {
        switch self {
        case .dictate: return "Just your words. No action is inferred."
        case .act: return "Text first, then one suggested action."
        }
    }

    var tint: Color {
        switch self {
        case .dictate: return FlowTheme.accent
        case .act: return FlowTheme.decoding
        }
    }
}

private struct FlowSeam: View {
    let tint: Color

    var body: some View {
        LinearGradient(
            colors: [.clear, tint.opacity(0.38), .clear],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 1)
        .animation(FlowMotion.state, value: tint.description)
        .accessibilityHidden(true)
    }
}

extension FlowBridgeCoordinator.State {
    var primaryActionTitle: String {
        switch self {
        case .recording: return "Finish"
        case .transcribing: return "Shaping words"
        case .warming: return "Preparing"
        case .ready: return "Speak again"
        case .idle, .failed: return "Speak"
        }
    }

    var primaryActionSymbol: String {
        switch self {
        case .recording: return "stop.fill"
        case .transcribing: return "waveform.badge.magnifyingglass"
        case .warming: return "sparkles"
        case .ready: return "arrow.counterclockwise"
        case .idle, .failed: return "mic.fill"
        }
    }

    var isBusyWithoutStop: Bool {
        switch self {
        case .transcribing, .warming: return true
        case .idle, .ready, .recording, .failed: return false
        }
    }
}
