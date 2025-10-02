import Foundation

/// Describes a preset that maps to a predefined `PortaDSP.Params` configuration.
public struct PortaDSPPreset: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let parameters: PortaDSP.Params

    public init(id: String, name: String, parameters: PortaDSP.Params) {
        self.id = id
        self.name = name
        self.parameters = parameters
    }

    public static func == (lhs: PortaDSPPreset, rhs: PortaDSPPreset) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

public extension PortaDSPPreset {
    /// A balanced, lightly coloured cassette profile.
    static let cleanCassette: PortaDSPPreset = {
        var params = PortaDSP.Params()
        params.wowDepth = 0.0005
        params.flutterDepth = 0.00025
        params.headBumpGainDb = 1.5
        params.headBumpFreqHz = 85.0
        params.satDriveDb = -5.0
        params.hissLevelDbFS = -65.0
        params.lpfCutoffHz = 13500.0
        params.azimuthJitterMs = 0.16
        params.crosstalkDb = -68.0
        params.dropoutRatePerMin = 0.15
        params.nrTrack4Bypass = false
        return PortaDSPPreset(id: "clean-cassette", name: "Clean Cassette", parameters: params)
    }()

    /// Adds extra head bump and saturation for a warm low-end lift.
    static let warmBump: PortaDSPPreset = {
        var params = PortaDSP.Params()
        params.wowDepth = 0.0007
        params.flutterDepth = 0.00035
        params.headBumpGainDb = 4.0
        params.headBumpFreqHz = 78.0
        params.satDriveDb = -3.0
        params.hissLevelDbFS = -60.0
        params.lpfCutoffHz = 12000.0
        params.azimuthJitterMs = 0.22
        params.crosstalkDb = -60.0
        params.dropoutRatePerMin = 0.25
        params.nrTrack4Bypass = false
        return PortaDSPPreset(id: "warm-bump", name: "Warm Bump", parameters: params)
    }()

    /// Heavier modulation and hiss for tape-artifact heavy lofi textures.
    static let loFiWarble: PortaDSPPreset = {
        var params = PortaDSP.Params()
        params.wowDepth = 0.0014
        params.flutterDepth = 0.0008
        params.headBumpGainDb = 2.0
        params.headBumpFreqHz = 75.0
        params.satDriveDb = -1.0
        params.hissLevelDbFS = -54.0
        params.lpfCutoffHz = 9800.0
        params.azimuthJitterMs = 0.4
        params.crosstalkDb = -52.0
        params.dropoutRatePerMin = 0.45
        params.nrTrack4Bypass = false
        return PortaDSPPreset(id: "lo-fi-warble", name: "Lo-Fi Warble", parameters: params)
    }()

    /// Focuses on saturated mids with restrained modulation for forward mixes.
    static let crunchySaturation: PortaDSPPreset = {
        var params = PortaDSP.Params()
        params.wowDepth = 0.00055
        params.flutterDepth = 0.00038
        params.headBumpGainDb = 3.0
        params.headBumpFreqHz = 90.0
        params.satDriveDb = -2.0
        params.hissLevelDbFS = -62.0
        params.lpfCutoffHz = 11200.0
        params.azimuthJitterMs = 0.2
        params.crosstalkDb = -55.0
        params.dropoutRatePerMin = 0.28
        params.nrTrack4Bypass = false
        return PortaDSPPreset(id: "crunchy-saturation", name: "Crunchy Saturation", parameters: params)
    }()

    /// Emulates an aged archive copy with narrow bandwidth and audible noise.
    static let dustyArchive: PortaDSPPreset = {
        var params = PortaDSP.Params()
        params.wowDepth = 0.0011
        params.flutterDepth = 0.0007
        params.headBumpGainDb = 1.2
        params.headBumpFreqHz = 68.0
        params.satDriveDb = -0.5
        params.hissLevelDbFS = -50.0
        params.lpfCutoffHz = 8000.0
        params.azimuthJitterMs = 0.55
        params.crosstalkDb = -46.0
        params.dropoutRatePerMin = 0.55
        params.nrTrack4Bypass = false
        return PortaDSPPreset(id: "dusty-archive", name: "Dusty Archive", parameters: params)
    }()

    /// All bundled presets shipped with PortaDSPKit.
    static let factoryPresets: [PortaDSPPreset] = [
        .cleanCassette,
        .warmBump,
        .loFiWarble,
        .crunchySaturation,
        .dustyArchive
    ]
}
