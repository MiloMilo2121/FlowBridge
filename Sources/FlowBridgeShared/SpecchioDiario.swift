import Foundation

/// The iPhone side of the diary mirror in iCloud Drive: diary entries both
/// ways, call transcripts **down only** (the Mac is their only source).
///
/// It ports the Mac's `Specchio` (trascrittore-auto,
/// `app/Sources/Condivisione/Specchio.swift`) rule for rule; the rules are in
/// `Docs/CONTRATTO-DIARIO.md`, «Lo specchio su iCloud». Both sides must
/// follow them: one side that re-uploads what the other deleted is enough to
/// put a deleted dictation back on Apple's servers on every sync.
///
/// - Only contract names move: `<lowercase uuid>.json` and
///   `<lowercase uuid>.cancellata.json`. iCloud conflict copies
///   (`<id> 2.json`), subfolders and anything else are reported, never copied.
/// - A file is checked before it is taken: a JSON object whose `id` matches
///   its name and with an integer `schema`. The entry is not fully decoded, so
///   a future schema still passes.
/// - Every file is written once, all or nothing: temporary file in the same
///   folder, then an exclusive rename. Never `copyItem` onto the final name.
/// - Only downloaded iCloud files are read; an iCloud placeholder
///   (`.<name>.icloud`) counts as present and is waited for.
/// - A valid tombstone wins on both sides: the entry file is removed from the
///   local folder **and** from the container. An invalid tombstone deletes
///   nothing. Calls cannot be deleted: a tombstone on a call is set aside
///   (`.rifiutata`) so `Diario.voci()` does not hide the call.
/// - An entry this device has seen in the container and that vanished without
///   a tombstone is not uploaded again: it was deleted elsewhere and the
///   tombstone has not arrived yet (iCloud does not guarantee ordering).
/// - Same name, different bytes: a conflict, never an overwrite.
public final class SpecchioDiario: @unchecked Sendable {

    public struct Esito: Equatable, Sendable {
        public var copied = 0
        public var removed = 0
        public var waiting = 0
        public var issues: [String] = []
        public init() {}
    }

    public let localRoot: URL
    public let cloudRoot: URL
    let seenRegistry: URL
    /// iCloud holds several versions of this file and has not picked one
    /// (`ubiquitousItemHasUnresolvedConflicts`): it is not read as good, not
    /// copied, not deleted. Injectable for the checks, which run outside iCloud.
    let conflict: (URL) -> Bool
    private let fm = FileManager.default

    /// A diary entry is a dictation or a note: 1 MiB is already an anomaly.
    public static let entryLimit = 1 << 20
    /// The largest call transcript so far is a few hundred KB.
    public static let transcriptLimit = 16 << 20

    enum Failure: LocalizedError {
        case conflict(String), tooLarge(String, Int)
        var errorDescription: String? {
            switch self {
            case .conflict(let name): "iCloud version conflict on \(name), left untouched"
            case .tooLarge(let name, let bytes): "\(name) is \(bytes) bytes, over the limit: not read"
            }
        }
    }

    var localDiary: URL { localRoot.appendingPathComponent("diario", isDirectory: true) }
    var cloudDiary: URL { cloudRoot.appendingPathComponent("diario", isDirectory: true) }
    var localTexts: URL { localRoot.appendingPathComponent("testi", isDirectory: true) }
    var cloudTexts: URL { cloudRoot.appendingPathComponent("testi", isDirectory: true) }

    /// `localRoot` and `cloudRoot` both contain `diario/` and `testi/`.
    public init(localRoot: URL, cloudRoot: URL, seenRegistry: URL? = nil,
                conflict: ((URL) -> Bool)? = nil) {
        self.localRoot = localRoot
        self.cloudRoot = cloudRoot
        self.seenRegistry = seenRegistry ?? localRoot.appendingPathComponent("seen-in-icloud.json")
        self.conflict = conflict ?? { url in
            #if os(Linux)
            return false
            #else
            return (try? url.resourceValues(forKeys: [.ubiquitousItemHasUnresolvedConflictsKey]))?
                .ubiquitousItemHasUnresolvedConflicts == true
            #endif
        }
    }

