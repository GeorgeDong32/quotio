import XCTest

@testable import QuotioForkExtras

final class ForkExtrasTests: XCTestCase {
    func testPortBaseMarker() {
        XCTAssertEqual(ForkExtras.portBase, "upstream-efe2f82")
    }
}
