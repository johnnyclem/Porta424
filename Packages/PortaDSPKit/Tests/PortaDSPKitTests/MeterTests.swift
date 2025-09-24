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

        var params = PortaDSP.Params()
        params.dropoutRatePerMin = 0.0
        params.headBumpGainDb = 0.0
        params.satDriveDb = 0.0
        dsp.update(params)

        dsp.processInterleaved(buffer: &buffer, frames: frames, channels: channels)

        func rmsDb(for channel: Int) -> Float {
            var sum: Double = 0.0
            for frame in 0..<frames {
                let sample = buffer[frame * channels + channel]
                sum += Double(sample * sample)
            }
            let mean = sum / Double(frames)
            let rms = sqrt(mean)
            return rms > 1.0e-9 ? Float(20.0 * log10(rms)) : -120.0
        }

        let meters = dsp.readMeters()
        XCTAssertGreaterThanOrEqual(meters.count, channels)

        let tolerance: Float = 1.0

        for channel in 0..<channels {
            XCTAssertEqual(meters[channel], rmsDb(for: channel), accuracy: tolerance, "Channel \(channel) meter should reflect RMS level")
        }

        let resetMeters = dsp.readMeters()
        for channel in 0..<channels {
            XCTAssertLessThan(resetMeters[channel], -119.0, "Channel \(channel) meter should reset after read")
        }
    }
}
