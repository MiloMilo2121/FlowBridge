import FlowBridgeShared
import UIKit

final class KeyboardViewController: UIInputViewController {
    private let eyebrowLabel = UILabel()
    private let previewLabel = UILabel()
    private let insertButton = UIButton(type: .system)
    private let liveButton = UIButton(type: .system)
    private var renderedPreview: String?
    private var liveTimer: Timer?
    private var darwinObserver: DarwinNotificationObserver?
    private var liveModeEnabled = true
    private var lastInsertedText = ""
    private var lastSessionID: UUID?
    private var lastSequence = 0
    private var completedSessionID: UUID?

    override func viewDidLoad() {
        super.viewDidLoad()
        NetworkGuard.install()
        buildInterface()
        refresh()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refresh()
        publishToneHint()
        startLiveUpdates()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stopLiveUpdates()
    }

    private func buildInterface() {
        view.backgroundColor = .clear

        let background = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
        background.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(background)

        eyebrowLabel.font = .preferredFont(forTextStyle: .caption1)
        eyebrowLabel.adjustsFontForContentSizeCategory = true
        eyebrowLabel.textColor = .secondaryLabel
        eyebrowLabel.text = "FLOWBRIDGE · LIVE INSERT"

        let previewSurface = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
        previewSurface.layer.cornerCurve = .continuous
        previewSurface.layer.cornerRadius = 16
        previewSurface.layer.borderWidth = 1 / traitCollection.displayScale
        previewSurface.layer.borderColor = UIColor.separator.withAlphaComponent(0.3).cgColor

        previewLabel.font = .preferredFont(forTextStyle: .callout)
        previewLabel.adjustsFontForContentSizeCategory = true
        previewLabel.textColor = .label
        previewLabel.numberOfLines = 2
        previewLabel.lineBreakMode = .byTruncatingTail
        previewLabel.translatesAutoresizingMaskIntoConstraints = false
        previewSurface.contentView.addSubview(previewLabel)

        NSLayoutConstraint.activate([
            previewLabel.leadingAnchor.constraint(equalTo: previewSurface.contentView.leadingAnchor, constant: 14),
            previewLabel.trailingAnchor.constraint(equalTo: previewSurface.contentView.trailingAnchor, constant: -14),
            previewLabel.topAnchor.constraint(equalTo: previewSurface.contentView.topAnchor, constant: 10),
            previewLabel.bottomAnchor.constraint(equalTo: previewSurface.contentView.bottomAnchor, constant: -10),
            previewSurface.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
        ])

        var insertConfig = UIButton.Configuration.prominentGlass()
        insertConfig.image = UIImage(systemName: "text.insert")
        insertConfig.title = "Insert"
        insertConfig.imagePadding = 7
        insertConfig.baseBackgroundColor = .flowViolet
        insertConfig.baseForegroundColor = .white
        insertButton.configuration = insertConfig
        insertButton.addTarget(self, action: #selector(insertLatestTranscript), for: .touchUpInside)

        let sendButton = UIButton(type: .system)
        sendButton.configuration = glassConfiguration(symbol: "arrow.up.circle.fill", tint: .flowViolet)
        sendButton.addTarget(self, action: #selector(insertLatestTranscriptAndReturn), for: .touchUpInside)
        sendButton.accessibilityLabel = "Insert and send"

        liveButton.configuration = glassConfiguration(symbol: "waveform.circle.fill", tint: .flowViolet)
        liveButton.addTarget(self, action: #selector(toggleLiveMode), for: .touchUpInside)
        liveButton.accessibilityLabel = "Toggle live insertion"

        let deleteButton = UIButton(type: .system)
        deleteButton.configuration = glassConfiguration(symbol: "delete.left")
        deleteButton.addTarget(self, action: #selector(deleteBackward), for: .touchUpInside)
        deleteButton.accessibilityLabel = "Delete backward"

        let nextKeyboardButton = UIButton(type: .system)
        nextKeyboardButton.configuration = glassConfiguration(symbol: "globe")
        nextKeyboardButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        nextKeyboardButton.accessibilityLabel = "Next keyboard"

        let buttonRow = UIStackView(arrangedSubviews: [
            nextKeyboardButton,
            liveButton,
            insertButton,
            sendButton,
            deleteButton,
        ])
        buttonRow.axis = .horizontal
        buttonRow.alignment = .fill
        buttonRow.distribution = .fill
        buttonRow.spacing = 8

        for button in [nextKeyboardButton, liveButton, sendButton, deleteButton] {
            button.widthAnchor.constraint(equalToConstant: 50).isActive = true
            button.heightAnchor.constraint(equalToConstant: 48).isActive = true
        }

        let stack = UIStackView(arrangedSubviews: [eyebrowLabel, previewSurface, buttonRow])
        stack.axis = .vertical
        stack.setCustomSpacing(6, after: eyebrowLabel)
        stack.setCustomSpacing(10, after: previewSurface)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            background.topAnchor.constraint(equalTo: view.topAnchor),
            background.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),
            insertButton.heightAnchor.constraint(equalToConstant: 48),
        ])
    }

    private func glassConfiguration(symbol: String, tint: UIColor = .label) -> UIButton.Configuration {
        var configuration = UIButton.Configuration.glass()
        configuration.image = UIImage(systemName: symbol)
        configuration.baseForegroundColor = tint
        return configuration
    }

    private func refresh() {
        let record = TranscriptStore.latest()
        let live = LiveTranscriptStore.latest()
        let nextPreview = live?.previewText.isEmpty == false ? live?.previewText : record?.text
        let display = nextPreview ?? "Speak from the Action Button. Your words will appear here."

        if renderedPreview != display {
            renderedPreview = display
            UIView.transition(
                with: previewLabel,
                duration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.20,
                options: [.transitionCrossDissolve, .allowAnimatedContent]
            ) {
                self.previewLabel.text = display
                self.previewLabel.textColor = nextPreview == nil ? .secondaryLabel : .label
            }
        }

        insertButton.isEnabled = record?.text.isEmpty == false
        liveButton.configuration = glassConfiguration(
            symbol: liveModeEnabled ? "waveform.circle.fill" : "waveform.circle",
            tint: liveModeEnabled ? .flowViolet : .secondaryLabel
        )
        liveButton.accessibilityValue = liveModeEnabled ? "On" : "Off"
    }

    @objc private func insertLatestTranscript() {
        refresh()
        guard let text = TranscriptStore.latest()?.text, !text.isEmpty else { return }
        textDocumentProxy.insertText(text)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    /// Insert the transcript and hit return. In chat fields the return key
    /// generally sends, so one tap completes the whole bridge.
    @objc private func insertLatestTranscriptAndReturn() {
        refresh()
        guard let text = TranscriptStore.latest()?.text, !text.isEmpty else { return }
        textDocumentProxy.insertText(text)
        textDocumentProxy.insertText("\n")
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Tone from public field traits: a send field is casual; an email field
    /// is formal. The keyboard never inspects the host app's identity.
    private func publishToneHint() {
        let profile: ToneProfile
        if textDocumentProxy.returnKeyType == .send {
            profile = .casual
        } else if textDocumentProxy.keyboardType == .emailAddress {
            profile = .formal
        } else {
            profile = .neutral
        }
        (try? ToneContextStore())?.writeHint(ToneHint(profile: profile))
    }

    @objc private func toggleLiveMode() {
        liveModeEnabled.toggle()
        UISelectionFeedbackGenerator().selectionChanged()
        refresh()
    }

    @objc private func deleteBackward() {
        textDocumentProxy.deleteBackward()
    }

    /// Push notifications drive normal updates; the timer is only a slow
    /// safety net for a coalesced Darwin notification.
    private func startLiveUpdates() {
        darwinObserver = DarwinNotificationObserver(
            name: FlowBridgeConstants.liveTranscriptDidChangeDarwinName
        ) { [weak self] in
            MainActor.assumeIsolated {
                self?.applyLiveSnapshotIfNeeded()
            }
        }

        let interval = FlowBridgeConstants.keyboardLegacyPollingEnabled
            ? FlowBridgeConstants.keyboardLegacyPollingInterval
            : FlowBridgeConstants.keyboardSafetyRefreshInterval

        liveTimer?.invalidate()
        liveTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.applyLiveSnapshotIfNeeded()
            }
        }
    }

    private func stopLiveUpdates() {
        darwinObserver = nil
        liveTimer?.invalidate()
        liveTimer = nil
    }

    private func applyLiveSnapshotIfNeeded() {
        refresh()
        guard liveModeEnabled, let snapshot = LiveTranscriptStore.latest() else { return }
        guard !(snapshot.isFinal && completedSessionID == snapshot.sessionID) else { return }

        if snapshot.sessionID != lastSessionID {
            lastInsertedText = ""
            lastSequence = 0
            completedSessionID = nil
            lastSessionID = snapshot.sessionID
        }

        guard snapshot.sequence > lastSequence else { return }
        lastSequence = snapshot.sequence

        let nextText = snapshot.text
        guard nextText != lastInsertedText else {
            if snapshot.isFinal { completedSessionID = snapshot.sessionID }
            return
        }

        applyIncrementalDiff(from: lastInsertedText, to: nextText)
        lastInsertedText = nextText

        if snapshot.isFinal { completedSessionID = snapshot.sessionID }
    }

    /// Replace only the unstable suffix; the committed prefix never flickers.
    private func applyIncrementalDiff(from old: String, to new: String) {
        let oldChars = Array(old)
        let newChars = Array(new)

        var commonPrefix = 0
        let limit = min(oldChars.count, newChars.count)
        while commonPrefix < limit, oldChars[commonPrefix] == newChars[commonPrefix] {
            commonPrefix += 1
        }

        for _ in 0..<(oldChars.count - commonPrefix) {
            textDocumentProxy.deleteBackward()
        }

        if commonPrefix < newChars.count {
            textDocumentProxy.insertText(String(newChars[commonPrefix...]))
        }
    }
}

private extension UIColor {
    static let flowViolet = UIColor(red: 0.486, green: 0.424, blue: 1.0, alpha: 1)
}
