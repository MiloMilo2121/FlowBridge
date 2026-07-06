import FlowBridgeShared
import Foundation

enum WhisperModelVariant: Sendable {
    /// Whisper Small bundled with the app (V1 behavior).
    case bundled
    /// Optional higher-accuracy model (large-v3-turbo compressed, ~626MB —
    /// staged by scripts/fetch-whisper-precision.sh). Never downloaded at
    /// runtime — the offline posture stays intact. Looked up first in the
    /// app bundle (build-time staging), then in Application Support
    /// (deliberate sideload).
    case precision
}

enum WhisperModelLocator {
    private static let requiredModels = ["MelSpectrogram", "AudioEncoder", "TextDecoder"]

    static func folder(for variant: WhisperModelVariant) throws -> URL {
        switch variant {
        case .bundled:
            return try bundledFolder()
        case .precision:
            guard let url = precisionFolderIfInstalled() else {
                throw FlowBridgeError.modelMissing(FlowBridgeConstants.precisionModelFolderName)
            }
            return url
        }
    }

    static func precisionFolderIfInstalled() -> URL? {
        // Build-time bundling wins (fetch-whisper-precision.sh stages into
        // Resources/WhisperModels/PrecisionModel, which ships inside the
        // WhisperModels folder resource)…
        if let bundled = Bundle.main.url(
            forResource: FlowBridgeConstants.precisionModelFolderName,
            withExtension: nil,
            subdirectory: FlowBridgeConstants.modelResourceSubdirectory
        ), isValidModelFolder(bundled) {
            return bundled
        }

        // …with deliberate sideload into Application Support as the fallback.
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let url = support.appendingPathComponent(FlowBridgeConstants.precisionModelFolderName, isDirectory: true)
        return isValidModelFolder(url) ? url : nil
    }

    private static func bundledFolder() throws -> URL {
        guard let url = Bundle.main.url(
            forResource: FlowBridgeConstants.modelFolderName,
            withExtension: nil,
            subdirectory: FlowBridgeConstants.modelResourceSubdirectory
        ) else {
            throw FlowBridgeError.modelMissing(
                "\(FlowBridgeConstants.modelResourceSubdirectory)/\(FlowBridgeConstants.modelFolderName)"
            )
        }
        guard isValidModelFolder(url) else {
            throw FlowBridgeError.modelMissing(url.path)
        }
        return url
    }

    private static func isValidModelFolder(_ url: URL) -> Bool {
        for file in requiredModels {
            let compiled = url.appendingPathComponent(file).appendingPathExtension("mlmodelc")
            let package = url.appendingPathComponent(file).appendingPathExtension("mlpackage")
            if !FileManager.default.fileExists(atPath: compiled.path),
               !FileManager.default.fileExists(atPath: package.path) {
                return false
            }
        }
        return FileManager.default.fileExists(atPath: url.appendingPathComponent("tokenizer.json").path)
    }
}
