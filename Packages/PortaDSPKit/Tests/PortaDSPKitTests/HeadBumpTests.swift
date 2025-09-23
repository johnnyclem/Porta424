import XCTest
@testable import PortaDSPKit

final class HeadBumpTests: XCTestCase {
    func testHeadBumpProducesResonantBump() {
        let sampleRate: Float = 48_000
        let frames = 8_192
        let channels = 1
        let amplitude: Float = 0.01
        let dsp = PortaDSP(sampleRate: Double(sampleRate), maxBlock: frames, tracks: channels)

        var params = PortaDSP.Params()
        params.headBumpGainDb = 6.0
        params.headBumpFreqHz = 80.0
        dsp.update(params)

        var warmup = [Float](repeating: 0.0, count: frames)
        dsp.processInterleaved(buffer: &warmup, frames: frames, channels: channels)

        let startIndex = frames / 4
        let targetGain = measureGain(
            frequency: params.headBumpFreqHz,
            amplitude: amplitude,
            sampleRate: sampleRate,
            frames: frames,
            startIndex: startIndex,
            dsp: dsp
        )

        let lowerGain = measureGain(
            frequency: params.headBumpFreqHz / 2,
            amplitude: amplitude,
            sampleRate: sampleRate,
            frames: frames,
            startIndex: startIndex,
            dsp: dsp
        )

        let upperGain = measureGain(
            frequency: params.headBumpFreqHz * 2,
            amplitude: amplitude,
            sampleRate: sampleRate,
            frames: frames,
            startIndex: startIndex,
            dsp: dsp
        )

        let targetDb = 20.0 * log10(targetGain)
        let lowerDb = 20.0 * log10(lowerGain)
        let upperDb = 20.0 * log10(upperGain)

        XCTAssertGreaterThan(targetDb, Double(params.headBumpGainDb) - 1.0, "Head bump should boost near the selected frequency")
        XCTAssertGreaterThan(targetDb - lowerDb, 2.0, "Head bump should be localized relative to lower frequencies")
        XCTAssertGreaterThan(targetDb - upperDb, 2.0, "Head bump should be localized relative to higher frequencies")
    }

    private func measureGain(
        frequency: Float,
        amplitude: Float,
        sampleRate: Float,
        frames: Int,
        startIndex: Int,
        dsp: PortaDSP
    ) -> Double {
        var input = [Float](repeating: 0.0, count: frames)
        let omega = 2.0 * Float.pi * frequency / sampleRate
        for n in 0..<frames {
            input[n] = amplitude * sin(omega * Float(n))
        }

        let inputRms = rms(input, start: startIndex)

        var buffer = input
        dsp.processInterleaved(buffer: &buffer, frames: frames, channels: 1)
        let outputRms = rms(buffer, start: startIndex)

        guard inputRms > 0 else { return 0 }
        return outputRms / inputRms
    }

    private func rms(_ data: [Float], start: Int) -> Double {
        var sum: Double = 0
        var count = 0
        for index in start..<data.count {
            let sample = Double(data[index])
            sum += sample * sample
            count += 1
        }
        return count > 0 ? sqrt(sum / Double(count)) : 0
    }
}
