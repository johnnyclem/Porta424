import XCTest
import Foundation
import PortaDSPBridge

final class HissDSPTests: XCTestCase {
    func testHissLevelMatchesDb() {
        let frames = 32768
        var noise = [Float](repeating: 0, count: frames)
        noise.withUnsafeMutableBufferPointer { buffer in
            porta_test_render_hiss(buffer.baseAddress, Int32(frames), Int32(1), 48_000, -60, 0x1234_5678_9ABC_DEF0)
        }

        let rmsValue = rms(noise)
        let db = 20.0 * log10(rmsValue)
        XCTAssertEqual(db, -60.0, accuracy: 1.0)
    }

    func testLowPassReducesHighBandEnergy() {
        let sampleRate: Float = 48_000
        let totalFrames = 4096
        let discard = 2048
        var generator = SeededGenerator(seed: 0xC0FFEE)
        var input = [Float](repeating: 0, count: totalFrames)
        for i in 0..<totalFrames {
            input[i] = .random(in: -1.0...1.0, using: &generator)
        }

        var highCut = [Float](repeating: 0, count: totalFrames)
        var lowCut = [Float](repeating: 0, count: totalFrames)

        input.withUnsafeBufferPointer { inputBuffer in
            highCut.withUnsafeMutableBufferPointer { output in
                porta_test_apply_hf_loss(inputBuffer.baseAddress, output.baseAddress, Int32(totalFrames), Int32(1), sampleRate, 20_000)
            }
            lowCut.withUnsafeMutableBufferPointer { output in
                porta_test_apply_hf_loss(inputBuffer.baseAddress, output.baseAddress, Int32(totalFrames), Int32(1), sampleRate, 2_000)
            }
        }

        let analysisHigh = Array(highCut[discard..<totalFrames])
        let analysisLow = Array(lowCut[discard..<totalFrames])

        let windowedHigh = applyHannWindow(analysisHigh)
        let windowedLow = applyHannWindow(analysisLow)

        let spectrumHigh = magnitudeSquaredSpectrum(of: windowedHigh)
        let spectrumLow = magnitudeSquaredSpectrum(of: windowedLow)

        let highBandHigh = bandEnergy(from: spectrumHigh, sampleRate: Double(sampleRate), fftSize: windowedHigh.count, minimumFrequency: 8_000)
        let highBandLow = bandEnergy(from: spectrumLow, sampleRate: Double(sampleRate), fftSize: windowedLow.count, minimumFrequency: 8_000)

        XCTAssertLessThan(highBandLow, highBandHigh * 0.25)
    }
}

private func rms(_ data: [Float]) -> Double {
    guard !data.isEmpty else { return 0 }
    let sum = data.reduce(0.0) { partial, value in
        partial + Double(value * value)
    }
    return sqrt(sum / Double(data.count))
}

private func applyHannWindow(_ signal: [Float]) -> [Float] {
    let count = signal.count
    guard count > 0 else { return [] }
    var result = [Float](repeating: 0, count: count)
    for i in 0..<count {
        let weight = 0.5 * (1.0 - cos(2.0 * Double.pi * Double(i) / Double(count - 1)))
        result[i] = signal[i] * Float(weight)
    }
    return result
}

private func magnitudeSquaredSpectrum(of signal: [Float]) -> [Double] {
    let n = signal.count
    guard n > 1 else { return [] }
    let half = n / 2
    var spectrum = [Double](repeating: 0, count: half)
    for k in 0..<half {
        var real = 0.0
        var imag = 0.0
        let angleBase = -2.0 * Double.pi * Double(k) / Double(n)
        for (index, sample) in signal.enumerated() {
            let angle = angleBase * Double(index)
            let value = Double(sample)
            real += value * cos(angle)
            imag += value * sin(angle)
        }
        spectrum[k] = real * real + imag * imag
    }
    return spectrum
}

private func bandEnergy(from spectrum: [Double], sampleRate: Double, fftSize: Int, minimumFrequency: Double) -> Double {
    guard fftSize > 0 else { return 0 }
    let binResolution = sampleRate / Double(fftSize)
    let startBin = max(Int(minimumFrequency / binResolution), 0)
    guard startBin < spectrum.count else { return 0 }
    return spectrum[startBin...].reduce(0, +)
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        precondition(seed != 0, "Seed must be non-zero")
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 636_413_622_384_679_3005 &+ 1
        return state
    }
}
