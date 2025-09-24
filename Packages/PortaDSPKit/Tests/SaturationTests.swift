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
        var thdValues: [Double] = []

        for drive in driveValues {
            let dsp = PortaDSP(sampleRate: sampleRate, maxBlock: frames, tracks: 1)
            var params = PortaDSP.Params()
            params.satDriveDb = drive
            params.dropoutRatePerMin = 0.0
            params.headBumpGainDb = 0.0
            dsp.update(params)

            var settle = [Float](repeating: 0, count: 256)
            dsp.processInterleaved(buffer: &settle, frames: settle.count, channels: 1)

            var buffer = (0..<frames).map { index -> Float in
                let phase = 2.0 * Double.pi * frequency / sampleRate * Double(index)
                return amplitude * Float(sin(phase))
            }
            dsp.processInterleaved(buffer: &buffer, frames: frames, channels: 1)

            let metrics = analyzeSignal(buffer, sampleRate: sampleRate, frequency: frequency)

            if let previous = previousRMS {
                XCTAssertGreaterThanOrEqual(metrics.rms, previous * 0.999, "Output RMS should not decrease as drive increases")
            }
            previousRMS = metrics.rms
            thdValues.append(metrics.thd)
        }

        guard let minTHD = thdValues.min(), let maxTHD = thdValues.max() else {
            XCTFail("Failed to collect THD measurements")
            return
        }

        XCTAssertGreaterThan(maxTHD - minTHD, 0.1, "THD should vary meaningfully with drive settings")

        if thdValues.count >= 3 {
            let mediumDriveTHD = thdValues[2] // corresponds to +12 dB
            let highDriveTHD = thdValues[3]    // corresponds to +24 dB
            XCTAssertGreaterThan(highDriveTHD, mediumDriveTHD, "Highest drive should introduce more THD than moderate drive")
        }
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
