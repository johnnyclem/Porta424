import XCTest
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
@testable import PortaDSPKit

final class MeterTests: XCTestCase {
    func testMetersReportRmsAndResetEachPoll() {
        let dsp = PortaDSP(sampleRate: 48_000, maxBlock: 64, tracks: 2)
        let frames = 32
        let channels = 2
        var buffer = [Float](repeating: 0.25, count: frames * channels)

        dsp.processInterleaved(buffer: &buffer, frames: frames, channels: channels)

        let meters = dsp.readMeters()
        XCTAssertGreaterThanOrEqual(meters.count, channels)

        let sample = tanhf(0.25)
        let expectedDb = Float(20.0 * log10(Double(sample)))
        let tolerance: Float = 1.0

        for channel in 0..<channels {
            XCTAssertEqual(meters[channel], expectedDb, accuracy: tolerance, "Channel \(channel) meter should reflect RMS level")
        }

        let resetMeters = dsp.readMeters()
        for channel in 0..<channels {
            XCTAssertLessThan(resetMeters[channel], -119.0, "Channel \(channel) meter should reset after read")
        }
    }
}
