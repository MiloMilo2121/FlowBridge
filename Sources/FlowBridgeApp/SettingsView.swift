import FlowBridgeShared
import SwiftUI

/// The transcription key and, when there is any, audio that automatic
/// recovery could not transcribe.
struct SettingsView: View {
    @EnvironmentObject private var coordinator: FlowBridgeCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var cloudAPIKey = ""
    @State private var keySaveTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                if !coordinator.unrecoveredDictations.isEmpty {
                    recoverySection
                }
                cloudSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear(perform: load)
            // A pending debounce must not be lost to a dismissal, and a key
            // left unsaved on purpose must not be written on the way out.
            .onDisappear {
                guard keySaveTask != nil else { return }
                keySaveTask?.cancel()
                keySaveTask = nil
                KeychainStore.saveCloudAPIKey(cloudAPIKey)
            }
        }
    }

    /// Only shown when there is something to act on: audio that automatic
    /// recovery could not transcribe is surfaced first, because it is the
    /// user's dictation and nothing else will ever pick it up.
    private var recoverySection: some View {
        Section {
            NavigationLink {
                UnrecoveredDictationsView()
            } label: {
                LabeledContent {
                    Text("\(coordinator.unrecoveredDictations.count)")
                } label: {
                    Label("Unrecovered dictations", systemImage: "waveform.badge.exclamationmark")
                }
            }
        } footer: {
            Text("Interrupted dictations that could not be transcribed automatically. The audio is still on this iPhone.")
        }
    }

    /// Persists the API key after the user stops typing. `.onSubmit` alone
    /// loses the key whenever the field is dismissed without pressing
    /// Return (Settings closed, scene backgrounded), which silently leaves
    /// the cloud engine unconfigured.
    private func scheduleCloudAPIKeySave() {
        keySaveTask?.cancel()
        let key = cloudAPIKey
        keySaveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            KeychainStore.saveCloudAPIKey(key)
        }
    }

    private var cloudSection: some View {
        Section {
            SecureField("\(FlowBridgeConstants.cloudProviderName) API key", text: $cloudAPIKey)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: cloudAPIKey) { _, _ in
                    scheduleCloudAPIKeySave()
                }
                .onSubmit {
                    keySaveTask?.cancel()
                    KeychainStore.saveCloudAPIKey(cloudAPIKey)
                }
        } header: {
            Text("Transcription")
        } footer: {
            Text("Dictation audio is uploaded to \(FlowBridgeConstants.cloudProviderName) when you stop. The key is stored in the Keychain.")
        }
    }

    private func load() {
        cloudAPIKey = KeychainStore.loadCloudAPIKey() ?? ""
        coordinator.refreshUnrecoveredDictations()
    }
}
