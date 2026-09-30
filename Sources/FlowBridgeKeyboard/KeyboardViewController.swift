import FlowBridgeShared
import UIKit

final class KeyboardViewController: UIInputViewController {
    private let previewLabel = UILabel()
    private let statusLabel = UILabel()
    private let insertButton = UIButton(type: .system)
    private let liveButton = UIButton(type: .system)
    private var liveTimer: Timer?
    private var darwinObserver: DarwinNotificationObserver?
    private var liveModeEnabled = true
    private var lastInsertedText = ""
    private var lastSessionID: UUID?
    private var lastSequence = 0
    private var completedSessionID: UUID?
    private var lastPublishedTone: ToneProfile?
    /// Set when the field no longer matches what we inserted (the user
    /// typed, moved the caret, or the host app auto-corrected): from that
    /// moment we stop touching the field for the rest of the session — the
    /// finished transcript stays available via Insert and the clipboard.
    private var liveInsertAborted = false
    private var uppercase = false
    private var characterButtons: [UIButton] = []

    isolated deinit {
        liveTimer?.invalidate()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NetworkGuard.install()
        buildInterface()
        refresh()
        FBLog.log("kb load fullAccess=\(hasFullAccess) hasTranscript=\(TranscriptStore.latest()?.text.isEmpty == false)", category: "keyboard")
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

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        // The user may have moved to a different field without the keyboard
        // disappearing; keep the tone hint in sync (cached — no-op unless it
        // actually changed).
        publishToneHint()
    }

