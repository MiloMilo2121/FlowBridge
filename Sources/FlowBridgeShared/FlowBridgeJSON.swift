import Foundation

/// The one JSON coder configuration used by every store: `deferredToDate`,
/// so timestamps round-trip bit-exactly across the app-group boundary. This
/// replaces five copy-pasted encoder/decoder setups (two of which had
/// drifted into differently-named twins).
public enum FlowBridgeJSON {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return decoder
    }
}
