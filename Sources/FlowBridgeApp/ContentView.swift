import FlowBridgeShared
import SwiftUI

/// The room. One hero — the Orb — with the live words below while recording
/// and the latest (polished) transcript otherwise. Everything else lives in
/// sheets.
struct ContentView: View {
    @EnvironmentObject private var coordinator: FlowBridgeCoordinator
    @State private var showHistory = false
    @State private var showSettings = false
    @State private var showStats = false
    @State private var showPrivacy = false
    @State private var ignitionPulse = 0
    @State private var readyPulse = 0
    @State private var failPulse = 0
    @State private var streakPulse = 0
    @State private var showDayWhisper = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            VStack(spacing: FlowTheme.space16) {
                Spacer(minLength: 0)

                OrbView(
                    state: coordinator.state,
                    diameter: 210,
                    ignitionPulse: ignitionPulse,
                    readyPulse: readyPulse,
                    failPulse: failPulse
                ) {
                    Task { await coordinator.toggleRecording() }
                }

                elapsedPill

                statusCaption

                timeSavedTicker

                Spacer(minLength: 0)

                transcriptArea

                primaryCapsule
            }
            .padding(FlowTheme.space20)
            .background(RoomBackground(intensity: roomIntensity, listens: isRecording))
            .toolbar {
                // No title: the orb is the identity. Items recede (opacity,
                // never removal) while recording.
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        showHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .opacity(chromeOpacity)
                    .allowsHitTesting(!isRecording)
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

                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .opacity(chromeOpacity)
                    .allowsHitTesting(!isRecording)
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
                if isNew {
                    streakPulse += 1
                    Task { @MainActor in
                        withAnimation(FlowMotion.state) { showDayWhisper = true }
                        try? await Task.sleep(for: RevealBeat.whisperDwell)
                        withAnimation(FlowMotion.state) { showDayWhisper = false }
                    }
                }
            }
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var elapsedPill: some View {
        if let elapsed = coordinator.recordingElapsed {
            Text(Duration.seconds(elapsed).formatted(.time(pattern: .minuteSecond)))
                .font(FlowTheme.numeric(17))
                .contentTransition(.numericText(value: elapsed))
                .animation(.snappy(duration: 0.25), value: Int(elapsed))
                .padding(.horizontal, FlowTheme.space12)
                .padding(.vertical, FlowTheme.space4)
                .flowGlass()
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }

    @ViewBuilder
    private var statusCaption: some View {
        if let message = coordinator.statusMessage {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .id(message)
                .transition(.blurReplace)
        }
    }

    /// The visible reward: minutes not spent typing, counting up after every
    /// session. Tap for the full story.
    private var timeSavedTicker: some View {
        Button {
            showStats = true
        } label: {
            HStack(spacing: FlowTheme.space8) {
                Image(systemName: "hourglass")
                Text("\(Int(coordinator.timeSavedMinutes.rounded())) min given back")
                    .contentTransition(reduceMotion ? .opacity : .numericText(value: coordinator.timeSavedMinutes))

                if coordinator.streakDays > 1 {
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .symbolEffect(.bounce, value: streakPulse)
                        Text("\(coordinator.streakDays)")
                            .contentTransition(reduceMotion ? .opacity : .numericText())
                    }
                    .foregroundStyle(FlowTheme.accent)
                    .phaseAnimator([1.0, 1.15, 1.0], trigger: streakPulse) { view, scale in
                        view.scaleEffect(reduceMotion ? 1.0 : scale)
                    } animation: { _ in
                        FlowMotion.celebrate
                    }
                }
            }
            .font(FlowTheme.numeric(14, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, FlowTheme.space12)
            .padding(.vertical, FlowTheme.space8)
        }
        .buttonStyle(.glass)
        .opacity(isRecording ? 0 : 1)
        .allowsHitTesting(!isRecording)
        // The ticker rolls as the text reveal settles — eye follows
        // text → number (RevealBeat clock).
        .animation(FlowMotion.tick.delay(RevealBeat.tickerDelay), value: coordinator.timeSavedMinutes)
        .animation(FlowMotion.state, value: isRecording)
        .overlay(alignment: .bottom) {
            if showDayWhisper {
                // The once-a-day moment: small text that appears and leaves.
                Text("day \(coordinator.streakDays)")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(FlowTheme.accentGradient)
                    .offset(y: 20)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 4)))
            }
        }
        .accessibilityLabel("Time given back: \(Int(coordinator.timeSavedMinutes.rounded())) minutes. Opens statistics.")
    }

    private var transcriptArea: some View {
        TranscriptStageView(
            state: coordinator.state,
            liveTranscript: coordinator.liveTranscript,
            record: coordinator.lastTranscript,
            reveal: coordinator.polishReveal,
            vocabularySuggestions: coordinator.vocabularySuggestions,
            onAddSuggestion: { coordinator.addVocabularySuggestion($0) },
            onDismissSuggestion: { coordinator.dismissVocabularySuggestion($0) },
            onCopy: { Task { await coordinator.copyLastTranscript() } }
        )
    }

    private var primaryCapsule: some View {
        HStack(spacing: FlowTheme.space8) {
            if isRecording {
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
                        .frame(width: 56, height: 56)
                }
                .buttonStyle(.glass)
                .tint(coordinator.pausedAt == nil ? FlowTheme.accent : .green)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .accessibilityLabel(coordinator.pausedAt == nil ? "Pause dictation" : "Resume dictation")
            }

            Button {
                Task { await coordinator.toggleRecording() }
            } label: {
                Label(coordinator.state.primaryActionTitle, systemImage: coordinator.state.primaryActionSymbol)
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(isRecording ? .red : FlowTheme.accent)
            .disabled(coordinator.state.isBusyWithoutStop)
        }
        .animation(FlowMotion.state, value: isRecording)
        .animation(FlowMotion.state, value: coordinator.pausedAt)
    }

    private var isRecording: Bool {
        if case .recording = coordinator.state {
            return true
        }
        return false
    }

    /// Chrome recedes while the voice has the stage.
    private var chromeOpacity: Double {
        isRecording ? 0.35 : 1
    }

    private var cloudActive: Bool {
        FinalPassMode.current == .cloudScribe || EnginePreference.current == .cloudRealtime
    }

    /// The room's single reactive scalar; while recording the aurora also
    /// reads the mic level per frame on its own.
    private var roomIntensity: Double {
        switch coordinator.state {
        case .idle: return 0.35
        case .warming: return 0.5
        case .recording: return 0.65
        case .transcribing: return 0.55
        case .ready: return 0.75
        case .failed: return 0.4
        }
    }
}

extension FlowBridgeCoordinator.State {
    var primaryActionTitle: String {
        switch self {
        case .recording:
            return "Stop"
        case .transcribing, .warming:
            return "Working"
        case .idle, .ready, .failed:
            return "Record"
        }
    }

    var primaryActionSymbol: String {
        switch self {
        case .recording:
            return "stop.fill"
        case .transcribing, .warming:
            return "waveform"
        case .idle, .ready, .failed:
            return "mic.fill"
        }
    }

    var isBusyWithoutStop: Bool {
        switch self {
        case .transcribing, .warming:
            return true
        case .idle, .ready, .recording, .failed:
            return false
        }
    }
}
