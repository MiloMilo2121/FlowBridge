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
    @State private var readyPulse = 0
    @State private var failPulse = 0
    @State private var streakPulse = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: FlowTheme.space16) {
                Spacer(minLength: 0)

                OrbView(
                    state: coordinator.state,
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
            .navigationTitle("FlowBridge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        showHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }

                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showPrivacy = true
                    } label: {
                        Image(systemName: "shield.lefthalf.filled")
                    }

                    Button {
                        Task { await coordinator.copyLastTranscript() }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .disabled(coordinator.lastTranscript == nil)
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
                .background(.thinMaterial, in: Capsule(style: .continuous))
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
                    .contentTransition(.numericText(value: coordinator.timeSavedMinutes))

                if coordinator.streakDays > 1 {
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                        Text("\(coordinator.streakDays)")
                            .contentTransition(.numericText())
                    }
                    .foregroundStyle(FlowTheme.accent)
                    .phaseAnimator([1.0, 1.25, 1.0], trigger: streakPulse) { view, scale in
                        view.scaleEffect(scale)
                    } animation: { _ in
                        FlowMotion.celebrate
                    }
                }
            }
            .font(FlowTheme.numeric(14, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .buttonStyle(FlowPressButtonStyle())
        .animation(.smooth(duration: 0.8), value: coordinator.timeSavedMinutes)
        .accessibilityLabel("Time given back: \(Int(coordinator.timeSavedMinutes.rounded())) minutes. Opens statistics.")
    }

    @ViewBuilder
    private var transcriptArea: some View {
        Group {
            if isRecording, let snapshot = coordinator.liveTranscript, !snapshot.text.isEmpty {
                LiveTranscriptView(snapshot: snapshot)
                    .frame(maxHeight: 230)
                    .padding(FlowTheme.space16)
                    .flowCard()
            } else if isRecording {
                Text("Listening…")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .flowCard()
            } else {
                TranscriptPanelView(
                    record: coordinator.lastTranscript,
                    reveal: coordinator.polishReveal
                )
            }
        }
        .animation(FlowMotion.state, value: isRecording)
    }

    private var primaryCapsule: some View {
        Button {
            Task { await coordinator.toggleRecording() }
        } label: {
            Label(coordinator.state.primaryActionTitle, systemImage: coordinator.state.primaryActionSymbol)
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 56)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .tint(isRecording ? .red : FlowTheme.accent)
        .disabled(coordinator.state.isBusyWithoutStop)
        .animation(FlowMotion.state, value: isRecording)
    }

    private var isRecording: Bool {
        if case .recording = coordinator.state {
            return true
        }
        return false
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
