import FlowBridgeShared
import Foundation

/// The iCloud diary mirror on temporary folders: a local iPhone folder and a
/// fake container that the Mac also writes to. Synthetic data only (this
/// repository is public).
private struct Bench {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("check-specchio-\(UUID().uuidString)")
    var local: URL { root.appendingPathComponent("local") }
    var cloud: URL { root.appendingPathComponent("cloud/Documents/FlowBridge") }
    var phone: Diario { Diario(cartella: local.appendingPathComponent("diario"), dispositivo: "iphone") }
    var mac: Diario { Diario(cartella: cloud.appendingPathComponent("diario"), dispositivo: "mac") }

    func sync() -> SpecchioDiario.Esito {
        SpecchioDiario(localRoot: local, cloudRoot: cloud).sincronizza()
    }

    func has(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    func names(_ folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }

    func allFiles() -> [URL] {
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        return e.compactMap { $0 as? URL }.filter { !$0.hasDirectoryPath }
    }

    func filesContaining(_ text: String) -> [URL] {
        allFiles().filter { (try? String(contentsOf: $0, encoding: .utf8))?.contains(text) == true }
    }

    func tombstoneName(_ id: UUID) -> String { "\(id.uuidString.lowercased()).cancellata.json" }
}

func runSpecchioChecks() throws {
    // The bounce: the Mac deletes, the iPhone must not upload the text again.
    do {
        let b = Bench()
        let v = VoceDiario(dispositivo: "iphone", tipo: .dettatura, testo: "deleted on the Mac 8812")
        try b.phone.scrivi(v)
        _ = b.sync()
        require(b.has(b.mac.file(v.id)), "The entry did not reach the container")
        try b.mac.cancella(v.id)                  // tombstone in iCloud, entry removed there
        _ = b.sync()
        _ = b.sync()
        require(!b.has(b.mac.file(v.id)), "The iPhone uploaded a deleted entry again")
        require(!b.has(b.phone.file(v.id)), "The deleted text is still on the iPhone")
        require(b.filesContaining("8812").isEmpty, "The deleted text survived in a file")
        require(b.phone.voci().isEmpty, "The deleted entry is visible")
    }

    // A deletion on the iPhone removes the text from the container too.
    do {
        let b = Bench()
        let v = VoceDiario(dispositivo: "iphone", tipo: .nota, testo: "deleted on the iPhone 3307")
        try b.phone.scrivi(v)
        _ = b.sync()
        try b.phone.cancella(v.id)
        let r = b.sync()
        require(r.removed == 1, "Expected one removal, got \(r)")
        require(b.names(b.mac.cartella) == [b.tombstoneName(v.id)], "Only the tombstone should remain in iCloud")
        require(b.filesContaining("3307").isEmpty, "The deleted text survived in a file")
    }

    // An invalid tombstone deletes nothing.
    do {
        let b = Bench()
        let v = VoceDiario(dispositivo: "iphone", tipo: .nota, testo: "stays")
        try b.phone.scrivi(v)
        _ = b.sync()
        try Diario.codificatore().encode(Lapide(id: UUID(), dispositivo: "mac"))
            .write(to: b.mac.cartella.appendingPathComponent(b.tombstoneName(v.id)))
        let r = b.sync()
        require(r.issues.contains { $0.hasPrefix("Invalid tombstone") }, "Invalid tombstone not reported: \(r.issues)")
        require(b.has(b.mac.file(v.id)) && b.has(b.phone.file(v.id)), "An invalid tombstone deleted the entry")
    }

    // A tombstone on a call is set aside: the call stays visible on both sides.
    do {
        let b = Bench()
        let call = VoceDiario.call(trascrizione: "testi/Synthetic_call_2026-07-27.txt", titolo: "Synthetic call",
                                   quando: Date())
        try b.mac.scrivi(call)
        try Diario.codificatore().encode(Lapide(id: call.id, dispositivo: "iphone"))
            .write(to: b.mac.cartella.appendingPathComponent(b.tombstoneName(call.id)))
        let r = b.sync()
        require(r.issues.contains { $0.hasPrefix("Tombstone on a call") }, "Call tombstone not reported: \(r.issues)")
        require(b.phone.voci().contains { $0.id == call.id }, "The call is hidden on the iPhone")
        require(b.mac.voci().contains { $0.id == call.id }, "The call is hidden in iCloud")
        let second = b.sync(); require(second.issues.isEmpty, "The same call tombstone is reported on every pass: \(second.issues)")
    }

    // Conflict copies, broken JSON and mismatched ids stay out.
    do {
        let b = Bench()
        try FileManager.default.createDirectory(at: b.mac.cartella, withIntermediateDirectories: true)
        let broken = UUID().uuidString.lowercased()
        try Data(#"{"schema": 1, "id": "#.utf8).write(to: b.mac.cartella.appendingPathComponent("\(broken).json"))
        let other = VoceDiario(dispositivo: "mac", tipo: .nota, testo: "wrong name")
        try Diario.codificatore().encode(other)
            .write(to: b.mac.cartella.appendingPathComponent("\(UUID().uuidString.lowercased()).json"))
        let copy = VoceDiario(dispositivo: "mac", tipo: .nota, testo: "conflict copy")
        try Diario.codificatore().encode(copy)
            .write(to: b.mac.cartella.appendingPathComponent("\(copy.id.uuidString.lowercased()) 2.json"))
        let r = b.sync()
        require(b.names(b.phone.cartella).isEmpty, "An invalid file entered the iPhone diary")
        require(r.issues.count == 3, "Not every invalid file was reported: \(r.issues)")
    }

    // An iCloud placeholder counts as present: nothing is written next to it.
    do {
        let b = Bench()
        let v = VoceDiario(dispositivo: "iphone", tipo: .nota, testo: "already in iCloud")
        try b.phone.scrivi(v)
        try FileManager.default.createDirectory(at: b.mac.cartella, withIntermediateDirectories: true)
        try Data().write(to: b.mac.cartella.appendingPathComponent(".\(v.id.uuidString.lowercased()).json.icloud"))
        let r = b.sync()
        require(!b.has(b.mac.file(v.id)), "Written next to a placeholder: a conflict in iCloud")
        require(r.waiting >= 1 && r.issues.isEmpty, "Placeholder not treated as waiting: \(r)")
    }

    // An entry that vanished from iCloud without a tombstone is not uploaded again.
    do {
        let b = Bench()
        let v = VoceDiario(dispositivo: "iphone", tipo: .dettatura, testo: "deleted elsewhere 6604")
        try b.phone.scrivi(v)
        _ = b.sync()
        try FileManager.default.removeItem(at: b.mac.file(v.id))
        let r = b.sync()
        require(!b.has(b.mac.file(v.id)), "A vanished entry was uploaded again")
        require(r.issues.contains { $0.hasPrefix("Entry vanished") }, "The vanished entry is not reported")
    }

    // Call transcripts move down only, written once, never overwritten.
    do {
        let b = Bench()
        let cloudTexts = b.cloud.appendingPathComponent("testi")
        let localTexts = b.local.appendingPathComponent("testi")
        try FileManager.default.createDirectory(at: cloudTexts, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: localTexts, withIntermediateDirectories: true)
        try Data("Speaker A: synthetic 1,6.\n".utf8).write(to: cloudTexts.appendingPathComponent("A_2026-07-27.txt"))
        try Data("from the Mac\n".utf8).write(to: cloudTexts.appendingPathComponent("B_2026-07-27.txt"))
        try Data("edited on the phone\n".utf8).write(to: localTexts.appendingPathComponent("B_2026-07-27.txt"))
        try Data("only on the phone\n".utf8).write(to: localTexts.appendingPathComponent("C_2026-07-27.txt"))
        try FileManager.default.createDirectory(at: cloudTexts.appendingPathComponent("sub"), withIntermediateDirectories: true)
        let r = b.sync()
        let copiedA = try Data(contentsOf: localTexts.appendingPathComponent("A_2026-07-27.txt"))
        require(copiedA == Data("Speaker A: synthetic 1,6.\n".utf8), "The transcript copy differs")
        let cloudB = try Data(contentsOf: cloudTexts.appendingPathComponent("B_2026-07-27.txt"))
        require(cloudB == Data("from the Mac\n".utf8), "The iPhone overwrote a transcript in iCloud")
        require(r.issues.contains { $0.hasPrefix("Different transcript") }, "The transcript conflict is not reported")
        require(!b.has(cloudTexts.appendingPathComponent("C_2026-07-27.txt")), "The iPhone uploaded a transcript")
        require(r.issues.contains { $0.contains("sub") }, "A subfolder in the transcripts is not reported")
        require(!b.has(localTexts.appendingPathComponent("sub")), "A subfolder was copied")
        require(b.sync().copied == 0, "A second pass copied again")
    }

    // Entries flow both ways once; status does not promise an upload; no temporaries left.
    do {
        let b = Bench()
        let mine = VoceDiario(dispositivo: "iphone", tipo: .dettatura, testo: "from the iPhone")
        let theirs = VoceDiario(dispositivo: "mac", tipo: .dettatura, testo: "from the Mac")
        try b.phone.scrivi(mine)
        try b.mac.scrivi(theirs)
        require(b.sync().copied == 2, "Entries were not copied both ways")
        let again = b.sync()
        require(again.copied == 0 && again.issues.isEmpty, "Second pass not idempotent: \(again)")
        let phoneBytes = try Data(contentsOf: b.phone.file(theirs.id))
        let macBytes = try Data(contentsOf: b.mac.file(theirs.id))
        require(phoneBytes == macBytes, "The copied entry is not byte-identical")
        require(b.allFiles().allSatisfy { !$0.lastPathComponent.hasSuffix(".tmp") }, "A temporary file was left")
        let ok = SpecchioDiario.statusText(SpecchioDiario.Esito(), at: Date())
        require(!ok.lowercased().contains("synced"), "Status promises an upload it cannot see: \(ok)")
        require(SpecchioDiario.statusText(nil, at: Date()).contains("unavailable"), "No-iCloud status")
    }
}
