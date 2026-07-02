import Foundation

/// Target tone for the polished transcript.
///
/// Keyboard extensions cannot read the host app's identity through public
/// API, so per-app tone is inferred from the active text field's traits —
/// which is often a better signal anyway: a "send" return key means a chat
/// box whatever the app is. The keyboard writes a `ToneHint` on every
/// appearance; the polisher uses it while fresh, otherwise the user's
/// default tone.
public enum ToneProfile: String, Codable, CaseIterable, Sendable {
    /// Clean up only; keep the speaker's register.
    case neutral
    /// Chat: relaxed capitalization, no trailing period on the last sentence.
    case casual
    /// Email/documents: complete sentences and standard punctuation.
    case formal

    public var displayName: String {
        switch self {
        case .neutral: return "Neutral"
        case .casual: return "Casual"
        case .formal: return "Formal"
        }
    }
}

public struct ToneHint: Codable, Equatable, Sendable {
    public let profile: ToneProfile
    public let capturedAt: Date

    public init(profile: ToneProfile, capturedAt: Date = Date()) {
        self.profile = profile
        self.capturedAt = capturedAt
    }
}

public final class ToneContextStore: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults? = nil) throws {
        self.defaults = try defaults ?? SharedContainer.userDefaults()
    }

    /// Written by the keyboard from the active field's traits.
    public func writeHint(_ hint: ToneHint) {
        guard let data = try? JSONEncoder.iso.encode(hint) else { return }
        defaults.set(data, forKey: FlowBridgeConstants.toneHintKey)
    }

    /// The tone the polisher should target right now: a fresh keyboard hint
    /// wins, otherwise the user's configured default, otherwise neutral.
    public func currentTone(now: Date = Date()) -> ToneProfile {
        if let data = defaults.data(forKey: FlowBridgeConstants.toneHintKey),
           let hint = try? JSONDecoder.iso.decode(ToneHint.self, from: data),
           now.timeIntervalSince(hint.capturedAt) <= FlowBridgeConstants.toneHintMaxAgeSeconds {
            return hint.profile
        }
        return defaultTone()
    }

    public func defaultTone() -> ToneProfile {
        let raw = defaults.string(forKey: FlowBridgeConstants.defaultToneKey)
        return raw.flatMap(ToneProfile.init(rawValue:)) ?? .neutral
    }

    public func setDefaultTone(_ tone: ToneProfile) {
        defaults.set(tone.rawValue, forKey: FlowBridgeConstants.defaultToneKey)
    }
}

private extension JSONEncoder {
    static var iso: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        return encoder
    }
}

private extension JSONDecoder {
    static var iso: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return decoder
    }
}
