import XCTest
@testable import Footprint

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, visionOS 1.0, *)
class FootprintTests: XCTestCase {
    
    func testLimit() {
        let mem = Footprint.shared.memory
        XCTAssertGreaterThan(mem.limit, 0)
    }
    
    func testName() {
        XCTAssertEqual("\(Footprint.Memory.State.normal)", "normal")
    }
}
