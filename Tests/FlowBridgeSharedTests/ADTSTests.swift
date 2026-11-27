import FlowBridgeShared
import XCTest

/// A wrong header makes every recording unplayable, so the provider rejects it.
final class ADTSTests: XCTestCase {
    func testHeaderEncodesFrameLengthRateAndChannel() throws {
        let header = try XCTUnwrap(ADTS.header(payloadLength: 300, sampleRate: 48_000, channels: 1))
        let bytes = [UInt8](header)

        XCTAssertEqual(bytes.count, ADTS.headerLength)
        XCTAssertEqual(bytes[0], 0xFF)
        XCTAssertEqual(bytes[1] & 0xF0, 0xF0, "Sync word")
        XCTAssertEqual((bytes[2] >> 2) & 0x0F, 3, "48 kHz is index 3")
        let channels = (bytes[2] & 1) << 2 | bytes[3] >> 6
        XCTAssertEqual(channels, 1)
        let frameLength = Int(bytes[3] & 3) << 11 | Int(bytes[4]) << 3 | Int(bytes[5]) >> 5
        XCTAssertEqual(frameLength, 307)
    }

    func testUnsupportedRateHasNoHeader() {
        XCTAssertNil(ADTS.header(payloadLength: 300, sampleRate: 47_000, channels: 1))
    }
}
