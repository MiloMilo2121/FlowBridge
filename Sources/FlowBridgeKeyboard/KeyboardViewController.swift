import FlowBridgeShared
import UIKit

final class KeyboardViewController: UIInputViewController {
    private let previewLabel = UILabel()
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

    deinit {
        liveTimer?.invalidate()
    }

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

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        // The user may have moved to a different field without the keyboard
        // disappearing; keep the tone hint in sync (cached — no-op unless it
        // actually changed).
        publishToneHint()
    }

    private func buildInterface() {
        view.backgroundColor = .systemBackground

        previewLabel.font = .preferredFont(forTextStyle: .callout)
        previewLabel.textColor = .secondaryLabel
        previewLabel.numberOfLines = 2
        previewLabel.lineBreakMode = .byTruncatingTail

        insertButton.setImage(UIImage(systemName: "text.insert"), for: .normal)
        insertButton.setTitle(" Insert", for: .normal)
        insertButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        insertButton.addTarget(self, action: #selector(insertLatestTranscript), for: .touchUpInside)

        let sendButton = UIButton(type: .system)
        sendButton.setImage(UIImage(systemName: "arrow.turn.down.left"), for: .normal)
        sendButton.addTarget(self, action: #selector(insertLatestTranscriptAndReturn), for: .touchUpInside)
        sendButton.widthAnchor.constraint(equalToConstant: 54).isActive = true

        liveButton.setImage(UIImage(systemName: "waveform.circle.fill"), for: .normal)
        liveButton.addTarget(self, action: #selector(toggleLiveMode), for: .touchUpInside)

        let deleteButton = UIButton(type: .system)
        deleteButton.setImage(UIImage(systemName: "delete.left"), for: .normal)
        deleteButton.addTarget(self, action: #selector(deleteBackward), for: .touchUpInside)

        let nextKeyboardButton = UIButton(type: .system)
        nextKeyboardButton.setImage(UIImage(systemName: "globe"), for: .normal)
        nextKeyboardButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)

        let buttonRow = UIStackView(arrangedSubviews: [nextKeyboardButton, liveButton, insertButton, sendButton, deleteButton])
        buttonRow.axis = .horizontal
        buttonRow.alignment = .fill
        buttonRow.distribution = .fill
        buttonRow.spacing = 10

        nextKeyboardButton.widthAnchor.constraint(equalToConstant: 54).isActive = true
        liveButton.widthAnchor.constraint(equalToConstant: 54).isActive = true
        deleteButton.widthAnchor.constraint(equalToConstant: 54).isActive = true

        let stack = UIStackView(arrangedSubviews: [previewLabel, buttonRow])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),
            insertButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func refresh(live: LiveTranscriptSnapshot? = nil) {
        let record = TranscriptStore.latest()
        let liveSnapshot = live ?? LiveTranscriptStore.latest()
        previewLabel.text = liveSnapshot?.previewText.isEmpty == false ? liveSnapshot?.previewText : record?.text
        insertButton.isEnabled = record?.text.isEmpty == false
        liveButton.tintColor = liveModeEnabled ? .systemBlue : .secondaryLabel
    }

    @objc private func insertLatestTranscript() {
        refresh()
        guard textDocumentProxy.isSecureTextEntry != true,
              let text = TranscriptStore.latest()?.text, !text.isEmpty else { return }
        textDocumentProxy.insertText(text)
    }

    /// Insert the transcript and hit return — in most chat apps the return
    /// key sends, so one tap goes from clipboard to sent message.
    @objc private func insertLatestTranscriptAndReturn() {
        refresh()
        guard textDocumentProxy.isSecureTextEntry != true,
              let text = TranscriptStore.latest()?.text, !text.isEmpty else { return }
        textDocumentProxy.insertText(text)
        textDocumentProxy.insertText("\n")
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
            if snapshot.isFinal {
                completedSessionID = snapshot.sessionID
            }
            return
        }

        applyIncrementalDiff(from: lastInsertedText, to: nextText)
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
