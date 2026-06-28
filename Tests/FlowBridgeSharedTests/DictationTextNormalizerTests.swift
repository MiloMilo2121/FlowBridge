import FlowBridgeShared
import XCTest

final class DictationTextNormalizerTests: XCTestCase {
    func collapsesWhitespaceAndPunctuationSpacing() {
        let result = DictationTextNormalizer.normalize(" hello   world  , this is  flowbridge  ! ")
        XCTAssertEqual(result, "Hello world, this is flowbridge!")
    }

    func preservesEmptyText() {
        XCTAssertEqual(DictationTextNormalizer.normalize("   "), "")
    }
}
