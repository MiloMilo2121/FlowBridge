import FlowBridgeShared
import Foundation

enum WhisperModelVariant: Sendable {
    /// Whisper Small bundled with the app (V1 behavior).
    case bundled
    /// Optional higher-accuracy model (e.g. large-v3-turbo compressed)
    /// installed under Application Support. Never downloaded at runtime —
    /// the offline posture stays intact; the folder is populated at build
    /// time or sideloaded deliberately (Finder/Files app).
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

/// Circuit breaker for optional model artifacts. The installed 626 MB
/// large-v3-turbo package was tested on physical hardware across GPU, CPU,
/// Neural Engine, and split encoder/decoder profiles. GPU reached the iOS
/// per-process memory limit; every non-GPU profile decoded only special
/// tokens. Keep the artifact installed, but never execute it until a
/// replacement package passes the same fixture on a real device.
enum PrecisionRuntimePolicy {
    static let installedArtifactValidated = false

    static var isQuarantined: Bool {
        WhisperModelLocator.precisionFolderIfInstalled() != nil && !installedArtifactValidated
    }
}
