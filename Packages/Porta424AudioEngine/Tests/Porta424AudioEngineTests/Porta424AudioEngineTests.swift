import XCTest
@testable import Porta424AudioEngine

@MainActor
final class Porta424AudioEngineTests: XCTestCase {
    func testInitialState() {
        let engine = Porta424Engine()
        XCTAssertEqual(engine.channels.count, 6)
        XCTAssertEqual(engine.meters.count, 4)
        XCTAssertEqual(engine.counterString, "00:00")
        XCTAssertEqual(engine.tapeTracks.count, 4)
        XCTAssertFalse(engine.tapeTracks[0].hasTape)
    }
}
