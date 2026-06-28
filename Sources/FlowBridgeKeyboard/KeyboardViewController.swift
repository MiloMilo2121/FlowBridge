import FlowBridgeShared
import UIKit

final class KeyboardViewController: UIInputViewController {
    private let previewLabel = UILabel()
    private let insertButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        NetworkGuard.install()
        buildInterface()
        refresh()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refresh()
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

        let deleteButton = UIButton(type: .system)
        deleteButton.setImage(UIImage(systemName: "delete.left"), for: .normal)
        deleteButton.addTarget(self, action: #selector(deleteBackward), for: .touchUpInside)

        let nextKeyboardButton = UIButton(type: .system)
        nextKeyboardButton.setImage(UIImage(systemName: "globe"), for: .normal)
        nextKeyboardButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)

        let buttonRow = UIStackView(arrangedSubviews: [nextKeyboardButton, insertButton, deleteButton])
        buttonRow.axis = .horizontal
        buttonRow.alignment = .fill
        buttonRow.distribution = .fill
        buttonRow.spacing = 10

        nextKeyboardButton.widthAnchor.constraint(equalToConstant: 54).isActive = true
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
        previewLabel.text = record?.text
        insertButton.isEnabled = record?.text.isEmpty == false
    }

    @objc private func insertLatestTranscript() {
        refresh()
        guard let text = TranscriptStore.latest()?.text, !text.isEmpty else { return }
        textDocumentProxy.insertText(text)
    }

    @objc private func deleteBackward() {
        textDocumentProxy.deleteBackward()
    }
}

