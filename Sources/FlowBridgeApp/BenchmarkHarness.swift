import FlowBridgeShared
import Foundation

/// Local engine benchmark: runs bundled (audio, reference transcript) pairs
/// through a `TranscriptionEngine` and reports WER and latency per case.
///
/// Cases live in `Resources/Benchmark`: every audio file (`wav`, `m4a`, `mp3`,
/// `caf`) is paired with a same-named `.txt` holding the reference transcript.
/// The folder ships empty by default; it exists so engine choices (Whisper
/// Small vs future engines) are decided on our own Italian recordings instead
/// of third-party benchmarks.
enum BenchmarkHarness {
    struct Case: Sendable {
        let name: String
        let audioURL: URL
        let referenceText: String
    }

    struct CaseResult: Sendable {
        let name: String
        let wer: WERCalculator.Result
        let latency: TimeInterval
        let audioDuration: TimeInterval
        let transcript: String
        let failure: String?

        /// Processing speed relative to audio length; below 1 is faster than
        /// real time.
        var realTimeFactor: Double? {
            guard audioDuration > 0 else { return nil }
            return latency / audioDuration
        }
    }

    struct Report: Sendable {
        let results: [CaseResult]

        var aggregateErrorRate: Double {
            let succeeded = results.filter { $0.failure == nil }
            let totalReferenceWords = succeeded.reduce(0) { $0 + $1.wer.referenceWordCount }
            guard totalReferenceWords > 0 else { return 0 }
            let totalErrors = succeeded.reduce(0) { $0 + $1.wer.errorCount }
            return Double(totalErrors) / Double(totalReferenceWords)
        }

        var markdown: String {
            var lines = [
                "| Case | WER | Latency | Audio | RTF | Note |",
                "|---|---|---|---|---|---|"
            ]
            for result in results {
                let wer = String(format: "%.1f%%", result.wer.errorRate * 100)
                let latency = String(format: "%.2fs", result.latency)
                let audio = String(format: "%.1fs", result.audioDuration)
                let rtf = result.realTimeFactor.map { String(format: "%.2f", $0) } ?? "–"
                let note = result.failure ?? ""
                lines.append("| \(result.name) | \(wer) | \(latency) | \(audio) | \(rtf) | \(note) |")
            }
            lines.append("")
            lines.append(String(format: "Aggregate WER: %.1f%%", aggregateErrorRate * 100))
            return lines.joined(separator: "\n")
        }
    }

    private static let audioExtensions: Set<String> = ["wav", "m4a", "mp3", "caf"]

    static func bundledCases(bundle: Bundle = .main) -> [Case] {
        guard let urls = bundle.urls(forResourcesWithExtension: nil, subdirectory: "Benchmark") else {
            return []
        }

        return urls
            .filter { audioExtensions.contains($0.pathExtension.lowercased()) }
            .compactMap { audioURL in
                let referenceURL = audioURL.deletingPathExtension().appendingPathExtension("txt")
                guard let reference = try? String(contentsOf: referenceURL, encoding: .utf8) else {
                    return nil
                }
                return Case(
                    name: audioURL.deletingPathExtension().lastPathComponent,
                    audioURL: audioURL,
                    referenceText: reference.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .sorted { $0.name < $1.name }
    }

    static func run(cases: [Case], engine: any TranscriptionEngine) async -> Report {
        var results: [CaseResult] = []
        let clock = ContinuousClock()

        for benchmarkCase in cases {
            let duration = AudioFileDurationReader.duration(of: benchmarkCase.audioURL) ?? 0
            let recording = RecordedAudio(url: benchmarkCase.audioURL, duration: duration)

            let start = clock.now
            do {
                let record = try await engine.transcribe(recording: recording, source: .sharedAudio)
                let latency = secondsSince(start, clock: clock)
                results.append(
                    CaseResult(
                        name: benchmarkCase.name,
                        wer: WERCalculator.evaluate(reference: benchmarkCase.referenceText, hypothesis: record.text),
                        latency: latency,
                        audioDuration: duration,
                        transcript: record.text,
                        failure: nil
                    )
                )
            } catch {
                let latency = secondsSince(start, clock: clock)
                results.append(
                    CaseResult(
                        name: benchmarkCase.name,
                        wer: WERCalculator.evaluate(reference: benchmarkCase.referenceText, hypothesis: ""),
                        latency: latency,
                        audioDuration: duration,
                        transcript: "",
                        failure: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    )
                )
            }
        }

        return Report(results: results)
    }

    private static func secondsSince(_ start: ContinuousClock.Instant, clock: ContinuousClock) -> TimeInterval {
        let elapsed = clock.now - start
        let (seconds, attoseconds) = elapsed.components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
