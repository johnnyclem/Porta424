import XCTest
@testable import Porta424AudioEngine

@MainActor
final class TapeTimelineTests: XCTestCase {

    private func region(start: TimeInterval, duration: TimeInterval, fileOffset: TimeInterval = 0) -> TapeRegion {
        TapeRegion(
            url: URL(fileURLWithPath: "/tmp/t.caf"),
            start: start,
            duration: duration,
            fileOffset: fileOffset
        )
    }

    func testCommitAppendsEmptyTimeline() {
        var regions: [TapeRegion] = []
        TapeTimeline.commit(region(start: 0, duration: 2), into: &regions)
        XCTAssertEqual(regions.count, 1)
        XCTAssertEqual(regions[0].start, 0)
        XCTAssertEqual(regions[0].duration, 2, accuracy: 0.0001)
    }

    func testPunchSplitsOverlappingRegion() {
        var regions = [region(start: 0, duration: 10)]
        // Punch 3...5
        TapeTimeline.commit(region(start: 3, duration: 2), into: &regions)

        XCTAssertEqual(regions.count, 3)
        // Left 0...3
        XCTAssertEqual(regions[0].start, 0, accuracy: 0.0001)
        XCTAssertEqual(regions[0].duration, 3, accuracy: 0.0001)
        XCTAssertEqual(regions[0].fileOffset, 0, accuracy: 0.0001)
        // Punch 3...5
        XCTAssertEqual(regions[1].start, 3, accuracy: 0.0001)
        XCTAssertEqual(regions[1].duration, 2, accuracy: 0.0001)
        // Right 5...10 with file offset advanced by 5
        XCTAssertEqual(regions[2].start, 5, accuracy: 0.0001)
        XCTAssertEqual(regions[2].duration, 5, accuracy: 0.0001)
        XCTAssertEqual(regions[2].fileOffset, 5, accuracy: 0.0001)
    }

    func testPunchFullyReplacesContainedRegion() {
        var regions = [region(start: 2, duration: 2)] // 2...4
        TapeTimeline.commit(region(start: 0, duration: 10), into: &regions)
        XCTAssertEqual(regions.count, 1)
        XCTAssertEqual(regions[0].start, 0)
        XCTAssertEqual(regions[0].duration, 10, accuracy: 0.0001)
    }

    func testPlayableFiltersPastRegions() {
        let regions = [
            region(start: 0, duration: 1),
            region(start: 2, duration: 1),
            region(start: 5, duration: 2)
        ]
        let playable = TapeTimeline.playable(from: regions, at: 2.5)
        XCTAssertEqual(playable.count, 2)
        XCTAssertEqual(playable[0].start, 2, accuracy: 0.0001)
        XCTAssertEqual(playable[1].start, 5, accuracy: 0.0001)
    }

    func testTrackStates() {
        let all = [
            [region(start: 0, duration: 1)],
            [],
            [region(start: 0, duration: 1), region(start: 2, duration: 3)],
            []
        ]
        let states = TapeTimeline.trackStates(from: all)
        XCTAssertEqual(states.count, 4)
        XCTAssertTrue(states[0].hasTape)
        XCTAssertFalse(states[1].hasTape)
        XCTAssertEqual(states[2].regionCount, 2)
        XCTAssertEqual(states[2].totalDuration, 5, accuracy: 0.0001)
    }
}
