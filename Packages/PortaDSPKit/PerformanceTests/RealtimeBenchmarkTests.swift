import Dispatch
import XCTest
@testable import PortaDSPKit

final class RealtimeBenchmarkTests: XCTestCase {
    private enum TestConfig {
        static let sampleRate: Int = 48_000
        static let channels: Int = 2
        static let durationSeconds: Double = 60.0
        static let maxBlock: Int = 512
    }

    func testDSPRealtimePerformance() {
        let totalFrames = Int(TestConfig.durationSeconds * Double(TestConfig.sampleRate))
        var buffer = makeStereoProgram(frames: totalFrames, channels: TestConfig.channels)

        let dsp = PortaDSP(sampleRate: Double(TestConfig.sampleRate), maxBlock: TestConfig.maxBlock, tracks: 4)
        dsp.update(PortaDSP.Params())

        let start = DispatchTime.now()
        dsp.processInterleaved(buffer: &buffer, frames: totalFrames, channels: TestConfig.channels)
        let end = DispatchTime.now()

        let elapsedSeconds = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000.0
        let realtimeRatio = elapsedSeconds / TestConfig.durationSeconds
        let realtimePercent = realtimeRatio * 100.0

        print(String(format: "[PortaDSP] Processed %.0fs stereo@%dHz in %.3fs (%.2f%%%% realtime)",
                     TestConfig.durationSeconds,
                     TestConfig.sampleRate,
                     elapsedSeconds,
                     realtimePercent))

        #if os(macOS) && arch(arm64)
        XCTAssertLessThanOrEqual(realtimePercent, 10.0, "DSP processing should be <=10% realtime on Apple Silicon macOS")
        #endif
    }

    private func makeStereoProgram(frames: Int, channels: Int) -> [Float] {
        precondition(channels == 2, "Benchmark assumes stereo processing")
        var result = [Float](repeating: 0.0, count: frames * channels)
        let sampleRate = Double(TestConfig.sampleRate)
        let leftFrequencies: [Double] = [110.0, 220.0, 440.0]
        let rightFrequencies: [Double] = [330.0, 550.0, 660.0]

        for frame in 0..<frames {
            let time = Double(frame) / sampleRate
            let left = leftFrequencies
                .enumerated()
                .map { index, freq -> Double in
                    let amplitude = 0.6 / pow(2.0, Double(index))
                    return amplitude * sin(2.0 * .pi * freq * time)
                }
                .reduce(0.0, +)
            let right = rightFrequencies
                .enumerated()
                .map { index, freq -> Double in
                    let amplitude = 0.6 / pow(2.0, Double(index))
                    return amplitude * sin(2.0 * .pi * freq * time + 0.25 * .pi)
                }
                .reduce(0.0, +)

            result[frame * channels] = Float(left)
            result[frame * channels + 1] = Float(right)
        }

        return result
    }
}
