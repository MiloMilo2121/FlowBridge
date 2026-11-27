import AVFoundation
import FlowBridgeShared

/// Encodes mono float samples to AAC-LC and returns ADTS frames ready to be
/// appended to the recording. An actor so the periodic flush and the final
/// drain at stop never run the converter at the same time.
actor AACEncoder {
    private static let samplesPerFrame: AVAudioFrameCount = 1024

    private let sampleRate: Double
    private let inputFormat: AVAudioFormat
    private let outputFormat: AVAudioFormat
    private let converter: AVAudioConverter

    init(sampleRate: Double) throws {
        guard ADTS.header(payloadLength: 0, sampleRate: sampleRate, channels: 1) != nil,
              let input = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false
              ) else {
            throw FlowBridgeError.recorderFailed("Unsupported microphone sample rate \(Int(sampleRate)) Hz.")
        }
        var description = AudioStreamBasicDescription(
            mSampleRate: sampleRate, mFormatID: kAudioFormatMPEG4AAC, mFormatFlags: 0,
            mBytesPerPacket: 0, mFramesPerPacket: Self.samplesPerFrame, mBytesPerFrame: 0,
            mChannelsPerFrame: 1, mBitsPerChannel: 0, mReserved: 0
        )
        guard let output = AVAudioFormat(streamDescription: &description),
              let converter = AVAudioConverter(from: input, to: output) else {
            throw FlowBridgeError.recorderFailed("AAC encoder unavailable.")
        }
        converter.bitRate = Int(FlowBridgeConstants.recordingBitRate)
        self.sampleRate = sampleRate
        self.inputFormat = input
        self.outputFormat = output
        self.converter = converter
    }

    /// Encodes `samples`; with `endOfStream` it also flushes the frames the
    /// encoder still holds, so the last words are not lost at stop.
    func encode(_ samples: [Float], endOfStream: Bool = false) -> Data {
        var pending = makeBuffer(samples)
        var frames = Data()
        while true {
            let packets = AVAudioCompressedBuffer(
                format: outputFormat,
                packetCapacity: 16,
                maximumPacketSize: max(converter.maximumOutputPacketSize, 1)
            )
            var error: NSError?
            let status = converter.convert(to: packets, error: &error) { _, inputStatus in
                if let buffer = pending {
                    pending = nil
                    inputStatus.pointee = .haveData
                    return buffer
                }
                inputStatus.pointee = endOfStream ? .endOfStream : .noDataNow
                return nil
            }
            frames.append(adtsFrames(from: packets))
            guard status == .haveData else { break }
        }
        return frames
    }

    private func makeBuffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?.pointee else { return nil }
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        return buffer
    }

    private func adtsFrames(from packets: AVAudioCompressedBuffer) -> Data {
        guard let descriptions = packets.packetDescriptions else { return Data() }
        var data = Data()
        for index in 0..<Int(packets.packetCount) {
            let packet = descriptions[index]
            let length = Int(packet.mDataByteSize)
            guard let header = ADTS.header(payloadLength: length, sampleRate: sampleRate, channels: 1) else {
                continue
            }
            data.append(header)
            data.append(packets.data.advanced(by: Int(packet.mStartOffset)).assumingMemoryBound(to: UInt8.self),
                        count: length)
        }
        return data
    }
}
