import FlowBridgeShared
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var coordinator: FlowBridgeCoordinator
    @State private var showHistory = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                statusBlock
                primaryButton
                transcriptPanel
                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("FlowBridge")
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        showHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("Dictation history")

                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        Task { await coordinator.copyLastTranscript() }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .disabled(coordinator.lastTranscript == nil)
                    .accessibilityLabel("Copy latest transcript")

                    Button {
                        Task { await coordinator.unloadModel() }
                    } label: {
                        Image(systemName: "memorychip")
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

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(coordinator.state.tint)
                    .frame(width: 10, height: 10)
                Text(coordinator.state.title)
                    .font(.headline)
                Spacer()
                if let elapsed = coordinator.recordingElapsed {
                    Text(elapsed.formatted(.number.precision(.fractionLength(0))) + "s")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            if let message = coordinator.statusMessage {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var primaryButton: some View {
        Button {
            Task { await coordinator.toggleRecording() }
        } label: {
            Label(coordinator.state.primaryActionTitle, systemImage: coordinator.state.primaryActionSymbol)
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 56)
        }
        .buttonStyle(.borderedProminent)
        .disabled(coordinator.state.isBusyWithoutStop)
    }

    private var transcriptPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Latest")
                    .font(.headline)
                Spacer()
                if let record = coordinator.lastTranscript {
                    Text(record.createdAt, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(coordinator.lastTranscript?.text ?? "")
                .font(.body)
                .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
                .textSelection(.enabled)
                .foregroundStyle(coordinator.lastTranscript == nil ? .secondary : .primary)
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private extension FlowBridgeCoordinator.State {
    var tint: Color {
        switch self {
        case .idle, .ready:
            return .green
        case .recording:
            return .red
        case .transcribing, .warming:
            return .orange
        case .failed:
            return .pink
        }
    }

    var title: String {
        switch self {
        case .idle:
            return "Ready"
        case .warming:
            return "Warming"
        case .recording:
            return "Recording"
        case .transcribing:
            return "Transcribing"
        case .ready:
            return "Copied"
        case .failed:
            return "Error"
        }
    }

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

