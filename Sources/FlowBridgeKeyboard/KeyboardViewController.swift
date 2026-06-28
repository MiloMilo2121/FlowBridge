import FlowBridgeShared
import UIKit

final class KeyboardViewController: UIInputViewController {
    private let previewLabel = UILabel()
    private let insertButton = UIButton(type: .system)
    private let liveButton = UIButton(type: .system)
    private var liveTimer: Timer?
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
        startLivePolling()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        liveTimer?.invalidate()
        liveTimer = nil
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

        liveButton.setImage(UIImage(systemName: "waveform.circle.fill"), for: .normal)
        liveButton.addTarget(self, action: #selector(toggleLiveMode), for: .touchUpInside)

        let deleteButton = UIButton(type: .system)
        deleteButton.setImage(UIImage(systemName: "delete.left"), for: .normal)
        deleteButton.addTarget(self, action: #selector(deleteBackward), for: .touchUpInside)

        let nextKeyboardButton = UIButton(type: .system)
        nextKeyboardButton.setImage(UIImage(systemName: "globe"), for: .normal)
        nextKeyboardButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)

        let buttonRow = UIStackView(arrangedSubviews: [nextKeyboardButton, liveButton, insertButton, deleteButton])
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

    private func refresh() {
        let record = TranscriptStore.latest()
        let live = LiveTranscriptStore.latest()
        previewLabel.text = live?.previewText.isEmpty == false ? live?.previewText : record?.text
        insertButton.isEnabled = record?.text.isEmpty == false
        liveButton.tintColor = liveModeEnabled ? .systemBlue : .secondaryLabel
    }

    @objc private func insertLatestTranscript() {
        refresh()
        guard let text = TranscriptStore.latest()?.text, !text.isEmpty else { return }
        textDocumentProxy.insertText(text)
    }

    @objc private func toggleLiveMode() {
        liveModeEnabled.toggle()
        refresh()
    }

    @objc private func deleteBackward() {
        textDocumentProxy.deleteBackward()
    }

    private func startLivePolling() {
        liveTimer?.invalidate()
        liveTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.applyLiveSnapshotIfNeeded()
        }
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
            if snapshot.isFinal {
                completedSessionID = snapshot.sessionID
            }
            return
        }

        for _ in lastInsertedText {
            textDocumentProxy.deleteBackward()
        }

        if !nextText.isEmpty {
            textDocumentProxy.insertText(nextText)
        }

        lastInsertedText = nextText

        if snapshot.isFinal {
            completedSessionID = snapshot.sessionID
        }
    }
}
