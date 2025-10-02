import XCTest
@testable import PortaDSPKit

final class DropoutsTests: XCTestCase {
    func testDropoutLengthIncludesTriggeringFrame() {
        let frames = 16
        let channels = 1
        let sampleRate: Float = 100.0
        let dropoutRatePerMinute: Float = 3000.0
        let dropoutLength = 4
        let seed: UInt32 = 0x01234567

        var buffer = [Float](repeating: 1.0, count: frames * channels)
        PortaDSPTesting.applyDropouts(
            buffer: &buffer,
            frames: frames,
            channels: channels,
            sampleRate: sampleRate,
            dropoutRatePerMinute: dropoutRatePerMinute,
            dropoutLengthSamples: dropoutLength,
            seed: seed
        )

        guard let firstDropIndex = buffer.firstIndex(where: { $0 < 1.0 }) else {
            XCTFail("Expected dropout to modify at least one sample")
            return
        }

        let dropoutValue = buffer[firstDropIndex]
        var consecutiveDropoutSamples = 0
        var index = firstDropIndex
        while index < buffer.count && abs(buffer[index] - dropoutValue) < 1.0e-6 {
            consecutiveDropoutSamples += 1
            index += 1
        }

        XCTAssertEqual(firstDropIndex, 0, "Triggering frame should be part of the dropout")
        XCTAssertEqual(consecutiveDropoutSamples, dropoutLength, "Dropout should span exactly the requested length")

        if index < buffer.count {
            XCTAssertGreaterThan(buffer[index], dropoutValue, "Samples following the dropout should recover")
        }
    }
}
