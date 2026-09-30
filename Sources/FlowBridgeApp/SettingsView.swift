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
    @State private var diagnosticsEnabled = DiagnosticsCollector.isEnabled
    @State private var diagnosticReports: [URL] = []
    @State private var cloudEnabled = CloudGate.isCloudEngineEnabled
    @State private var cloudAPIKey = ""
    @State private var showCloudConsent = false
    @State private var vocabularyCount = 0

    private let appendChoices: [(label: String, value: TimeInterval)] = [
        ("Off", 0), ("2 min", 120), ("5 min", 300), ("15 min", 900)
    ]

    var body: some View {
        NavigationStack {
            Form {
                engineSection
                polishSection
                captureSection
                vocabularySection
                statsSection
                cloudSection
                privacySection
                diagnosticsSection
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
                ForEach(availableEngines, id: \.self) { preference in
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

    /// The cloud engine only appears once the user has explicitly enabled it
    /// in the Cloud section below.
    private var availableEngines: [EnginePreference] {
        EnginePreference.allCases.filter { $0 != .cloud || cloudEnabled }
    }

    private var engineFooter: String {
        switch engine {
        case .whisper:
            return "The bundled Whisper model. Everything runs on this iPhone."
        case .whisperPrecision:
            return WhisperModelLocator.precisionFolderIfInstalled() == nil
                ? "No Precision model installed — the bundled model is used. Stage one with scripts/fetch-whisper-precision.sh or sideload it to Application Support/PrecisionModel."
                : "Whisper large-v3-turbo — best multilingual accuracy and Italian/English code-switching, still fully on-device."
        case .appleSpeech:
            return "Apple's on-device speech model (iOS 26). Fastest, best Italian; no custom vocabulary biasing."
        case .cloud:
            return "Live audio goes to \(FlowBridgeConstants.cloudProviderName) in the EU. Your own API key is stored in the Keychain."
        }
    }

    private var polishSection: some View {
        Section {
            Toggle(isOn: $polishEnabled) {
                ChipRow(glyph: .polish, title: "Polish transcripts")
            }
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
            // The three unavailability modes get their own explanation —
            // "device can't", "user turned it off" and "still downloading"
            // are different situations with different remedies.
            if let explanation = TranscriptPolisher.shared.availabilityExplanation {
                Text(explanation)
            } else {
                Text("Fillers out, punctuation fixed — by Apple's on-device model. The verbatim transcript is always kept. The keyboard adapts the tone to the field you're writing in; this is the fallback.")
            }
        }
    }

    private var captureSection: some View {
        Section {
            Toggle(isOn: $voiceCommandsEnabled) {
                ChipRow(glyph: .commands, title: "Spoken commands", subtitle: "“punto” · “virgola” · “a capo”")
            }
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

    private var vocabularySection: some View {
        Section {
            NavigationLink {
                VocabularyEditorView()
            } label: {
                ChipRow(
                    glyph: .vocab,
                    title: "My vocabulary",
                    subtitle: vocabularyCount > 0 ? "\(vocabularyCount) terms" : "Names, brands, jargon"
                )
            }
        } footer: {
            Text("Names, brands, jargon — recognized the way you spell them. The feature system dictation doesn't have.")
        }
    }

    private var statsSection: some View {
        Section {
            LabeledContent("Dictations", value: "\(stats.sessions)")
            LabeledContent("Words", value: "\(stats.words)")
            LabeledContent("Speaking speed", value: stats.wordsPerMinute.formatted(.number.precision(.fractionLength(0))) + " wpm")
            LabeledContent("Time given back", value: stats.timeSavedMinutes.formatted(.number.precision(.fractionLength(0))) + " min")
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

    private var cloudSection: some View {
        Section {
            Toggle(isOn: $cloudEnabled) {
                ChipRow(glyph: .language, tone: .orange, title: "AssemblyAI live transcription")
            }
                .onChange(of: cloudEnabled) { _, newValue in
                    if newValue {
                        let consented = UserDefaults.standard.bool(forKey: FlowBridgeConstants.cloudConsentAcceptedKey)
                        if consented {
                            CloudGate.setCloudEngineEnabled(true)
                        } else {
                            showCloudConsent = true
                        }
                    } else {
                        CloudGate.setCloudEngineEnabled(false)
                        if engine == .cloud {
                            engine = .whisper
                            EnginePreference.set(.whisper)
                        }
                    }
                }

            if cloudEnabled {
                SecureField("\(FlowBridgeConstants.cloudProviderName) API key", text: $cloudAPIKey)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit {
                        KeychainStore.saveCloudAPIKey(cloudAPIKey)
                        if !cloudAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && cloudEnabled {
                            engine = .cloud
                            EnginePreference.set(.cloud)
                        }
                    }
                Button("Save API key and use cloud") {
                    KeychainStore.saveCloudAPIKey(cloudAPIKey)
                    if !cloudAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        engine = .cloud
                        EnginePreference.set(.cloud)
                    }
                }
                .disabled(cloudAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } header: {
            Text("Cloud dictation")
        } footer: {
            Text(cloudEnabled
                ? "Live microphone audio is sent to AssemblyAI's EU endpoint when cloud is selected. Your key stays in this iPhone's Keychain."
                : "Local dictation is active. Enable cloud and enter your own AssemblyAI key to make streaming the default.")
        }
        .confirmationDialog(
            "Send dictations to the cloud?",
            isPresented: $showCloudConsent,
            titleVisibility: .visible
        ) {
            Button("I understand — enable cloud", role: .destructive) {
                UserDefaults.standard.set(true, forKey: FlowBridgeConstants.cloudConsentAcceptedKey)
                CloudGate.setCloudEngineEnabled(true)
            }
            Button("Keep everything on-device", role: .cancel) {
                cloudEnabled = false
            }
        } message: {
            Text("With cloud selected, microphone audio streams to AssemblyAI in the EU as you speak. A local WAV is kept until the transcript is safely delivered. Your diary syncs separately through iCloud Drive.")
        }
    }

    private var privacySection: some View {
        Section {
            ChipRow(
                glyph: .privacy,
                tone: .green,
                title: "Audio & transcripts",
                subtitle: cloudEnabled ? "AssemblyAI EU when cloud is selected" : "Local transcription"
            )
            ChipRow(
                glyph: .onDevice,
                tone: .green,
                title: "Network on the audio path",
                subtitle: cloudEnabled ? "AssemblyAI EU; iCloud syncs the diary" : "iCloud syncs the diary"
            )
        } header: {
            Text("Privacy")
        } footer: {
            Text("Not a policy — an architecture. The app installs a guard that rejects any network request, and dictation works in Airplane Mode. Try it.")
        }
    }

    private var diagnosticsSection: some View {
        Section {
            Toggle(isOn: $diagnosticsEnabled) {
                ChipRow(glyph: .copy, title: "Collect crash reports", subtitle: "Stored on this iPhone only")
            }
                .onChange(of: diagnosticsEnabled) { _, newValue in
                    DiagnosticsCollector.isEnabled = newValue
                    if newValue {
                        DiagnosticsCollector.shared.startIfEnabled()
                    } else {
                        DiagnosticsCollector.shared.stop()
                    }
                }

            if !diagnosticReports.isEmpty {
                LabeledContent("Stored reports", value: "\(diagnosticReports.count)")
                if let latest = diagnosticReports.first {
                    ShareLink(item: latest) {
                        HStack(spacing: 12) {
                            LineaVivaIcon(.share)
                                .frame(width: 20, height: 20)
                            Text("Share latest report")
                        }
                    }
                }
                Button("Delete all reports", role: .destructive) {
                    DiagnosticsCollector.deleteAllReports()
                    diagnosticReports = []
                }
            }
        } header: {
            Text("Diagnostics")
        } footer: {
            Text("Crash and hang reports are produced by iOS, stored only on this iPhone, and sent nowhere. If something breaks, you can review a report here and choose to share it — or delete everything.")
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
        diagnosticsEnabled = DiagnosticsCollector.isEnabled
        diagnosticReports = DiagnosticsCollector.reports()
        vocabularyCount = (try? VocabularyStore())?.terms().count ?? 0
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
