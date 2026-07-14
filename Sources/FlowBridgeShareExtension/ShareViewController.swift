import FlowBridgeShared
import UniformTypeIdentifiers
import UIKit

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        NetworkGuard.install()

        view.backgroundColor = .systemBackground
        Task { await importSharedItem() }
    }

    private func importSharedItem() async {
        do {
            guard let sourceURL = try await firstSharedAudioURL() else {
                throw FlowBridgeError.unsupportedShareItem
            }

            _ = try QueuedAudioStore.copyIntoInbox(sourceURL: sourceURL)
            try PendingCommandStore().write(.transcribeQueuedAudio)

            await MainActor.run {
                let url = URL(string: "flowbridge://transcribeQueuedAudio")!
                extensionContext?.open(url) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.extensionContext?.completeRequest(returningItems: nil)
                    }
                }
            }
        } catch {
            await MainActor.run {
                extensionContext?.cancelRequest(withError: error)
            }
        }
    }

    private func firstSharedAudioURL() async throws -> URL? {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            return nil
        }

        let typeIdentifiers = [
            UTType.audio.identifier,
            UTType.movie.identifier,
            UTType.mpeg4Audio.identifier,
            UTType.wav.identifier,
            UTType.aiff.identifier
        ]

        for item in items {
            guard let providers = item.attachments else { continue }

            for provider in providers {
                for identifier in typeIdentifiers where provider.hasItemConformingToTypeIdentifier(identifier) {
                    if let url = try await provider.copyFlowBridgeFileRepresentation(for: identifier) {
                        return url
                    }
                }
            }
        }

        return nil
    }
}

private extension NSItemProvider {
    func copyFlowBridgeFileRepresentation(for typeIdentifier: String) async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }

                do {
                    let fileExtension = url.pathExtension.isEmpty ? "caf" : url.pathExtension
                    let destination = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(fileExtension)

                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.copyItem(at: url, to: destination)
                    continuation.resume(returning: destination)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
