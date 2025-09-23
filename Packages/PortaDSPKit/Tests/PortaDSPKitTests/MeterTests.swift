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

        let params = PortaDSP.Params.zeroed()
        dsp.update(params)

        dsp.processInterleaved(buffer: &buffer, frames: frames, channels: channels)

        let meters = dsp.readMeters()
        XCTAssertGreaterThanOrEqual(meters.count, channels)

        var perChannelRMS = [Double](repeating: 0.0, count: channels)
        for frame in 0..<frames {
            for channel in 0..<channels {
                let index = frame * channels + channel
                let sample = Double(buffer[index])
                perChannelRMS[channel] += sample * sample
            }
        }

        let expectedDb = perChannelRMS.map { rmsAccumulator -> Float in
            guard rmsAccumulator > 0 else { return -120.0 }
            let rms = sqrt(rmsAccumulator / Double(frames))
            return Float(20.0 * log10(rms))
        }
        let tolerance: Float = 1.0

        for channel in 0..<channels {
            XCTAssertEqual(meters[channel], expectedDb[channel], accuracy: tolerance, "Channel \(channel) meter should reflect RMS level")
        }

        let resetMeters = dsp.readMeters()
        for channel in 0..<channels {
            XCTAssertLessThan(resetMeters[channel], -119.0, "Channel \(channel) meter should reset after read")
        }
    }
}
