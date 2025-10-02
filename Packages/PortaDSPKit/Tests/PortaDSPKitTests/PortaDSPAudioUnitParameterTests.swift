#if canImport(AudioToolbox)
import AudioToolbox
import AVFoundation
@testable import PortaDSPKit
import XCTest

final class PortaDSPAudioUnitParameterTests: XCTestCase {
    func testParameterTreeUpdatesCachedParams() throws {
        let audioUnit = try PortaDSPAudioUnit(componentDescription: PortaDSPAudioUnit.componentDescription)
        let tree = try XCTUnwrap(audioUnit.parameterTree)
        var generator = SeededGenerator(seed: 0xFACECAFE)
        var expected = PortaDSP.Params()

        for identifier in PortaDSPAudioUnit.ParameterID.allCases {
            guard let parameter = tree.parameter(withAddress: identifier.address) else {
                XCTFail("Missing AUParameter for \(identifier)")
                continue
            }

            switch identifier {
            case .wowDepth:
                let value = Float.random(in: identifier.range, using: &generator)
                parameter.setValue(value, originator: nil)
                expected.wowDepth = value
            case .flutterDepth:
                let value = Float.random(in: identifier.range, using: &generator)
                parameter.setValue(value, originator: nil)
                expected.flutterDepth = value
            case .headBumpGainDb:
                let value = Float.random(in: identifier.range, using: &generator)
                parameter.setValue(value, originator: nil)
                expected.headBumpGainDb = value
            case .headBumpFreqHz:
                let value = Float.random(in: identifier.range, using: &generator)
                parameter.setValue(value, originator: nil)
                expected.headBumpFreqHz = value
            case .satDriveDb:
                let value = Float.random(in: identifier.range, using: &generator)
                parameter.setValue(value, originator: nil)
                expected.satDriveDb = value
            case .hissLevelDbFS:
                let value = Float.random(in: identifier.range, using: &generator)
                parameter.setValue(value, originator: nil)
                expected.hissLevelDbFS = value
            case .lpfCutoffHz:
                let value = Float.random(in: identifier.range, using: &generator)
                parameter.setValue(value, originator: nil)
                expected.lpfCutoffHz = value
            case .azimuthJitterMs:
                let value = Float.random(in: identifier.range, using: &generator)
                parameter.setValue(value, originator: nil)
                expected.azimuthJitterMs = value
            case .crosstalkDb:
                let value = Float.random(in: identifier.range, using: &generator)
                parameter.setValue(value, originator: nil)
                expected.crosstalkDb = value
            case .dropoutRatePerMin:
                let value = Float.random(in: identifier.range, using: &generator)
                parameter.setValue(value, originator: nil)
                expected.dropoutRatePerMin = value
            case .nrTrack4Bypass:
                let boolValue = Bool.random(using: &generator)
                parameter.setValue(boolValue ? 1.0 : 0.0, originator: nil)
                expected.nrTrack4Bypass = boolValue
            }
        }

        let snapshot = audioUnit.currentParameters()
        XCTAssertEqual(snapshot.wowDepth, expected.wowDepth, accuracy: tolerance)
        XCTAssertEqual(snapshot.flutterDepth, expected.flutterDepth, accuracy: tolerance)
        XCTAssertEqual(snapshot.headBumpGainDb, expected.headBumpGainDb, accuracy: tolerance)
        XCTAssertEqual(snapshot.headBumpFreqHz, expected.headBumpFreqHz, accuracy: tolerance)
        XCTAssertEqual(snapshot.satDriveDb, expected.satDriveDb, accuracy: tolerance)
        XCTAssertEqual(snapshot.hissLevelDbFS, expected.hissLevelDbFS, accuracy: tolerance)
        XCTAssertEqual(snapshot.lpfCutoffHz, expected.lpfCutoffHz, accuracy: tolerance)
        XCTAssertEqual(snapshot.azimuthJitterMs, expected.azimuthJitterMs, accuracy: tolerance)
        XCTAssertEqual(snapshot.crosstalkDb, expected.crosstalkDb, accuracy: tolerance)
        XCTAssertEqual(snapshot.dropoutRatePerMin, expected.dropoutRatePerMin, accuracy: tolerance)
        XCTAssertEqual(snapshot.nrTrack4Bypass, expected.nrTrack4Bypass)

        let cParams = snapshot.makeCParams()
        XCTAssertEqual(cParams.wowDepth, expected.wowDepth, accuracy: tolerance)
        XCTAssertEqual(cParams.flutterDepth, expected.flutterDepth, accuracy: tolerance)
        XCTAssertEqual(cParams.headBumpGainDb, expected.headBumpGainDb, accuracy: tolerance)
        XCTAssertEqual(cParams.headBumpFreqHz, expected.headBumpFreqHz, accuracy: tolerance)
        XCTAssertEqual(cParams.satDriveDb, expected.satDriveDb, accuracy: tolerance)
        XCTAssertEqual(cParams.hissLevelDbFS, expected.hissLevelDbFS, accuracy: tolerance)
        XCTAssertEqual(cParams.lpfCutoffHz, expected.lpfCutoffHz, accuracy: tolerance)
        XCTAssertEqual(cParams.azimuthJitterMs, expected.azimuthJitterMs, accuracy: tolerance)
        XCTAssertEqual(cParams.crosstalkDb, expected.crosstalkDb, accuracy: tolerance)
        XCTAssertEqual(cParams.dropoutRatePerMin, expected.dropoutRatePerMin, accuracy: tolerance)
        XCTAssertEqual(cParams.nrTrack4Bypass, expected.nrTrack4Bypass ? 1 : 0)
    }

