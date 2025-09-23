@testable import PortaDSPKit

extension PortaDSP.Params {
    static func zeroed() -> PortaDSP.Params {
        var params = PortaDSP.Params()
        params.wowDepth = 0
        params.flutterDepth = 0
        params.headBumpGainDb = 0
        params.headBumpFreqHz = 0
        params.satDriveDb = 0
        params.hissLevelDbFS = -120
        params.lpfCutoffHz = 0
        params.azimuthJitterMs = 0
        params.crosstalkDb = 0
        params.dropoutRatePerMin = 0
        params.nrTrack4Bypass = false
        return params
    }
}
