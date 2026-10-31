import XCTest
@testable import CrateCore

final class SmokeTests: XCTestCase {
    func testVersionIsSet() {
        XCTAssertFalse(CrateCore.version.isEmpty)
    }
}
