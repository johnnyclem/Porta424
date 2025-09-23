import Foundation
import PortaDSPBridge

extension PortaDSP.Params {
    /// Converts the Swift parameter container into the C bridge struct expected by the DSP core.
    /// - Returns: A `porta_params_t` struct ready to be passed across the bridge.
    func makeCParams() -> porta_params_t {
        porta_params_t(
            wowDepth: wowDepth,
            flutterDepth: flutterDepth,
            headBumpGainDb: headBumpGainDb,
            headBumpFreqHz: headBumpFreqHz,
            satDriveDb: satDriveDb,
            hissLevelDbFS: hissLevelDbFS,
            lpfCutoffHz: lpfCutoffHz,
            azimuthJitterMs: azimuthJitterMs,
            crosstalkDb: crosstalkDb,
            dropoutRatePerMin: dropoutRatePerMin,
            nrTrack4Bypass: nrTrack4Bypass ? 1 : 0
        )
    }
}