    /// `container/Documents/FlowBridge`, where the Mac and the iPhone meet.
    public static func cloudRoot(inContainer container: URL) -> URL {
        container.appendingPathComponent("Documents/FlowBridge", isDirectory: true)
    }

    // MARK: - One pass

    public func sincronizza() -> Esito {
        var result = Esito()
        do {
            for folder in [localDiary, cloudDiary, localTexts, cloudTexts] {
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            }
        } catch {
            result.issues.append("Folders: \(error.localizedDescription)")
            return result
        }
        // A mirror folder that is a symbolic link would send writes (and the
        // deletions of tombstones) wherever it points. Stop and say so.
        for folder in [localRoot, localDiary, localTexts, cloudRoot, cloudDiary, cloudTexts] where isSymlink(folder) {
            result.issues.append("Mirror folder is a symbolic link, stopping: \(folder.path)")
            return result
        }
        propagateTombstones(&result)
        mirror(from: cloudDiary, to: localDiary, side: "iCloud", &result)
        let seen = readRegistry()
        mirror(from: localDiary, to: cloudDiary, side: "iPhone", seen: seen, &result)
        downloadTexts(&result)
        updateRegistry(seen)
        return result
    }

    /// First line: the summary the app shows. Below: every issue.
    public static func statusText(_ result: Esito?, at date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d/M HH:mm"
        let time = f.string(from: date)
        guard let result else { return "Diary saved here · iCloud Drive unavailable (\(time))" }
        let waiting = result.waiting > 0 ? " · \(result.waiting) waiting" : ""
        guard !result.issues.isEmpty else {
            // «Copied», not «synced»: iOS uploads when it has network, and
            // that is not visible from here.
            return "Diary copied to iCloud Drive (\(time))\(waiting) · iOS handles the upload"
        }
        let n = result.issues.count
        return (["Diary: \(n) \(n == 1 ? "issue" : "issues") (\(time))\(waiting) · \(result.issues[0])"]
                + result.issues.map { "- \($0)" }).joined(separator: "\n")
    }

    // MARK: - Names and validation

    static let tombstoneSuffix = ".cancellata.json"

    static func idFromName(_ name: String) -> (id: String, tombstone: Bool)? {
        let tombstone = name.hasSuffix(tombstoneSuffix)
        guard tombstone || name.hasSuffix(".json") else { return nil }
        let stem = String(name.dropLast(tombstone ? tombstoneSuffix.count : ".json".count))
        guard stem == stem.lowercased(), let uuid = UUID(uuidString: stem),
              uuid.uuidString.lowercased() == stem else { return nil }
        return (stem, tombstone)
    }

