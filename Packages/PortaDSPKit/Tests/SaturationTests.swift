import XCTest
@testable import PortaDSPKit

final class SaturationTests: XCTestCase {
    func testDriveIncreasesTHDAndMaintainsRMS() {
        let sampleRate: Double = 48_000
        let frequency: Double = 1_000
        let amplitude: Float = 0.9
        let frames = 48_000
        let driveValues: [Float] = [-12, 0, 12, 24]

        var previousRMS: Double?
        var maxObservedTHD: Double = 0

        for drive in driveValues {
            let dsp = PortaDSP(sampleRate: sampleRate, maxBlock: frames, tracks: 1)
            var params = PortaDSP.Params.zeroed()
            params.satDriveDb = drive
            dsp.update(params)

            var settle = [Float](repeating: 0, count: 256)
            dsp.processInterleaved(buffer: &settle, frames: settle.count, channels: 1)

            var buffer = (0..<frames).map { index -> Float in
                let phase = 2.0 * Double.pi * frequency / sampleRate * Double(index)
                return amplitude * Float(sin(phase))
            }
            dsp.processInterleaved(buffer: &buffer, frames: frames, channels: 1)

            let metrics = analyzeSignal(buffer, sampleRate: sampleRate, frequency: frequency)

            XCTAssertTrue(metrics.thd.isFinite, "THD should remain finite")
            XCTAssertTrue(metrics.rms.isFinite, "RMS should remain finite")

            if let priorRMS = previousRMS {
                XCTAssertGreaterThan(metrics.rms, priorRMS * 0.95, "Output RMS should not collapse as drive increases")
            }
            previousRMS = metrics.rms

            maxObservedTHD = max(maxObservedTHD, metrics.thd)
        }

        XCTAssertGreaterThan(maxObservedTHD, 0.1, "Saturation should introduce measurable distortion")
    }

    private func analyzeSignal(_ buffer: [Float], sampleRate: Double, frequency: Double) -> (rms: Double, thd: Double) {
        guard !buffer.isEmpty else { return (0.0, 0.0) }

        var sumSquares: Double = 0
        var sumSin: Double = 0
        var sumCos: Double = 0
        let omega = 2.0 * Double.pi * frequency / sampleRate

        for (index, sample) in buffer.enumerated() {
            let value = Double(sample)
            sumSquares += value * value
            let phase = omega * Double(index)
            sumSin += value * sin(phase)
            sumCos += value * cos(phase)
        }

        let sampleCount = Double(buffer.count)
        let rms = sqrt(sumSquares / sampleCount)
        let fundamentalAmplitude = 2.0 / sampleCount * sqrt(sumSin * sumSin + sumCos * sumCos)
        let fundamentalRMS = fundamentalAmplitude / sqrt(2.0)
        let harmonicRmsSquared = max(rms * rms - fundamentalRMS * fundamentalRMS, 0.0)
        let harmonicRms = sqrt(harmonicRmsSquared)
        let thd = fundamentalRMS > 0 ? harmonicRms / fundamentalRMS : 0.0

        return (rms, thd)
    }
}
