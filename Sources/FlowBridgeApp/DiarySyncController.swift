import CryptoKit
import FlowBridgeShared
import Foundation

/// Local-first mirror of the shared, immutable diary. iCloud transfer is
/// eventual; an unavailable account never prevents a dictation from saving.
/// The mirror rules live in `SpecchioDiario` (FlowBridgeShared), where they
/// are checked on synthetic data; this actor only finds the container, runs a
/// pass and keeps the status.
actor DiarySyncController {
    static let containerID = "iCloud.com.marcomilanello.flowbridge"
    private static let migrationDoneKey = "diaryHistoryMigrated"

    private let localRoot: URL
    private let local: Diario
    /// Kept apart from the mirror's issues: a failed migration must stay
    /// visible until a later launch retries it.
    private var migrationIssues: [String] = []
    private var status = "Diary saved here · waiting for iCloud Drive"

    init() throws {
        localRoot = try SharedContainer.containerURL()
            .appendingPathComponent("FlowBridgeDiary", isDirectory: true)
        local = Diario(cartella: localRoot.appendingPathComponent("diario"), dispositivo: "iphone")
        try FileManager.default.createDirectory(at: local.cartella, withIntermediateDirectories: true)
    }

    /// Copies the legacy `TranscriptHistoryStore` into the diary.
    ///
    /// Bails out entirely once it has completed, so a mature install does not
    /// replay one exclusive write (temp file + failed `renamex_np`) per
    /// retained record on every launch. `voci()` is cheap enough to use as the
    /// "already migrated" test; `scrivi` remains the real gate, so records
    /// that arrive later still land through the normal path. Any failed write
    /// leaves the flag unset, so the next launch retries just those records.
    func migrate(_ history: [TranscriptHistoryStore.Entry]) {
        let migrated = UserDefaults.standard.bool(forKey: Self.migrationDoneKey)
        guard !migrated else { return }
        migrationIssues = []
        let known = Set(local.voci().map(\.id))
        for entry in history where !known.contains(entry.record.id) {
            let record = entry.record
            let voice = VoceDiario(
                id: record.id, quando: record.createdAt, dispositivo: "iphone", tipo: .dettatura,
                testo: record.text, testoGrezzo: record.rawText,
                pulizia: record.rawText == nil ? .nessuna : .modello,
                motore: nil, versioneOS: ProcessInfo.processInfo.operatingSystemVersionString,
                lingua: record.language, durataS: record.audioDuration)
            do { try local.scrivi(voice) }
            catch Diario.Errore.esisteGia(_) { /* The migration is idempotent. */ }
            catch { migrationIssues.append("Migration: \(error.localizedDescription)") }
        }
        if migrationIssues.isEmpty {
            UserDefaults.standard.set(true, forKey: Self.migrationDoneKey)
        }
    }

    func add(_ record: TranscriptRecord, engine: String, polished: Bool) throws {
        let voice = VoceDiario(
            id: record.id, quando: record.createdAt, dispositivo: "iphone", tipo: .dettatura,
            testo: record.text, testoGrezzo: record.rawText,
            pulizia: polished ? .modello : .nessuna, motore: engine,
            versioneOS: ProcessInfo.processInfo.operatingSystemVersionString,
            lingua: record.language, durataS: record.audioDuration)
        try local.scrivi(voice)
    }

    func entries() -> [VoceDiario] { local.voci() }

    /// A call transcript and whether it is the copy the Mac exported.
    struct CallText: Sendable {
        let text: String
        let verification: CallTranscriptVerification
    }

    func callText(_ entry: VoceDiario) -> CallText? {
        guard entry.tipo == .call, let relative = entry.trascrizione,
              // A ".." component, not the substring: "Prices..._2026-07-27.txt" is a valid name.
              relative.hasPrefix("testi/"), !relative.split(separator: "/").contains("..") else { return nil }
        guard let data = try? Data(contentsOf: localRoot.appendingPathComponent(relative)),
              let text = String(data: data, encoding: .utf8) else { return nil }
        // The hash covers the exact bytes the Mac copied: check them before showing the text.
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return CallText(text: text,
                        verification: CallTranscriptVerification.check(expected: entry.sha256, actualSHA256: actual))
    }

    func delete(_ id: UUID) throws { try local.cancella(id) }

    func statusText() -> String {
        // The first line is the summary; SpecchioDiario lists every issue below it.
        let summary = status.split(separator: "\n").first.map(String.init) ?? status
        if let first = migrationIssues.first { return "Diary needs attention · \(first)" }
        return summary
    }

    /// One mirror pass. `url(forUbiquityContainerIdentifier:)` can block for a
    /// long time and the pass does coordinated reads and writes: none of it
    /// runs on Swift's cooperative pool (a detached Task would still be on it).
    func sync() async {
        let root = localRoot
        let result: SpecchioDiario.Esito? = await withCheckedContinuation { reply in
            DispatchQueue.global(qos: .utility).async {
                guard let container = FileManager.default
                    .url(forUbiquityContainerIdentifier: DiarySyncController.containerID) else {
                    reply.resume(returning: nil); return
                }
                reply.resume(returning: SpecchioDiario(
                    localRoot: root, cloudRoot: SpecchioDiario.cloudRoot(inContainer: container)).sincronizza())
            }
        }
        status = SpecchioDiario.statusText(result, at: Date())
    }
}

