import FlowBridgeShared
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var coordinator: FlowBridgeCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @State private var showHistory = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            // ScrollView keeps content clear of the floating toolbar and
            // stays usable at accessibility text sizes.
            ScrollView {
                VStack(spacing: FlowTheme.Spacing.stack) {
                    heroCard
                    primaryButton
                    transcriptCard
                    FlowTrailView(openHistory: { showHistory = true })
                }
                .padding(FlowTheme.Spacing.page)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background { AuroraBackground() }
            .navigationTitle("FlowBridge")
            .navigationBarTitleDisplayMode(.inline)
            .animation(FlowTheme.Motion.base, value: coordinator.state)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        showHistory = true
                    } label: {
                        LineaVivaIcon(.history)
                            .frame(width: 19, height: 19)
                    }
                    .accessibilityLabel("Dictation history")

                    Button {
                        showSettings = true
                    } label: {
                        LineaVivaIcon(.settings)
                            .frame(width: 19, height: 19)
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        Task { await coordinator.copyLastTranscript() }
                    } label: {
                        LineaVivaIcon(.copy)
                            .frame(width: 19, height: 19)
                    }
                    .disabled(coordinator.lastTranscript == nil)
                    .accessibilityLabel("Copy latest transcript")

                    Button {
                        Task { await coordinator.unloadModel() }
                    } label: {
                        LineaVivaIcon(.engine)
                            .frame(width: 19, height: 19)
                    }
                    .accessibilityLabel("Unload speech model")
                }
            }
            .sheet(isPresented: $showHistory) {
                HistoryView()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }

    // MARK: Hero — the mesh waveform card (design: "Mesh waveform — reference")

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: FlowTheme.Spacing.m) {
            HStack(alignment: .center) {
                CapsLabel(text: coordinator.state.capsTitle, tone: coordinator.state.capsTone)
                Spacer()
                if let elapsed = coordinator.recordingElapsed {
                    Text(elapsed.formatted(.number.precision(.fractionLength(0))) + "s")
                        .font(.footnote.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(FlowPalette.textSecondary)
                }
                PrivacyDot()
            }

            MeshWaveformView(
                live: coordinator.state.isLive,
                level: coordinator.inputLevel,
                paused: scenePhase != .active || showHistory || showSettings
            )
            .frame(height: 110)

            VStack(alignment: .leading, spacing: 4) {
                Text(engineLine)
                    .font(.footnote)
                    .foregroundStyle(FlowPalette.textSecondary)
                if let message = coordinator.statusMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(FlowPalette.textTertiary)
                        .lineLimit(2)
                }
            }
        }
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(coordinator.state.capsTitle). \(engineLine)"))
    }

    private var engineLine: String {
        let engine = EnginePreference.current
        let locality = engine == .cloud ? "Cloud" : "On-device"
        return "\(engine.displayName) · \(locality)"
    }

    // MARK: Primary CTA

    private var primaryButton: some View {
        Button {
            Task { await coordinator.toggleRecording() }
        } label: {
            HStack(spacing: 10) {
                LineaVivaIcon(coordinator.state.primaryActionGlyph)
                    .frame(width: 20, height: 20)
                Text(coordinator.state.primaryActionTitle)
            }
        }
        .buttonStyle(FlowCTAButtonStyle(tone: coordinator.state.ctaTone))
        .disabled(coordinator.state.isBusyWithoutStop)
        .accessibilityHint(coordinator.state.isLive ? "Stops the dictation" : "Starts a dictation")
    }

    // MARK: Transcript card

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: FlowTheme.Spacing.m) {
            HStack {
                Text("Latest")
                    .font(.headline)
                    .foregroundStyle(FlowPalette.textBody)
                Spacer()
                if let record = coordinator.lastTranscript, !isStreaming {
                    Text(record.createdAt, style: .time)
                        .font(.caption)
                        .foregroundStyle(FlowPalette.textSecondary)
                }
            }

            transcriptBody
                .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        }
        .glassCard()
    }

    private var isStreaming: Bool {
        coordinator.state.isLive && !coordinator.livePartial.isEmpty
    }

    @ViewBuilder
    private var transcriptBody: some View {
        if isStreaming {
            // Words as they land, with the live caret from the design.
            (Text(coordinator.livePartial) + Text(" ▎").foregroundStyle(FlowPalette.stateLive))
                .font(.body.italic())
                .fontDesign(.serif)
                .foregroundStyle(FlowPalette.textBody)
        } else if let record = coordinator.lastTranscript {
            Text(record.text)
                .font(.body.italic())
                .fontDesign(.serif)
                .foregroundStyle(FlowPalette.textBody)
                .textSelection(.enabled)
        } else {
            Text("Your words land here — on this iPhone only.")
                .font(.subheadline)
                .foregroundStyle(FlowPalette.textTertiary)
        }
    }
}

// MARK: - State → design language

private extension FlowBridgeCoordinator.State {
    var capsTitle: String {
        switch self {
        case .idle: return "Ready to bridge"
        case .warming: return "Warming up"
        case .recording: return "Listening"
        case .transcribing: return "Transcribing"
        case .ready: return "Copied · on-device"
        case .failed: return "Error"
        }
    }

    var capsTone: CapsLabel.Tone {
        switch self {
        case .idle, .transcribing: return .accent
        case .warming, .recording: return .attention
        case .ready: return .privacy
        case .failed: return .stop
        }
    }

    var isLive: Bool {
        if case .recording = self { return true }
        return false
    }

    var primaryActionTitle: String {
        switch self {
        case .recording: return "Stop"
        case .transcribing, .warming: return "Working"
        case .idle, .ready, .failed: return "Record"
        }
    }

    var primaryActionGlyph: LineaVivaIcon.Glyph {
        switch self {
        case .recording: return .stop
        case .transcribing, .warming: return .waveform
        case .idle, .ready, .failed: return .dictate
        }
    }

    var ctaTone: FlowCTAButtonStyle.Tone {
        switch self {
        case .recording: return .stop
        case .transcribing, .warming: return .working
        case .idle, .ready, .failed: return .accent
        }
    }

    var isBusyWithoutStop: Bool {
        switch self {
        case .transcribing, .warming: return true
        case .idle, .ready, .recording, .failed: return false
        }
    }
}