    private func buildInterface() {
        view.backgroundColor = FlowPaletteUIKit.keyboardBackground

        // The transcript voice: serif italic, matching the app and island.
        let calloutDescriptor = UIFont.preferredFont(forTextStyle: .callout).fontDescriptor
        let serifItalic = calloutDescriptor
            .withDesign(.serif)?
            .withSymbolicTraits(.traitItalic)
        previewLabel.font = serifItalic.map { UIFont(descriptor: $0, size: 0) }
            ?? .preferredFont(forTextStyle: .callout)
        previewLabel.textColor = .secondaryLabel
        previewLabel.numberOfLines = 2
        previewLabel.lineBreakMode = .byTruncatingTail
        statusLabel.font = .preferredFont(forTextStyle: .caption2)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 2

        insertButton.setImage(UIImage(systemName: "text.insert"), for: .normal)
        insertButton.setTitle(" Insert", for: .normal)
        insertButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        insertButton.addTarget(self, action: #selector(insertLatestTranscript), for: .touchUpInside)
        insertButton.accessibilityLabel = "Insert latest transcript"

        let sendButton = UIButton(type: .system)
        sendButton.setImage(UIImage(systemName: "arrow.turn.down.left"), for: .normal)
        sendButton.addTarget(self, action: #selector(insertLatestTranscriptAndReturn), for: .touchUpInside)
        sendButton.widthAnchor.constraint(equalToConstant: 54).isActive = true
        sendButton.accessibilityLabel = "Insert transcript and send"

        liveButton.setImage(UIImage(systemName: "waveform.circle.fill"), for: .normal)
        liveButton.addTarget(self, action: #selector(toggleLiveMode), for: .touchUpInside)
        liveButton.accessibilityLabel = "Live insertion"

        let deleteButton = UIButton(type: .system)
        deleteButton.setImage(UIImage(systemName: "delete.left"), for: .normal)
        deleteButton.addTarget(self, action: #selector(deleteBackward), for: .touchUpInside)
        deleteButton.accessibilityLabel = "Delete backward"

        let nextKeyboardButton = UIButton(type: .system)
        nextKeyboardButton.setImage(UIImage(systemName: "globe"), for: .normal)
        nextKeyboardButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        nextKeyboardButton.accessibilityLabel = "Next keyboard"

        let buttonRow = UIStackView(arrangedSubviews: [nextKeyboardButton, liveButton, insertButton, sendButton, deleteButton])
        buttonRow.axis = .horizontal
        buttonRow.alignment = .fill
        buttonRow.distribution = .fill
        buttonRow.spacing = 10

        // Key chips: 12pt radius on the key fill; the primary Insert key
        // carries the brand accent (design: violet = primary action).
        for key in [nextKeyboardButton, liveButton, sendButton, deleteButton] {
            key.backgroundColor = FlowPaletteUIKit.key
            key.layer.cornerRadius = 12
            key.layer.cornerCurve = .continuous
            key.tintColor = .label
        }
        insertButton.backgroundColor = FlowPaletteUIKit.accent
        insertButton.layer.cornerRadius = 12
        insertButton.layer.cornerCurve = .continuous
        insertButton.tintColor = .white

        nextKeyboardButton.widthAnchor.constraint(equalToConstant: 54).isActive = true
        liveButton.widthAnchor.constraint(equalToConstant: 54).isActive = true
        deleteButton.widthAnchor.constraint(equalToConstant: 54).isActive = true

        let characterRows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"].map { letters -> UIStackView in
            let buttons = letters.map { character -> UIButton in
                let button = UIButton(type: .system)
                button.setTitle(String(character), for: .normal)
                button.titleLabel?.font = .preferredFont(forTextStyle: .body)
                button.backgroundColor = FlowPaletteUIKit.key
                button.tintColor = .label
                button.layer.cornerRadius = 5
                button.addTarget(self, action: #selector(typeCharacter(_:)), for: .touchUpInside)
                characterButtons.append(button)
                return button
            }
            let row = UIStackView(arrangedSubviews: buttons)
            row.axis = .horizontal
            row.distribution = .fillEqually
            row.spacing = 3
            return row
        }
        let shift = typingKey("shift", image: "shift", action: #selector(toggleShift))
        let space = typingKey("space", image: nil, action: #selector(typeSpace))
        let period = typingKey(".", image: nil, action: #selector(typePeriod))
        let enter = typingKey("return", image: "return", action: #selector(typeReturn))
        shift.widthAnchor.constraint(equalToConstant: 44).isActive = true
        period.widthAnchor.constraint(equalToConstant: 38).isActive = true
        enter.widthAnchor.constraint(equalToConstant: 62).isActive = true
        let lastRow = UIStackView(arrangedSubviews: [shift, space, period, enter])
        lastRow.axis = .horizontal
        lastRow.spacing = 3

        let stack = UIStackView(arrangedSubviews: [statusLabel, previewLabel, buttonRow] + characterRows + [lastRow])
        stack.axis = .vertical
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),
            insertButton.heightAnchor.constraint(equalToConstant: 40),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 292)
        ])
        for row in characterRows { row.heightAnchor.constraint(equalToConstant: 37).isActive = true }
        lastRow.heightAnchor.constraint(equalToConstant: 37).isActive = true
    }

    private func typingKey(_ title: String, image: String?, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        if let image { button.setImage(UIImage(systemName: image), for: .normal) }
        else { button.setTitle(title, for: .normal) }
        button.backgroundColor = FlowPaletteUIKit.key
        button.tintColor = .label
        button.layer.cornerRadius = 5
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    @objc private func typeCharacter(_ sender: UIButton) {
        guard let value = sender.title(for: .normal) else { return }
        textDocumentProxy.insertText(value)
        if uppercase { toggleShift() }
    }
    @objc private func typeSpace() { textDocumentProxy.insertText(" ") }
    @objc private func typePeriod() { textDocumentProxy.insertText(".") }
    @objc private func typeReturn() { textDocumentProxy.insertText("\n") }
    @objc private func toggleShift() {
        uppercase.toggle()
        for button in characterButtons {
            button.setTitle(uppercase ? button.title(for: .normal)?.uppercased()
                                    : button.title(for: .normal)?.lowercased(), for: .normal)
        }
    }

    private func refresh(live: LiveTranscriptSnapshot? = nil) {
        // A keyboard extension can only reach the shared App Group (where the
        // transcript lives) with "Allow Full Access" ON. Without it every
        // read returns nil and Insert would silently do nothing — say so.
        guard hasFullAccess else {
            statusLabel.text = "Typing works. Enable Full Access to insert FlowBridge transcripts."
            previewLabel.text = "Settings › General › Keyboard › FlowBridge"
            insertButton.isEnabled = false
            liveButton.isEnabled = false
            return
        }
        liveButton.isEnabled = true
        let record = TranscriptStore.latest()
        let liveSnapshot = live ?? LiveTranscriptStore.latest()
        if liveInsertAborted {
            statusLabel.text = "Live insert paused: cursor or text changed. Use Insert after checking the field."
        } else if let liveSnapshot, liveSnapshot.isRecording {
            statusLabel.text = "● Listening · live insert \(liveModeEnabled ? "on" : "off")"
        } else if let liveSnapshot, liveSnapshot.isFinal, liveSnapshot.text.isEmpty,
                  !liveSnapshot.previewText.isEmpty {
            statusLabel.text = liveSnapshot.previewText
        } else {
            statusLabel.text = "Ready · last transcript stays in the clipboard"
        }
        previewLabel.text = liveSnapshot?.previewText.isEmpty == false ? liveSnapshot?.previewText : record?.text
        insertButton.isEnabled = record?.text.isEmpty == false
        liveButton.tintColor = liveModeEnabled ? FlowPaletteUIKit.accent : .secondaryLabel
    }

    @objc private func insertLatestTranscript() {
        refresh()
        guard textDocumentProxy.isSecureTextEntry != true,
              let text = TranscriptStore.latest()?.text, !text.isEmpty else { return }
        textDocumentProxy.insertText(text)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Insert the transcript and hit return — in most chat apps the return
    /// key sends, so one tap goes from clipboard to sent message.
    @objc private func insertLatestTranscriptAndReturn() {
        refresh()
        guard textDocumentProxy.isSecureTextEntry != true,
              let text = TranscriptStore.latest()?.text, !text.isEmpty else { return }
        textDocumentProxy.insertText(text)
        textDocumentProxy.insertText("\n")
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Tone from the active field's traits (public API; keyboards cannot see
    /// the host app's identity): a "send" return key is a chat box → casual;
    /// an email-address field belongs to a mail flow → formal.
    private func publishToneHint() {
        let profile: ToneProfile
        if textDocumentProxy.returnKeyType == .send {
            profile = .casual
        } else if textDocumentProxy.keyboardType == .emailAddress {
            profile = .formal
        } else {
            profile = .neutral
        }
        guard profile != lastPublishedTone else { return }
        lastPublishedTone = profile
        (try? ToneContextStore())?.writeHint(ToneHint(profile: profile))
    }

    @objc private func toggleLiveMode() {
        liveModeEnabled.toggle()
        refresh()
    }

    @objc private func deleteBackward() {
        textDocumentProxy.deleteBackward()
    }

    /// Live updates are push-based: the app posts a Darwin notification after
    /// every snapshot write and the keyboard reloads on delivery. A timer
    /// remains as the fallback path — at the legacy 250ms cadence when the
    /// compatibility flag is on, otherwise as a slow safety refresh that
    /// covers a missed notification without burning CPU.
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
            MainActor.assumeIsolated {
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
        let latest = LiveTranscriptStore.latest()
        refresh(live: latest)
        guard liveModeEnabled, let snapshot = latest else { return }
        // Never dictate into password/secure fields.
        guard textDocumentProxy.isSecureTextEntry != true else { return }
        guard !(snapshot.isFinal && completedSessionID == snapshot.sessionID) else { return }

        if snapshot.sessionID != lastSessionID {
            lastInsertedText = ""
            lastSequence = 0
            completedSessionID = nil
            liveInsertAborted = false
            lastSessionID = snapshot.sessionID
        }

        guard !liveInsertAborted else {
            if snapshot.isFinal {
                completedSessionID = snapshot.sessionID
            }
            return
        }

        guard snapshot.sequence > lastSequence else { return }
        lastSequence = snapshot.sequence

        let nextText = snapshot.text
        guard nextText != lastInsertedText else {
            if snapshot.isFinal {
                completedSessionID = snapshot.sessionID
            }
            return
        }

        // Desync guard: only delete when the text before the caret still
        // ends with what we inserted. If it doesn't, deleting would eat the
        // user's own characters — stop live insertion for this session.
        guard fieldStillMatchesInsertedText() else {
            liveInsertAborted = true
            statusLabel.text = "Live insert paused: cursor or text changed. Use Insert."
            if snapshot.isFinal {
                completedSessionID = snapshot.sessionID
            }
            return
        }

        guard applyIncrementalDiff(from: lastInsertedText, to: nextText) else {
            liveInsertAborted = true
            statusLabel.text = "Large rewrite paused. Check the field, then use Insert."
            return
        }
        lastInsertedText = nextText

        if snapshot.isFinal {
            completedSessionID = snapshot.sessionID
        }
    }

    /// True when the host field's context before the caret is consistent
    /// with `lastInsertedText`. The proxy context window is truncated (a few
    /// hundred chars), so when it's shorter we verify the visible tail;
    /// conservative failures abort live insertion rather than risk deleting
    /// user text.
    private func fieldStillMatchesInsertedText() -> Bool {
        guard !lastInsertedText.isEmpty else { return true }
        let context = textDocumentProxy.documentContextBeforeInput ?? ""
        guard !context.isEmpty else { return false }
        if context.count >= lastInsertedText.count {
            return context.hasSuffix(lastInsertedText)
        }
        return lastInsertedText.hasSuffix(context)
    }

    /// Replaces only the unstable tail instead of delete-all/reinsert: the
    /// committed prefix never flickers and long dictations stay smooth.
    private func applyIncrementalDiff(from old: String, to new: String) -> Bool {
        let oldChars = Array(old)
        let newChars = Array(new)

        var commonPrefix = 0
        let limit = min(oldChars.count, newChars.count)
        while commonPrefix < limit, oldChars[commonPrefix] == newChars[commonPrefix] {
            commonPrefix += 1
        }

        // UITextDocumentProxy has no batch-delete API. A large correction
        // causes host autocorrect to race individual deletes, so stop safely.
        guard oldChars.count - commonPrefix <= 32 else { return false }
        for _ in 0..<(oldChars.count - commonPrefix) {
            textDocumentProxy.deleteBackward()
        }

        if commonPrefix < newChars.count {
            textDocumentProxy.insertText(String(newChars[commonPrefix...]))
        }
        return true
    }
}