    func testPresetDictionaryRoundTrip() throws {
        let audioUnit = try PortaDSPAudioUnit(componentDescription: PortaDSPAudioUnit.componentDescription)
        var custom = PortaDSP.Params()
        custom.wowDepth = 0.002
        custom.flutterDepth = 0.001
        custom.headBumpGainDb = 6.0
        custom.headBumpFreqHz = 150.0
        custom.satDriveDb = 3.0
        custom.hissLevelDbFS = -42.0
        custom.lpfCutoffHz = 16_000.0
        custom.azimuthJitterMs = 0.4
        custom.crosstalkDb = -30.0
        custom.dropoutRatePerMin = 2.5
        custom.nrTrack4Bypass = true

        audioUnit.updateParameters(custom)
        let preset = audioUnit.exportPresetDictionary()

        var reset = PortaDSP.Params()
        reset.wowDepth = 0.0
        reset.flutterDepth = 0.0
        reset.headBumpGainDb = 0.0
        reset.headBumpFreqHz = 20.0
        reset.satDriveDb = -6.0
        reset.hissLevelDbFS = -60.0
        reset.lpfCutoffHz = 12_000.0
        reset.azimuthJitterMs = 0.0
        reset.crosstalkDb = -120.0
        reset.dropoutRatePerMin = 0.0
        reset.nrTrack4Bypass = false

        audioUnit.updateParameters(reset)
        audioUnit.applyPresetDictionary(preset)

        let snapshot = audioUnit.currentParameters()
        XCTAssertEqual(snapshot.wowDepth, custom.wowDepth, accuracy: tolerance)
        XCTAssertEqual(snapshot.flutterDepth, custom.flutterDepth, accuracy: tolerance)
        XCTAssertEqual(snapshot.headBumpGainDb, custom.headBumpGainDb, accuracy: tolerance)
        XCTAssertEqual(snapshot.headBumpFreqHz, custom.headBumpFreqHz, accuracy: tolerance)
        XCTAssertEqual(snapshot.satDriveDb, custom.satDriveDb, accuracy: tolerance)
        XCTAssertEqual(snapshot.hissLevelDbFS, custom.hissLevelDbFS, accuracy: tolerance)
        XCTAssertEqual(snapshot.lpfCutoffHz, custom.lpfCutoffHz, accuracy: tolerance)
        XCTAssertEqual(snapshot.azimuthJitterMs, custom.azimuthJitterMs, accuracy: tolerance)
        XCTAssertEqual(snapshot.crosstalkDb, custom.crosstalkDb, accuracy: tolerance)
        XCTAssertEqual(snapshot.dropoutRatePerMin, custom.dropoutRatePerMin, accuracy: tolerance)
        XCTAssertEqual(snapshot.nrTrack4Bypass, custom.nrTrack4Bypass)
    }

    private let tolerance: Float = 1e-6
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
#endif
