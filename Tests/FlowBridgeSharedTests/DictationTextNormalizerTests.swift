import FlowBridgeShared
import XCTest

final class DictationTextNormalizerTests: XCTestCase {
    func testCollapsesWhitespaceAndPunctuationSpacing() {
        let result = DictationTextNormalizer.normalize(" hello   world  , this is  flowbridge  ! ")
        XCTAssertEqual(result, "Hello world, this is flowbridge!")
    }

    func testPreservesEmptyText() {
        XCTAssertEqual(DictationTextNormalizer.normalize("   "), "")
    }
}
