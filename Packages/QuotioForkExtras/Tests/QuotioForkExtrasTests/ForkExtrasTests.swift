import XCTest

@testable import QuotioForkExtras

final class ForkExtrasTests: XCTestCase {
    func testPortBaseMarker() {
        XCTAssertEqual(QuotioForkExtras.portBase, "upstream-efe2f82")
    }
}
