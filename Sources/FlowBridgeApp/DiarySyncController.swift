import FlowBridgeShared
import Foundation

/// Local-first mirror of the shared, immutable diary. iCloud transfer is
/// eventual; an unavailable account never prevents a dictation from saving.
actor DiarySyncController {
    static let containerID = "iCloud.com.marcomilanello.flowbridge"

    private let localRoot: URL
    private let local: Diario
    private var issues: [String] = []
    private var cloudAvailable = false

    init() throws {
        localRoot = try SharedContainer.containerURL()
            .appendingPathComponent("FlowBridgeDiary", isDirectory: true)
        local = Diario(cartella: localRoot.appendingPathComponent("diario"), dispositivo: "iphone")
        try FileManager.default.createDirectory(at: local.cartella, withIntermediateDirectories: true)
    }

    func migrate(_ history: [TranscriptHistoryStore.Entry]) {
        for entry in history {
            let record = entry.record
            let voice = VoceDiario(
                id: record.id, quando: record.createdAt, dispositivo: "iphone", tipo: .dettatura,
                testo: record.text, testoGrezzo: record.rawText,
                pulizia: record.rawText == nil ? .nessuna : .modello,
                motore: nil, versioneOS: ProcessInfo.processInfo.operatingSystemVersionString,
                lingua: record.language, durataS: record.audioDuration)
            do { try local.scrivi(voice) }
            catch Diario.Errore.esisteGia(_) { /* The migration is idempotent. */ }
            catch { issues.append("Migration: \(error.localizedDescription)") }
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

    func callText(_ entry: VoceDiario) -> String? {
        guard entry.tipo == .call, let relative = entry.trascrizione,
              relative.hasPrefix("testi/"), !relative.contains("..") else { return nil }
        return try? String(contentsOf: localRoot.appendingPathComponent(relative), encoding: .utf8)
    }

    func delete(_ id: UUID) throws { try local.cancella(id) }

    func statusText() -> String {
        if let first = issues.first { return "Diary needs attention · \(first)" }
        return cloudAvailable ? "Diary synced with iCloud Drive" : "Diary saved here · waiting for iCloud Drive"
    }

    func sync() {
        issues = []
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: Self.containerID) else {
            cloudAvailable = false
            return
        }
        let cloudRoot = container.appendingPathComponent("Documents/FlowBridge", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: cloudRoot, withIntermediateDirectories: true)
            for folder in ["diario", "testi"] {
                let localFolder = localRoot.appendingPathComponent(folder, isDirectory: true)
                let cloudFolder = cloudRoot.appendingPathComponent(folder, isDirectory: true)
                try FileManager.default.createDirectory(at: localFolder, withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: cloudFolder, withIntermediateDirectories: true)
                mirror(from: localFolder, to: cloudFolder)
                mirror(from: cloudFolder, to: localFolder)
            }
            cloudAvailable = true
        } catch {
            cloudAvailable = false
            issues.append("iCloud: \(error.localizedDescription)")
        }
    }

    private func mirror(from source: URL, to destination: URL) {
        guard let names = try? FileManager.default.contentsOfDirectory(
            at: source, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        for from in names {
            let name = from.lastPathComponent
            guard !name.hasPrefix("."), !from.isSymbolicLink else { continue }
            let to = destination.appendingPathComponent(name)
            if (try? from.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                do {
                    try FileManager.default.createDirectory(at: to, withIntermediateDirectories: true)
                    mirror(from: from, to: to)
                } catch { issues.append("Directory \(name): \(error.localizedDescription)") }
                continue
            }
            guard name.hasSuffix(".json") || name.hasSuffix(".txt") else { continue }
            if !FileManager.default.fileExists(atPath: to.path) {
                // iCloud may have a placeholder for a document not yet on disk.
                if source.path.contains("Mobile Documents") {
                    try? FileManager.default.startDownloadingUbiquitousItem(at: from)
                }
                do { try FileManager.default.copyItem(at: from, to: to) }
                catch { issues.append("Sync \(name): \(error.localizedDescription)") }
            } else if let a = try? Data(contentsOf: from),
                      let b = try? Data(contentsOf: to), a != b {
                let conflict = "Different content for \(name)"
                if !issues.contains(conflict) { issues.append(conflict) }
            }
        }
    }
}

private extension URL {
    var isSymbolicLink: Bool {
        (try? resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }
}
