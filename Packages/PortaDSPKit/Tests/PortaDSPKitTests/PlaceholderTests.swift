import XCTest
@testable import PortaDSPKit

final class PlaceholderTests: XCTestCase {
    func testMakeCParamsRandomized() {
        var generator = SeededGenerator(seed: 0xDEADBEEF)

        for _ in 0..<100 {
            let params = PortaDSP.Params.randomized(using: &generator)
            assertBridgeMatches(params)
        }
    }

    func testMakeCParamsEdgeValues() {
        let edgeFloatValues: [Float] = [0.0, 1.0, -Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude]
        let edgeBoolValues: [Bool] = [false, true]

        for floatValue in edgeFloatValues {
            for boolValue in edgeBoolValues {
                let params = PortaDSP.Params.repeating(floatValue, bypass: boolValue)
                assertBridgeMatches(params)
            }
        }
    }

    private func assertBridgeMatches(_ params: PortaDSP.Params, file: StaticString = #filePath, line: UInt = #line) {
        let cStruct = params.makeCParams()

        XCTAssertEqual(cStruct.wowDepth, params.wowDepth, file: file, line: line)
        XCTAssertEqual(cStruct.flutterDepth, params.flutterDepth, file: file, line: line)
        XCTAssertEqual(cStruct.headBumpGainDb, params.headBumpGainDb, file: file, line: line)
        XCTAssertEqual(cStruct.headBumpFreqHz, params.headBumpFreqHz, file: file, line: line)
        XCTAssertEqual(cStruct.satDriveDb, params.satDriveDb, file: file, line: line)
        XCTAssertEqual(cStruct.hissLevelDbFS, params.hissLevelDbFS, file: file, line: line)
        XCTAssertEqual(cStruct.lpfCutoffHz, params.lpfCutoffHz, file: file, line: line)
        XCTAssertEqual(cStruct.azimuthJitterMs, params.azimuthJitterMs, file: file, line: line)
        XCTAssertEqual(cStruct.crosstalkDb, params.crosstalkDb, file: file, line: line)
        XCTAssertEqual(cStruct.dropoutRatePerMin, params.dropoutRatePerMin, file: file, line: line)
        XCTAssertEqual(cStruct.nrTrack4Bypass, params.nrTrack4Bypass ? 1 : 0, file: file, line: line)
    }
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

private extension PortaDSP.Params {
    static func randomized<G: RandomNumberGenerator>(using generator: inout G) -> PortaDSP.Params {
        var params = PortaDSP.Params()
        params.wowDepth = .random(in: -1_000...1_000, using: &generator)
        params.flutterDepth = .random(in: -1_000...1_000, using: &generator)
        params.headBumpGainDb = .random(in: -60...60, using: &generator)
        params.headBumpFreqHz = .random(in: 0...20_000, using: &generator)
        params.satDriveDb = .random(in: -40...40, using: &generator)
        params.hissLevelDbFS = .random(in: -120...0, using: &generator)
        params.lpfCutoffHz = .random(in: 20...30_000, using: &generator)
        params.azimuthJitterMs = .random(in: 0...5, using: &generator)
        params.crosstalkDb = .random(in: -120...0, using: &generator)
        params.dropoutRatePerMin = .random(in: 0...60, using: &generator)
        params.nrTrack4Bypass = Bool.random(using: &generator)
        return params
    }

    static func repeating(_ value: Float, bypass: Bool) -> PortaDSP.Params {
        var params = PortaDSP.Params()
        params.wowDepth = value
        params.flutterDepth = value
        params.headBumpGainDb = value
        params.headBumpFreqHz = value
        params.satDriveDb = value
        params.hissLevelDbFS = value
        params.lpfCutoffHz = value
        params.azimuthJitterMs = value
        params.crosstalkDb = value
        params.dropoutRatePerMin = value
        params.nrTrack4Bypass = bypass
        return params
    }
}
