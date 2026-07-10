import FlowBridgeShared
import SwiftUI

/// Few controls, all local: engine, polish, tone, spoken commands, session
/// append, personal vocabulary, and the "time given back" stats.
struct SettingsView: View {
    @EnvironmentObject private var coordinator: FlowBridgeCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var engine = EnginePreference.current
    @State private var polishEnabled = true
    @State private var defaultTone: ToneProfile = .neutral
    @State private var voiceCommandsEnabled = true
    @State private var appendWindow: TimeInterval = FlowBridgeConstants.sessionAppendWindowDefault
    @State private var stats = DictationStatsStore.Stats()
    @State private var hapticsEnabled = true
    @State private var voicePeaksEnabled = false
    @State private var wordTicksEnabled = true

    private let appendChoices: [(label: String, value: TimeInterval)] = [
        ("Off", 0), ("2 min", 120), ("5 min", 300), ("15 min", 900)
    ]

    var body: some View {
        NavigationStack {
            Form {
                engineSection
                polishSection
                captureSection
                hapticsSection
                vocabularySection
                statsSection
                privacySection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear(perform: load)
        }
    }

    private var engineSection: some View {
        Section {
            Picker("Engine", selection: $engine) {
                ForEach(EnginePreference.allCases, id: \.self) { preference in
                    Text(preference.displayName).tag(preference)
                }
            }
            .onChange(of: engine) { _, newValue in
                EnginePreference.set(newValue)
            }
        } header: {
            Text("Transcription")
        } footer: {
            Text(engineFooter)
        }
    }

    private var engineFooter: String {
        let note = " Takes effect the next time the app launches."
        switch engine {
        case .whisper:
            return "The bundled Whisper model. Everything runs on this iPhone." + note
        case .whisperPrecision:
            return (WhisperModelLocator.precisionFolderIfInstalled() == nil
                ? "No Precision model installed — the bundled model is used. Install one under Application Support/PrecisionModel."
                : "Higher-accuracy Whisper model, still fully on-device.") + note
        case .appleSpeech:
            return "Apple's on-device speech model (iOS 26). Fastest, best Italian; no custom vocabulary biasing." + note
        }
    }

    private var polishSection: some View {
        Section {
            Toggle("Polish transcripts", isOn: $polishEnabled)
                .onChange(of: polishEnabled) { _, newValue in
                    let defaults = try? SharedContainer.userDefaults()
                    defaults?.set(newValue, forKey: FlowBridgeConstants.polishEnabledKey)
                }
            Picker("Default tone", selection: $defaultTone) {
                ForEach(ToneProfile.allCases, id: \.self) { tone in
                    Text(tone.displayName).tag(tone)
                }
            }
            .onChange(of: defaultTone) { _, newValue in
                coordinator.toneContext?.setDefaultTone(newValue)
            }
        } header: {
            Text("Cleanup")
        } footer: {
            Text("Fillers out, punctuation fixed — by Apple's on-device model. The verbatim transcript is always kept. The keyboard adapts the tone to the field you're writing in; this is the fallback.")
        }
    }

    private var captureSection: some View {
        Section {
            Toggle("Spoken commands", isOn: $voiceCommandsEnabled)
                .onChange(of: voiceCommandsEnabled) { _, newValue in
                    let defaults = try? SharedContainer.userDefaults()
                    defaults?.set(newValue, forKey: FlowBridgeConstants.voiceCommandsEnabledKey)
                }
            Picker("Continue previous dictation", selection: $appendWindow) {
                ForEach(appendChoices, id: \.value) { choice in
                    Text(choice.label).tag(choice.value)
                }
            }
            .onChange(of: appendWindow) { _, newValue in
                let defaults = try? SharedContainer.userDefaults()
                defaults?.set(newValue, forKey: FlowBridgeConstants.sessionAppendWindowKey)
            }
        } header: {
            Text("Capture")
        } footer: {
            Text("Spoken commands: “punto”, “virgola”, “a capo”, “nuovo paragrafo” — applied literally, in Italian and English. Dictations within the chosen window are delivered as one continued text.")
        }
    }

    private var hapticsSection: some View {
        Section {
            Toggle("Haptics", isOn: $hapticsEnabled)
                .onChange(of: hapticsEnabled) { _, newValue in
                    let defaults = try? SharedContainer.userDefaults()
                    defaults?.set(newValue, forKey: FlowBridgeConstants.hapticsEnabledKey)
                }
            Toggle("Tick as words land", isOn: $wordTicksEnabled)
                .disabled(!hapticsEnabled)
                .onChange(of: wordTicksEnabled) { _, newValue in
                    let defaults = try? SharedContainer.userDefaults()
                    defaults?.set(newValue, forKey: FlowBridgeConstants.hapticWordTickEnabledKey)
                }
            Toggle("Pulse on voice peaks", isOn: $voicePeaksEnabled)
                .disabled(!hapticsEnabled)
                .onChange(of: voicePeaksEnabled) { _, newValue in
                    let defaults = try? SharedContainer.userDefaults()
                    defaults?.set(newValue, forKey: FlowBridgeConstants.hapticVoicePeaksEnabledKey)
                }
        } header: {
            Text("Touch")
        } footer: {
            Text("A fixed vocabulary: heartbeat to start and stop, a crystal tap when the text is ready. The optional textures make dictation followable from the pocket.")
        }
    }

    private var vocabularySection: some View {
        Section {
            NavigationLink {
                VocabularyEditorView()
            } label: {
                Label("My vocabulary", systemImage: "character.book.closed")
            }
        } footer: {
            Text("Names, brands, jargon — recognized the way you spell them. The feature system dictation doesn't have.")
        }
    }

    private var statsSection: some View {
        Section {
            NavigationLink {
                StatsContent()
                    .navigationTitle("Statistics")
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                Label {
                    Text("Statistics")
                } icon: {
                    Image(systemName: "chart.bar.xaxis")
                }
                .badge(stats.timeSavedMinutes.formatted(.number.precision(.fractionLength(0))) + " min")
            }
            Button("Reset statistics", role: .destructive) {
                coordinator.stats?.reset()
                stats = DictationStatsStore.Stats()
            }
        } header: {
            Text("Time given back")
        } footer: {
            Text("Computed on this device, for you. Never collected, never sent.")
        }
    }

    private var privacySection: some View {
        Section {
            NavigationLink {
                PrivacyCockpitContent()
                    .navigationTitle("Privacy")
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                Label("Privacy Cockpit", systemImage: "shield.lefthalf.filled")
            }
        } footer: {
            Text("Not a policy — an architecture. The app installs a guard that rejects any network request, and dictation works in Airplane Mode. Try it.")
        }
    }

    private func load() {
        engine = EnginePreference.current
        let defaults = try? SharedContainer.userDefaults()
        polishEnabled = defaults?.object(forKey: FlowBridgeConstants.polishEnabledKey) as? Bool ?? true
        voiceCommandsEnabled = defaults?.object(forKey: FlowBridgeConstants.voiceCommandsEnabledKey) as? Bool ?? true
        appendWindow = defaults?.object(forKey: FlowBridgeConstants.sessionAppendWindowKey) as? Double
            ?? FlowBridgeConstants.sessionAppendWindowDefault
        defaultTone = coordinator.toneContext?.defaultTone() ?? .neutral
        stats = coordinator.stats?.stats() ?? DictationStatsStore.Stats()
        hapticsEnabled = defaults?.object(forKey: FlowBridgeConstants.hapticsEnabledKey) as? Bool ?? true
        voicePeaksEnabled = defaults?.object(forKey: FlowBridgeConstants.hapticVoicePeaksEnabledKey) as? Bool ?? false
        wordTicksEnabled = defaults?.object(forKey: FlowBridgeConstants.hapticWordTickEnabledKey) as? Bool ?? true
    }
}

/// Add/remove vocabulary terms. Deliberately plain: a list and a field.
struct VocabularyEditorView: View {
    @State private var terms: [String] = []
    @State private var newTerm = ""

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Add a name or term", text: $newTerm)
                        .autocorrectionDisabled()
                        .onSubmit(addTerm)
                    Button(action: addTerm) {
                        Image(systemName: "plus.circle.fill")
                    }
                    .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } footer: {
                Text("Up to \(VocabularyStore.maxTerms) terms. They bias recognition and guide the polisher.")
            }

            Section {
                ForEach(terms, id: \.self) { term in
                    Text(term)
                }
                .onDelete { offsets in
                    let store = try? VocabularyStore()
                    for index in offsets {
                        try? store?.remove(terms[index])
                    }
                    reload()
                }
            }
        }
        .navigationTitle("My vocabulary")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
    }

    private func addTerm() {
        let store = try? VocabularyStore()
        try? store?.add(newTerm)
        newTerm = ""
        reload()
    }

    private func reload() {
        terms = (try? VocabularyStore())?.terms() ?? []
    }
}
