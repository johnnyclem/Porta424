import XCTest
import Foundation
import PortaDSPBridge

final class ModuleDSPTests: XCTestCase {
    func testSaturationMatchesTanh() {
        let input: Float = 0.5
        let driveDb: Float = 6.0
        let expected = tanh(input * pow(10.0, driveDb / 20.0))
        let output = porta_test_saturation(input, driveDb)
        XCTAssertEqual(output, expected, accuracy: 1e-6)
    }

    func testHeadBumpSingleSampleResponse() {
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

        let omega = 2.0 * Float.pi * freqHz / sampleRate
        let alpha = 1.0 - exp(-omega)
        let gain = pow(10.0, gainDb / 20.0)
        let expected = input[0] + (gain - 1.0) * alpha * input[0]
        XCTAssertEqual(output[0], expected, accuracy: 1e-5)
    }

    func testWowFlutterAppliesDeterministicModulation() {
        let frames = Int32(4)
        let sampleRate: Float = 48_000.0
        let wowRate: Float = 0.5
        let flutterRate: Float = 5.0
        let wowDepth: Float = 0.002
        let flutterDepth: Float = 0.001
        let input = [Float](repeating: 1.0, count: Int(frames))
        var output = [Float](repeating: 0.0, count: Int(frames))

        input.withUnsafeBufferPointer { inPtr in
            output.withUnsafeMutableBufferPointer { outPtr in
                porta_test_wow_flutter(inPtr.baseAddress, outPtr.baseAddress, frames, sampleRate, wowDepth, flutterDepth, wowRate, flutterRate)
            }
        }

        var wowPhase: Float = 0.0
        var flutterPhase: Float = 0.0
        let twoPi = 2.0 * Float.pi
        let wowIncrement = twoPi * wowRate / sampleRate
        let flutterIncrement = twoPi * flutterRate / sampleRate

        for idx in 0..<Int(frames) {
            let modulation = 1.0 + wowDepth * sin(wowPhase) + flutterDepth * sin(flutterPhase)
            XCTAssertEqual(output[idx], modulation * input[idx], accuracy: 1e-6)
            wowPhase += wowIncrement
            flutterPhase += flutterIncrement
            if wowPhase > twoPi { wowPhase -= twoPi }
            if flutterPhase > twoPi { flutterPhase -= twoPi }
        }
    }
}

