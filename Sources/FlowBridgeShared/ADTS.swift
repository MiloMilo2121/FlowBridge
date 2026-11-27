import Foundation

/// The 7-byte ADTS header that makes each AAC-LC frame readable on its own,
/// so a recording cut short by a crash stays valid up to its last frame.
public enum ADTS {
    public static let headerLength = 7
    /// MPEG-4 sampling frequency index table (ISO/IEC 14496-3).
    private static let sampleRates: [Double] = [
        96_000, 88_200, 64_000, 48_000, 44_100, 32_000, 24_000, 22_050, 16_000, 12_000, 11_025, 8_000
    ]

    /// Header for one AAC-LC frame of `payloadLength` bytes, or nil when the
    /// sample rate has no ADTS index or the frame is too long for the 13-bit field.
    public static func header(payloadLength: Int, sampleRate: Double, channels: Int) -> Data? {
        guard let rateIndex = sampleRates.firstIndex(of: sampleRate), (1...7).contains(channels) else {
            return nil
        }
        let frameLength = headerLength + payloadLength
        guard frameLength < 1 << 13 else { return nil }
        let profile = 1 // AAC LC, stored as object type minus one
        return Data([
            0xFF,
            0xF1, // MPEG-4, no CRC
            UInt8(profile << 6 | rateIndex << 2 | channels >> 2),
            UInt8((channels & 3) << 6 | frameLength >> 11),
            UInt8((frameLength >> 3) & 0xFF),
            UInt8((frameLength & 7) << 5 | 0x1F),
            0xFC
        ])
    }
}
