import FlowBridgeShared
import SwiftUI

/// Interrupted dictations that automatic recovery gave up on. The audio is
/// never deleted behind the user's back, so this is where it goes instead:
/// transcribe it again, export the WAV, or discard it explicitly.
struct UnrecoveredDictationsView: View {
    @EnvironmentObject private var coordinator: FlowBridgeCoordinator

    @State private var inFlight: URL?
    @State private var pendingDiscard: AudioSafetyBuffer.PendingRecording?
    @State private var lastOutcome: String?

    var body: some View {
        List {
            Section {
                ForEach(coordinator.unrecoveredDictations, id: \.url) { recording in
                    row(for: recording)
                }
            } footer: {
                Text("These dictations were interrupted and could not be transcribed automatically. The audio is stored only on this iPhone and stays here until you transcribe or delete it.")
            }

            if let lastOutcome {
                Section {
                    Text(lastOutcome)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .overlay {
            if coordinator.unrecoveredDictations.isEmpty {
                ContentUnavailableView(
                    "Nothing to recover",
                    systemImage: "checkmark.circle",
                    description: Text("Every interrupted dictation has been transcribed or deleted.")
                )
            }
        }
        .navigationTitle("Unrecovered dictations")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { coordinator.refreshUnrecoveredDictations() }
        .confirmationDialog(
            "Delete this dictation?",
            isPresented: Binding(
                get: { pendingDiscard != nil },
                set: { if !$0 { pendingDiscard = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDiscard
        ) { recording in
            Button("Delete audio", role: .destructive) {
                coordinator.discardUnrecoveredDictation(recording)
                pendingDiscard = nil
            }
            Button("Keep", role: .cancel) {
                pendingDiscard = nil
            }
        } message: { _ in
            Text("This is the only copy of the recording. It cannot be recovered after deletion.")
        }
    }

    private func row(for recording: AudioSafetyBuffer.PendingRecording) -> some View {
        let isTranscribing = inFlight == recording.url
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title(for: recording))
                Text(Duration.seconds(recording.duration).formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated)))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            Spacer()

            if isTranscribing {
                ProgressView()
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Transcribing")
            } else {
                Button("Transcribe") {
                    transcribe(recording)
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
                .disabled(inFlight != nil)
                .accessibilityHint("Transcribes the saved audio and copies the text to the clipboard")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                pendingDiscard = recording
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(isTranscribing)
        }
        .contextMenu {
            ShareLink(item: recording.url) {
                Label("Export audio", systemImage: "square.and.arrow.up")
            }
            Button(role: .destructive) {
                pendingDiscard = recording
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(isTranscribing)
        }
    }

    private func title(for recording: AudioSafetyBuffer.PendingRecording) -> String {
        guard let recordedAt = recording.recordedAt else { return "Interrupted dictation" }
        return recordedAt.formatted(date: .abbreviated, time: .shortened)
    }

    private func transcribe(_ recording: AudioSafetyBuffer.PendingRecording) {
        inFlight = recording.url
        lastOutcome = nil
        Task {
            let recovered = await coordinator.retryUnrecoveredDictation(recording)
            inFlight = nil
            lastOutcome = recovered
                ? "Transcribed — the text is on the clipboard."
                : coordinator.statusMessage ?? "The dictation could not be transcribed."
        }
    }
}
