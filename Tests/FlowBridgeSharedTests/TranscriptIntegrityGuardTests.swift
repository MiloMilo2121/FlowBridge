import FlowBridgeShared
import XCTest

final class TranscriptIntegrityGuardTests: XCTestCase {
    func testConservativeCleanup() {
        XCTAssertTrue(TranscriptIntegrityGuard.accepts(
            original: "Ehm, ciao ciao Marco.", cleaned: "Ciao Marco."))
        XCTAssertFalse(TranscriptIntegrityGuard.accepts(
            original: "Costa 1,3 milioni.", cleaned: "Costa 13 milioni."))
        XCTAssertFalse(TranscriptIntegrityGuard.accepts(
            original: "Non mandarlo.", cleaned: "Mandalo."))
        XCTAssertFalse(TranscriptIntegrityGuard.accepts(
            original: "Luca ha detto sì.", cleaned: "Luka ha detto sì."))
    }
}
