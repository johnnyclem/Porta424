import XCTest
@testable import Porta424AudioEngine

final class Porta424AudioEngineTests: XCTestCase {
    func testInitialState() {
        let engine = Porta424Engine()
        XCTAssertEqual(engine.channels.count, 6)
        XCTAssertEqual(engine.meters.count, 4)
        XCTAssertEqual(engine.counterString, "00:00")
    }
}
