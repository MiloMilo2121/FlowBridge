import AVFoundation
import Foundation

enum AudioFileDurationReader {
    static func duration(of url: URL) -> TimeInterval? {
        let asset = AVURLAsset(url: url)
        return CMTimeGetSeconds(asset.duration).isFinite ? CMTimeGetSeconds(asset.duration) : nil
    }
}

