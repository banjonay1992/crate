import Foundation
import XCTest

/// Loads invented fixture JSON from the test bundle.
enum Fixture {
    static func data(_ name: String, file: StaticString = #filePath, line: UInt = #line) -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            XCTFail("Missing fixture \(name).json", file: file, line: line)
            return Data()
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            XCTFail("Could not read fixture \(name).json: \(error)", file: file, line: line)
            return Data()
        }
    }
}
