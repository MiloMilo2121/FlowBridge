import FlowBridgeShared
import SwiftUI

/// Few controls, all local: engine, polish, tone, spoken commands, session
/// append, personal vocabulary, and the "time given back" stats.
struct SettingsView: View {
    @EnvironmentObject private var coordinator: FlowBridgeCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var engine = EnginePreference.current
    @State private var language = DictationLanguage.current
    @State private var finalPassMode = FinalPassMode.current
    @State private var speakersEnabled = SpeakerDetection.isEnabled
    @State private var hasCloudKey = CloudCredentialsStore.hasKey
    @State private var cloudKeyInput = ""
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
                statusHeroSection
                Group {
                    engineSection
                    cloudSection
                    polishSection
                    captureSection
                    accessSection
                    hapticsSection
                    vocabularySection
                    statsSection
                    privacySection
                }
                .listRowBackground(FlowTheme.surfaceRaised)
            }
            .scrollContentBackground(.hidden)
            .background(RoomBackground())
            .listSectionSpacing(FlowTheme.space20)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
            .onAppear(perform: load)
        }
    }

    /// "What is my dictation doing right now" — one glance, no digging.
    private var statusHeroSection: some View {
        Section {
            HStack(spacing: FlowTheme.space12) {
                Circle()
                    .fill(cloudActive ? Color.orange : Color.green)
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(engine.displayName)
                        .font(.headline)
                    Text("\(language.displayName) · Final pass: \(finalPassMode.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: cloudActive ? "cloud.fill" : "iphone")
                    .foregroundStyle(.secondary)
            }
            .padding(FlowTheme.space16)
            .flowCard()
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    private var cloudActive: Bool {
        finalPassMode == .cloudScribe || engine == .cloudRealtime
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
            Picker("Language", selection: $language) {
                ForEach(DictationLanguage.allCases, id: \.self) { choice in
                    Text(choice.displayName).tag(choice)
                }
            }
            .onChange(of: language) { _, newValue in
                DictationLanguage.set(newValue)
            }
            Picker("Final pass", selection: $finalPassMode) {
                ForEach(availableFinalPassModes, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .onChange(of: finalPassMode) { _, newValue in
                FinalPassMode.set(newValue)
            }
            Toggle("Detect speakers", isOn: $speakersEnabled)
                .onChange(of: speakersEnabled) { _, newValue in
                    SpeakerDetection.set(newValue)
                }
        } header: {
            Text("Transcription").flowEyebrow()
        } footer: {
            Text(engineFooter + " Pinning the language noticeably improves accuracy; auto-detect struggles on short phrases. The final pass re-transcribes the whole recording once you stop — a moment slower, distinctly more accurate. Speaker detection labels who said what when more than one voice is heard; it runs in the final pass, and quietly uses the on-device Precision pass when the final pass is off. Engine changes apply from the next app launch.")
        }
    }

    private var availableFinalPassModes: [FinalPassMode] {
        FinalPassMode.allCases.filter { $0 != .cloudScribe || hasCloudKey }
    }

    private var cloudSection: some View {
        Section {
            if hasCloudKey {
                LabeledContent("API key", value: "Saved ✓")
                Button("Remove key", role: .destructive) {
                    CloudCredentialsStore.delete()
                    hasCloudKey = false
                    if finalPassMode == .cloudScribe {
                        finalPassMode = .localPrecision
                        FinalPassMode.set(.localPrecision)
                    }
                }
            } else {
                SecureField("ElevenLabs API key", text: $cloudKeyInput)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button("Save key") {
                    if CloudCredentialsStore.save(cloudKeyInput) {
                        cloudKeyInput = ""
                        hasCloudKey = true
                    }
                }
                .disabled(cloudKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Cloud transcription (ElevenLabs)").flowEyebrow()
        } footer: {
            Text("Optional. When a cloud option is active, the audio of your dictation is sent to ElevenLabs for transcription — nothing else, never in the background. The key lives in this device's Keychain. The Privacy Cockpit shows every cloud request.")
        }
    }

    private var engineFooter: String {
        let note = " Takes effect from the next dictation."
        switch engine {
        case .whisper:
            return "The bundled Whisper model. Everything runs on this iPhone." + note
        case .whisperPrecision:
            return (WhisperModelLocator.precisionFolderIfInstalled() == nil
                ? "No Precision model installed — the bundled model is used. Install one under Application Support/PrecisionModel."
                : "Higher-accuracy Whisper model, still fully on-device.") + note
        case .appleSpeech:
            return "Apple's on-device speech model (iOS 26). Fastest, and your vocabulary biases it too." + note
        case .cloudRealtime:
            return "ElevenLabs Scribe v2 live over the network (~150ms): audio leaves this device while you dictate. Falls back to on-device when unreachable." + note
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
            Text("Cleanup").flowEyebrow()
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
            Text("Capture").flowEyebrow()
        } footer: {
            Text("Spoken commands: “punto”, “virgola”, “a capo”, “nuovo paragrafo” — applied literally, in Italian and English. Dictations within the chosen window are delivered as one continued text.")
        }
    }

    /// Every way in that doesn't require opening the app. Informational —
    /// iOS owns these switches, so the rows say exactly where they live.
    private var accessSection: some View {
        Section {
            accessRow(
                symbol: "button.vertical.left.press",
                title: "Action Button",
                detail: "Settings → Action Button → choose FlowBridge “Quick Dictation”."
            )
            accessRow(
                symbol: "hand.tap",
                title: "Back Tap",
                detail: "Settings → Accessibility → Touch → Back Tap → pick the “Quick Dictation” shortcut."
            )
            accessRow(
                symbol: "lock.iphone",
                title: "Lock Screen widget",
                detail: "Hold the Lock Screen → Customize → add the FlowBridge “Speak” widget."
            )
            accessRow(
                symbol: "switch.2",
                title: "Control Center",
                detail: "Open Control Center → hold to edit → add the FlowBridge control."
            )
        } header: {
            Text("Access").flowEyebrow()
        } footer: {
            Text("Dictation starts in the background from any of these — live progress lands in the Dynamic Island, no need to open the app.")
        }
    }

    private func accessRow(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: FlowTheme.space12) {
            Image(systemName: symbol)
                .foregroundStyle(FlowTheme.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
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
            Text("Touch").flowEyebrow()
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
            Text("Time given back").flowEyebrow()
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
        language = DictationLanguage.current
        finalPassMode = FinalPassMode.current
        speakersEnabled = SpeakerDetection.isEnabled
        hasCloudKey = CloudCredentialsStore.hasKey
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
