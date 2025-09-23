import XCTest
@testable import PortaDSPKit

final class PassthroughTests: XCTestCase {
    private let tolerance: Float = 1.0e-6

    func testMonoPassthroughCopiesSamples() {
        let input: [Float] = [0.1, 0.2, 0.3]
        let frames = input.count
        let channels = 1

        let output = PortaDSP.passthrough(input: input, frames: frames, channels: channels)

        XCTAssertEqual(output.count, input.count, "Mono passthrough should preserve sample count")
        zip(output, input).forEach { outSample, inSample in
            XCTAssertEqual(outSample, inSample, accuracy: tolerance)
        }
    }

    func testStereoPassthroughCopiesSamples() {
        let baseSamples: [Float] = [0.1, 0.2, 0.3]
        let input = baseSamples.flatMap { [$0, $0] }
        let frames = baseSamples.count
        let channels = 2

        let output = PortaDSP.passthrough(input: input, frames: frames, channels: channels)

        XCTAssertEqual(output.count, input.count, "Stereo passthrough should preserve sample count")
        zip(output, input).forEach { outSample, inSample in
            XCTAssertEqual(outSample, inSample, accuracy: tolerance)
        }
    }
}
