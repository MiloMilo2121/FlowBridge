import Accelerate
import Foundation

/// Real-time microphone level shared by the Dynamic Island waveform and the
/// in-app Living Voice Field. Written from the audio tap thread (AppleSpeechEngine) or a
/// polling task (WhisperEngine); read from the main actor. An NSLock beats
/// an actor hop on the realtime path.
final class AudioLevelMeter: @unchecked Sendable {
    static let shared = AudioLevelMeter()

    /// One slot per ingest (~80–100ms of audio): 24 slots ≈ the last 2s.
    static let barCount = 24

    private let lock = NSLock()
    private var ring = [Float](repeating: 0, count: AudioLevelMeter.barCount)
    private var head = 0
    private var smoothed: Float = 0

    /// Latest smoothed level in 0…1, read per-frame by the Voice Field.
    var latestLevel: Float {
        lock.lock()
        defer { lock.unlock() }
        return smoothed
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        ring = [Float](repeating: 0, count: Self.barCount)
        head = 0
        smoothed = 0
    }

    /// Feed one linear RMS value straight from the audio buffer.
    func ingest(rms: Float) {
        let level = Self.normalize(rms: rms)
        lock.lock()
        defer { lock.unlock() }
        // Attack fast, release slow: bars snap up on plosives, fall gracefully.
        smoothed = level >= smoothed ? level : max(level, smoothed * 0.82)
        ring[head] = smoothed
        head = (head + 1) % Self.barCount
    }

    func ingest(samples: UnsafePointer<Float>, count: Int) {
        guard count > 0 else { return }
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(count))
        ingest(rms: rms)
    }

    func ingest(samples: [Float]) {
        samples.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            ingest(samples: base, count: buffer.count)
        }
    }

    /// Levels oldest→newest, quantized 0…100 for the Live Activity payload.
    func barSnapshot() -> [UInt8] {
        lock.lock()
        defer { lock.unlock() }
        var bars = [UInt8]()
        bars.reserveCapacity(Self.barCount)
        for offset in 0..<Self.barCount {
            let value = ring[(head + offset) % Self.barCount]
            bars.append(UInt8((min(max(value, 0), 1) * 100).rounded()))
        }
        return bars
    }

    /// Linear RMS → perceptual 0…1: dBFS clamped to the speech window
    /// [-50, -8], with a gamma lift so quiet speech stays visible.
    private static func normalize(rms: Float) -> Float {
        let db = 20 * log10(max(rms, 1e-6))
        let clamped = min(max((db + 50) / 42, 0), 1)
        return pow(clamped, 0.8)
    }
}
