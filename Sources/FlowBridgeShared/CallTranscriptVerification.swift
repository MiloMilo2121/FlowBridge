import Foundation

/// Whether the call transcript the iPhone shows is the one the Mac exported.
///
/// The Mac writes the SHA-256 of the transcript bytes into the call entry
/// (`sha256`, lowercase hex) when it makes the iCloud copy. iCloud can keep
/// only one of two copies written with the same name by two devices, and a
/// copy in the container can be edited: the hash is what lets a reader tell.
/// Hashing itself happens in the app (CryptoKit is not on Linux); the decision
/// lives here so it is checked on every platform.
public enum CallTranscriptVerification: Equatable, Sendable {
    /// The copy matches the hash the Mac recorded.
    case verified
    /// The entry predates the hash (written before 2026-10-03): it cannot be checked.
    case unverifiable
    /// The copy is not the transcript the Mac exported. Do not cite it.
    case mismatch

    public static func check(expected: String?, actualSHA256 actual: String) -> Self {
        guard let expected else { return .unverifiable }
        // A malformed hash is not "unverifiable": someone wrote something
        // that is not what the Mac writes.
        guard expected.count == 64, expected.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else { return .mismatch }
        return expected == actual.lowercased() ? .verified : .mismatch
    }
}
