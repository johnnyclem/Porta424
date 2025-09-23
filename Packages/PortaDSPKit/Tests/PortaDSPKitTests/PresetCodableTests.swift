import XCTest
@testable import PortaDSPKit

final class PresetCodableTests: XCTestCase {
    func testPresetRoundTrip() throws {
        var params = PortaDSP.Params()
        params.wowDepth = 0.001
        params.flutterDepth = 0.0005
        params.headBumpGainDb = 4.2
        params.headBumpFreqHz = 77.0
        params.satDriveDb = -1.5
        params.hissLevelDbFS = -55.0
        params.lpfCutoffHz = 9300.0
        params.azimuthJitterMs = 0.42
        params.crosstalkDb = -47.0
        params.dropoutRatePerMin = 1.1
        params.nrTrack4Bypass = true

        let preset = PortaPreset(name: "Unit Test", author: "Tests", parameters: params)
        let encoder = JSONEncoder()
        let data = try encoder.encode(preset)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(PortaPreset.self, from: data)

        XCTAssertEqual(decoded, preset)
        XCTAssertTrue(decoded.isCompatible())
    }
}
