import XCTest
import Foundation
import PortaDSPBridge

final class ModuleDSPTests: XCTestCase {
    // The saturation stage applies a tanh nonlinearity (scaled by the drive) and
    // then a drive-dependent RMS-compensation trim. For a fixed drive the output
    // is therefore the tanh curve scaled by a single constant trim factor, so the
    // ratio output / tanh(drive * x) is the same for every input.
    func testSaturationAppliesTanhCurveWithConsistentTrim() {
        let driveDb: Float = 6.0
        let driveLinear = powf(10.0, driveDb / 20.0)
        let inputs: [Float] = [0.2, 0.5, 0.8]

        var trims: [Float] = []
        for x in inputs {
            let output = porta_test_saturation(x, driveDb)
            let rawTanh = tanhf(driveLinear * x)
            XCTAssertTrue(output.isFinite)
            // Sign-preserving: tanh and a positive trim keep the input's sign.
            XCTAssertEqual(output < 0, x < 0)
            trims.append(output / rawTanh)
        }

        for trim in trims {
            XCTAssertEqual(trim, trims[0], accuracy: 1e-4)
        }
        XCTAssertGreaterThan(trims[0], 0)
    }

    // The head-bump filter ramps its biquad coefficients from unity toward the
    // target over ~20 ms, so its response to the very first sample is essentially
    // unity; the resonant boost accrues over subsequent samples (see
    // HeadBumpTests for the steady-state resonant behaviour).
    func testHeadBumpFirstSampleIsNearUnity() {
        let frames = Int32(1)
        let sampleRate: Float = 48_000.0
        let gainDb: Float = 6.0
        let freqHz: Float = 60.0
        let input: [Float] = [1.0]
        var output: [Float] = [0.0]

        input.withUnsafeBufferPointer { inPtr in
            output.withUnsafeMutableBufferPointer { outPtr in
                porta_test_head_bump(inPtr.baseAddress, outPtr.baseAddress, frames, sampleRate, gainDb, freqHz)
            }
        }

        XCTAssertTrue(output[0].isFinite)
        XCTAssertEqual(output[0], input[0], accuracy: 0.01)
    }

    // Wow/flutter is a modulated delay line (pitch modulation), not amplitude
    // modulation, and it is deterministically seeded. Two runs with identical
    // parameters must therefore produce identical, finite, bounded output.
    func testWowFlutterIsDeterministicAndBounded() {
        let frames = Int32(8)
        let sampleRate: Float = 48_000.0
        let wowRate: Float = 0.5
        let flutterRate: Float = 5.0
        let wowDepth: Float = 0.002
        let flutterDepth: Float = 0.001
        let input = [Float](repeating: 1.0, count: Int(frames))

        func run() -> [Float] {
            var output = [Float](repeating: 0.0, count: Int(frames))
            input.withUnsafeBufferPointer { inPtr in
                output.withUnsafeMutableBufferPointer { outPtr in
                    porta_test_wow_flutter(inPtr.baseAddress, outPtr.baseAddress, frames, sampleRate, wowDepth, flutterDepth, wowRate, flutterRate)
                }
            }
            return output
        }

        let first = run()
        let second = run()

        XCTAssertEqual(first, second, "Deterministic seeding should make repeated runs identical")
        for value in first {
            XCTAssertTrue(value.isFinite)
            // A delay line of a unit-amplitude signal cannot exceed unity.
            XCTAssertLessThanOrEqual(abs(value), 1.0 + 1e-4)
        }
    }
}
