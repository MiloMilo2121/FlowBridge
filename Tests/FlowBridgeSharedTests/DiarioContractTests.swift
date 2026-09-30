import FlowBridgeShared
import Foundation
import XCTest

final class DiarioContractTests: XCTestCase {
    func testMacFixturesAndTombstone() throws {
        let fixtureDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/diario")
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("flowbridge-diary-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        for file in try FileManager.default.contentsOfDirectory(at: fixtureDirectory,
                                                                 includingPropertiesForKeys: nil) {
            try FileManager.default.copyItem(at: file, to: temporary.appendingPathComponent(file.lastPathComponent))
        }
        let diary = Diario(cartella: temporary, dispositivo: "iphone")
        let entries = diary.voci()
        XCTAssertEqual(entries.count, 4)
        XCTAssertTrue(entries.contains { $0.tipo == .call })
        XCTAssertFalse(entries.contains {
            $0.id.uuidString.lowercased() == "9e8d7c6b-5a4f-4e3d-8c2b-1a0f9e8d7c6b"
        })
        for entry in entries {
            let encoded = try Diario.codificatore().encode(entry)
            XCTAssertEqual(try Diario.decodificatore().decode(VoceDiario.self, from: encoded), entry)
        }
    }

    func testImmutableWrites() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("flowbridge-diary-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let diary = Diario(cartella: directory, dispositivo: "iphone")
        let voice = VoceDiario(dispositivo: "iphone", tipo: .dettatura, testo: "Uno")
        try diary.scrivi(voice)
        XCTAssertThrowsError(try diary.scrivi(voice))
        try diary.cancella(voice.id)
        XCTAssertTrue(diary.voci().isEmpty)
        XCTAssertThrowsError(try diary.scrivi(voice))
    }
}
