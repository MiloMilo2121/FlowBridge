import FlowBridgeShared
import Foundation
import MetricKit

/// Privacy-first crash/hang insight: MetricKit delivers on-device diagnostic
/// payloads (crashes, hangs — including Jetsam terminations of the keyboard
/// extension) at most once per day. We store them as local JSON files and
/// NEVER upload anything: the user reviews and shares a report explicitly
/// from Settings (mail/share sheet) or deletes it. This is the only crash
/// signal compatible with "no telemetry, ever".
///
/// NOTE: MetricKit only produces payloads for users who share diagnostics
/// with developers in the system settings; expect partial coverage.
final class DiagnosticsCollector: NSObject, MXMetricManagerSubscriber {
    static let shared = DiagnosticsCollector()

    private var isStarted = false

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: FlowBridgeConstants.diagnosticsEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: FlowBridgeConstants.diagnosticsEnabledKey) }
    }

    func startIfEnabled() {
        guard Self.isEnabled, !isStarted else { return }
        isStarted = true
        MXMetricManager.shared.add(self)
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        MXMetricManager.shared.remove(self)
    }

    // MARK: - MXMetricManagerSubscriber

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            store(payload.jsonRepresentation(), prefix: "diagnostic")
        }
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        // Performance metrics are noise for our purpose; only diagnostics
        // (crashes/hangs) are kept.
    }

    // MARK: - Local storage

    static func reportsDirectory() -> URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let url = support.appendingPathComponent("Diagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func reports() -> [URL] {
        guard let directory = reportsDirectory(),
              let urls = try? FileManager.default.contentsOfDirectory(
                  at: directory,
                  includingPropertiesForKeys: [.creationDateKey],
                  options: [.skipsHiddenFiles]
              ) else {
            return []
        }
        return urls.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    static func deleteAllReports() {
        for url in reports() {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func store(_ data: Data, prefix: String) {
        guard let directory = Self.reportsDirectory() else { return }
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let url = directory.appendingPathComponent("\(prefix)-\(stamp).json")
        try? data.write(to: url, options: .atomic)
    }
}
