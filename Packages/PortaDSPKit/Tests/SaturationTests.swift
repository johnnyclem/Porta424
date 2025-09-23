import XCTest
@testable import PortaDSPKit

final class SaturationTests: XCTestCase {
    func testDriveIncreasesTHDAndMaintainsRMS() {
        let sampleRate: Double = 48_000
        let frequency: Double = 1_000
        let amplitude: Float = 0.9
        let frames = 48_000
        let driveValues: [Float] = [-12, 0, 12, 24]

        var previousTHD: Double?
        var baselineRMS: Double?

        for drive in driveValues {
            let dsp = PortaDSP(sampleRate: sampleRate, maxBlock: frames, tracks: 1)
            var params = PortaDSP.Params()
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

            if let previous = previousTHD {
                XCTAssertGreaterThan(metrics.thd, previous * 1.05, "THD should grow with drive")
            }
            previousTHD = metrics.thd

            if baselineRMS == nil {
                baselineRMS = metrics.rms
            } else if let baseline = baselineRMS {
                let diffDb = 20.0 * log10(metrics.rms / baseline)
                XCTAssertLessThan(abs(diffDb), 1.0, "Output RMS deviates by more than ±1 dB")
            }
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