    static func invalidReason(_ data: Data, id: String) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "not a JSON object"
        }
        guard let field = object["id"] as? String, field.lowercased() == id else {
            return "id does not match the name"
        }
        guard let schema = object["schema"] as? Int, schema >= 1 else { return "missing schema" }
        return nil
    }

    func exists(_ folder: URL, _ name: String) -> Bool {
        fm.fileExists(atPath: folder.appendingPathComponent(name).path)
    }

    /// The file is there, downloaded or as an iCloud placeholder.
    func present(_ folder: URL, _ name: String) -> Bool {
        exists(folder, name) || exists(folder, ".\(name).icloud")
    }

    func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
    }

    func isRegularFile(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
        return values?.isSymbolicLink != true && values?.isRegularFile == true
    }

    /// Contract names in a folder. Placeholders are requested and waited for;
    /// other `.json` names and subfolders are reported once per pass (`report`).
    func list(_ folder: URL, side: String, report: Bool = true, _ result: inout Esito)
        -> [(name: String, id: String, tombstone: Bool)] {
        let names = ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
        var entries: [(String, String, Bool)] = []
        for name in names {
            if name.hasPrefix(".") {
                if report, name.hasSuffix(".icloud") {
                    let real = String(name.dropFirst().dropLast(".icloud".count))
                    if Self.idFromName(real) != nil {
                        requestDownload(folder.appendingPathComponent(real))
                        result.waiting += 1
                    }
                }
                continue
            }
            // A tombstone set aside on purpose stays as a trace, silently.
            if name.contains(Self.tombstoneSuffix + ".rifiutata") { continue }
            let url = folder.appendingPathComponent(name)
            if let (id, tombstone) = Self.idFromName(name), isRegularFile(url) {
                entries.append((name, id, tombstone))
            } else if report {
                result.issues.append("Unexpected file in the diary (\(side)): \(name)")
            }
        }
        return entries
    }

    // MARK: - Tombstones

    func propagateTombstones(_ result: inout Esito) {
        let sides = [(folder: localDiary, side: "iPhone"), (folder: cloudDiary, side: "iCloud")]
        var tombstones: [String: [(folder: URL, side: String)]] = [:]
        for s in sides {
            for e in list(s.folder, side: s.side, report: false, &result) where e.tombstone {
                tombstones[e.id, default: []].append(s)
            }
        }
        for (id, holders) in tombstones.sorted(by: { $0.key < $1.key }) {
            let name = id + Self.tombstoneSuffix
            var call = false
            var notDownloaded = false
            var inConflict = false
            for s in sides where exists(s.folder, "\(id).json") {
                let entry = s.folder.appendingPathComponent("\(id).json")
                if conflict(entry) { inConflict = true; continue }
                switch isCall(entry) {
                case .some(true): call = true
                case .none: notDownloaded = true
                case .some(false): break
                }
            }
            if call {
                for s in holders { setAside(s.folder.appendingPathComponent(name), &result) }
                result.issues.append("Tombstone on a call, set aside: \(id)")
                continue
            }
            if inConflict {
                result.issues.append("Deleted entry in an iCloud version conflict, not removed: \(id)")
                continue
            }
            if notDownloaded { result.waiting += 1; continue }

            var valid: URL?
            var invalidSides: Set<String> = []
            for s in holders {
                let url = s.folder.appendingPathComponent(name)
                let data: Data
                do {
                    guard let read = try readIfDownloaded(url, limit: Self.entryLimit) else { result.waiting += 1; continue }
                    data = read
                } catch {
                    result.issues.append("Tombstone (\(s.side)): \(error.localizedDescription)")
                    invalidSides.insert(s.side)
                    continue
                }
                if let reason = Self.invalidReason(data, id: id) {
                    result.issues.append("Invalid tombstone (\(s.side)): \(name) — \(reason)")
                    invalidSides.insert(s.side)
                } else if valid == nil {
                    valid = url
                }
            }
            guard let valid else { continue }
            for s in sides where !invalidSides.contains(s.side) {
                let tombstone = s.folder.appendingPathComponent(name)
                if !present(s.folder, name) {
                    switch copyOnce(from: valid, to: tombstone, id: id) {
                    case .copied: result.copied += 1
                    case .waiting: result.waiting += 1; continue
                    case .issue(let p): result.issues.append("Tombstone \(id) (\(s.side)): \(p)"); continue
                    case .same, .different: break
                    }
                } else if !fm.fileExists(atPath: tombstone.path) {
                    continue  // placeholder: the tombstone exists, the rest next pass
                }
                let entry = s.folder.appendingPathComponent("\(id).json")
                guard fm.fileExists(atPath: entry.path) else { continue }
                if conflict(entry) {
                    result.issues.append("Deleted entry in an iCloud version conflict, not removed: \(id)")
                    continue
                }
                do {
                    try remove(entry)
                    result.removed += 1
                } catch {
                    result.issues.append("Deleted entry still on \(s.side): \(id)")
                }
            }
        }
    }

    /// Whether an entry is a call, without decoding all of it; nil if not
    /// downloaded yet. A broken file is not a call: its tombstone applies.
    func isCall(_ url: URL) -> Bool? {
        guard let data = try? readIfDownloaded(url, limit: Self.entryLimit) else { return nil }
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (object?["tipo"] as? String) == "call"
    }

    /// Renames a tombstone out of the contract (`.rifiutata` does not end in
    /// `.json`), without overwriting anything.
    func setAside(_ tombstone: URL, _ result: inout Esito) {
        guard fm.fileExists(atPath: tombstone.path) else { return }
        var target = tombstone.appendingPathExtension("rifiutata")
        if fm.fileExists(atPath: target.path) {
            target = tombstone.appendingPathExtension("rifiutata-\(UUID().uuidString.prefix(8).lowercased())")
        }
        do { try moveExclusively(tombstone, to: target) }
        catch { result.issues.append("Tombstone on a call not moved: \(tombstone.lastPathComponent)") }
    }

    // MARK: - Entries

    func mirror(from source: URL, to destination: URL, side: String,
                seen: Set<String> = [], _ result: inout Esito) {
        for e in list(source, side: side, &result) where !e.tombstone {
            // A tombstone that arrived mid-pass wins, next pass. (Tombstones on
            // calls were already set aside by propagateTombstones.)
            let tombstoneName = e.id + Self.tombstoneSuffix
            if present(destination, tombstoneName) || present(source, tombstoneName) { continue }
            if !exists(destination, e.name), exists(destination, ".\(e.name).icloud") {
                result.waiting += 1
                continue
            }
            if seen.contains(e.id), !present(destination, e.name) {
                result.issues.append("Entry vanished from iCloud without a tombstone, not uploading it again: \(e.name)")
                continue
            }
            switch copyOnce(from: source.appendingPathComponent(e.name),
                            to: destination.appendingPathComponent(e.name), id: e.id) {
            case .copied: result.copied += 1
            case .same: break
            case .waiting: result.waiting += 1
            case .different: result.issues.append("Different content: \(e.name)")
            case .issue(let p): result.issues.append("Entry \(e.name) (\(side)): \(p)")
            }
        }
    }

    // MARK: - Call transcripts: down only

    /// The Mac writes `testi/<name>.txt` once; the iPhone only reads them.
    /// Uploading from here would turn a stale or tampered local copy into
    /// the one everyone sees.
    func downloadTexts(_ result: inout Esito) {
        let names = ((try? fm.contentsOfDirectory(atPath: cloudTexts.path)) ?? []).sorted()
        for name in names {
            if name.hasPrefix(".") {
                if name.hasSuffix(".txt.icloud") {
                    requestDownload(cloudTexts.appendingPathComponent(String(name.dropFirst().dropLast(".icloud".count))))
                    result.waiting += 1
                }
                continue
            }
            let source = cloudTexts.appendingPathComponent(name)
            guard name.hasSuffix(".txt"), !name.contains("/"), isRegularFile(source) else {
                result.issues.append("Unexpected file in the transcripts: \(name)")
                continue
            }
            let target = localTexts.appendingPathComponent(name)
            do {
                guard let data = try readIfDownloaded(source, limit: Self.transcriptLimit) else { result.waiting += 1; continue }
                switch try compare(data, with: target) {
                case .missing:
                    try writeOnce(data, to: target)
                    result.copied += 1
                case .same: break
                case .different: result.issues.append("Different transcript: \(name)")
                case .notDownloaded: result.waiting += 1
                }
            } catch {
                result.issues.append("Transcript \(name): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Seen registry

    func readRegistry() -> Set<String> {
        guard let data = try? Data(contentsOf: seenRegistry),
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(ids)
    }

    /// Adds the entries that are in the container now; never removes any.
    func updateRegistry(_ before: Set<String>) {
        let names = (try? fm.contentsOfDirectory(atPath: cloudDiary.path)) ?? []
        let now = names.compactMap { name -> String? in
            let real = name.hasPrefix(".") && name.hasSuffix(".icloud")
                ? String(name.dropFirst().dropLast(".icloud".count)) : name
            guard let (id, tombstone) = Self.idFromName(real), !tombstone else { return nil }
            return id
        }
        let all = before.union(now)
        guard all != before, let data = try? JSONEncoder().encode(all.sorted()) else { return }
        try? data.write(to: seenRegistry, options: .atomic)
    }

    // MARK: - Bytes

    enum Copy: Equatable { case copied, same, different, waiting, issue(String) }

    func copyOnce(from source: URL, to target: URL, id: String) -> Copy {
        do {
            guard let data = try readIfDownloaded(source, limit: Self.entryLimit) else { return .waiting }
            if let reason = Self.invalidReason(data, id: id) { return .issue(reason) }
            switch try compare(data, with: target) {
            case .same: return .same
            case .different: return .different
            case .notDownloaded: return .waiting
            case .missing:
                try writeOnce(data, to: target)
                return .copied
            }
        } catch {
            return .issue(error.localizedDescription)
        }
    }

    enum Comparison { case missing, same, different, notDownloaded }

    func compare(_ data: Data, with url: URL) throws -> Comparison {
        guard fm.fileExists(atPath: url.path) else {
            return exists(url.deletingLastPathComponent(), ".\(url.lastPathComponent).icloud")
                ? .notDownloaded : .missing
        }
        // Different size: different, without reading it (and without pulling
        // an arbitrary file into memory just to find out).
        if let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, bytes != data.count {
            if conflict(url) { throw Failure.conflict(url.lastPathComponent) }
            return .different
        }
        guard let existing = try readIfDownloaded(url) else { return .notDownloaded }
        return existing == data ? .same : .different
    }

    func requestDownload(_ url: URL) {
        #if !os(Linux)
        try? fm.startDownloadingUbiquitousItem(at: url)
        #endif
    }

    /// The bytes of a file, coordinated. An iCloud file that is not on disk yet
    /// is requested and nil is returned, instead of blocking on a coordinated
    /// read that waits for the network.
    func readIfDownloaded(_ url: URL, limit: Int? = nil) throws -> Data? {
        if conflict(url) { throw Failure.conflict(url.lastPathComponent) }
        if let limit, let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, bytes > limit {
            throw Failure.tooLarge(url.lastPathComponent, bytes)
        }
        #if os(Linux)
        return try Data(contentsOf: url)
        #else
        let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        if values?.isUbiquitousItem == true,
           let status = values?.ubiquitousItemDownloadingStatus, status != .current {
            requestDownload(url)
            return nil
        }
        var data = Data()
        var coordinationError: NSError?
        var innerError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [],
                                                         error: &coordinationError) { u in
            do { data = try Data(contentsOf: u) } catch { innerError = error }
        }
        if let innerError { throw innerError }
        if let coordinationError { throw coordinationError }
        return data
        #endif
    }

    /// Temporary file in the same folder, then an exclusive rename: the file
    /// is there whole or not at all, and an existing one is never replaced.
    /// The temporary file is removed even if the write stops halfway.
    func writeOnce(_ data: Data, to target: URL) throws {
        let temporary = target.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
        defer { try? fm.removeItem(at: temporary) }
        try data.write(to: temporary)
        try moveExclusively(temporary, to: target)
    }

    func moveExclusively(_ source: URL, to target: URL) throws {
        func posixError() -> NSError {
            NSError(domain: NSPOSIXErrorDomain, code: Int(errno),
                    userInfo: [NSLocalizedDescriptionKey: errno == EEXIST
                        ? "already exists, not overwritten" : String(cString: strerror(errno))])
        }
        #if os(Linux)
        // link() fails with EEXIST instead of replacing: exclusive and atomic.
        guard link(source.path, target.path) == 0 else { throw posixError() }
        unlink(source.path)
        #else
        try coordinated(target, options: []) { destination in
            if renamex_np(source.path, destination.path, UInt32(RENAME_EXCL)) != 0 { throw posixError() }
        }
        #endif
    }

    func remove(_ url: URL) throws {
        #if os(Linux)
        try fm.removeItem(at: url)
        #else
        try coordinated(url, options: .forDeleting) { try self.fm.removeItem(at: $0) }
        #endif
    }

    #if !os(Linux)
    func coordinated(_ url: URL, options: NSFileCoordinator.WritingOptions,
                     _ body: (URL) throws -> Void) throws {
        var coordinationError: NSError?
        var innerError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: options,
                                                         error: &coordinationError) { u in
            do { try body(u) } catch { innerError = error }
        }
        if let innerError { throw innerError }
        if let coordinationError { throw coordinationError }
    }
    #endif
}
