import XCTest
@testable import PortaDSPKit

final class PortaDSPWrapperTests: XCTestCase {
    private let sampleRate: Double = 48_000
    private let tolerance: Float = 1.0e-5

    private func makeDeterministicParams() -> PortaDSP.Params {
        var params = PortaDSP.Params()
        params.dropoutRatePerMin = 0.0
        params.headBumpGainDb = 0.0
        params.satDriveDb = 0.0
        return params
    }

    private func makeTestBuffer(frames: Int, channels: Int) -> [Float] {
        (0..<frames).flatMap { frame in
            (0..<channels).map { channel in
                let index = frame * channels + channel + 1
                return Float(index) / Float(frames * channels + 1)
            }
        }
    }

    func testProcessInterleavedIsDeterministicAcrossInstances() {
        let frames = 32
        let channels = 2
        let params = makeDeterministicParams()

        let dsp = PortaDSP(sampleRate: sampleRate, maxBlock: frames, tracks: channels)
        dsp.update(params)

        var firstPass = makeTestBuffer(frames: frames, channels: channels)
        let originalBuffer = firstPass
        dsp.processInterleaved(buffer: &firstPass, frames: frames, channels: channels)

        let verificationDSP = PortaDSP(sampleRate: sampleRate, maxBlock: frames, tracks: channels)
        verificationDSP.update(params)
        var secondPass = originalBuffer
        verificationDSP.processInterleaved(buffer: &secondPass, frames: frames, channels: channels)

        zip(firstPass, secondPass).forEach { first, second in
            XCTAssertEqual(first, second, accuracy: tolerance)
        }

        let processedDiffersFromInput = zip(firstPass, originalBuffer).contains { abs($0 - $1) > tolerance }
        XCTAssertTrue(processedDiffersFromInput, "Processing should alter at least one sample")
    }

    func testReadMetersReportsChannelRMS() {
        let frames = 48
        let channels = 2
        let dsp = PortaDSP(sampleRate: sampleRate, maxBlock: frames, tracks: channels)
        dsp.update(makeDeterministicParams())

        var buffer = makeTestBuffer(frames: frames, channels: channels)
        dsp.processInterleaved(buffer: &buffer, frames: frames, channels: channels)

        let meters = dsp.readMeters()
        XCTAssertEqual(meters.count, 8)

        for channel in 0..<channels {
            var sumSquares: Double = 0.0
            for frame in 0..<frames {
                let sample = buffer[frame * channels + channel]
                sumSquares += Double(sample * sample)
            }
            let rms = sumSquares > 0 ? sqrt(sumSquares / Double(frames)) : 0.0
            let expectedDb = rms > 1.0e-9 ? 20.0 * log10(rms) : -120.0
            XCTAssertEqual(
                Double(meters[channel]),
                expectedDb,
                accuracy: 0.05,
                "Meter for channel \(channel) should match RMS of processed signal"
            )
        }

        meters[channels...].forEach { value in
            XCTAssertEqual(value, -120.0, accuracy: 1.0e-6, "Unused meter slots should report silence")
        }
    }
}
