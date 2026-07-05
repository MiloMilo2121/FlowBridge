import AVFoundation
import Foundation

enum AudioFileDurationReader {
    /// Async duration load. The synchronous `AVAsset.duration` accessor is
    /// deprecated since iOS 16 and can return an indefinite value on iOS 26;
    /// `load(.duration)` is the supported path.
    static func duration(of url: URL) async -> TimeInterval? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return nil }
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite && seconds >= 0 ? seconds : nil
    }
}
