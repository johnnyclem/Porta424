import Foundation

public struct PortaPreset: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1
    public static let fileExtension = "portapreset"

    public let formatVersion: Int
    public var name: String
    public var author: String?
    public var parameters: PortaDSP.Params

    public init(name: String, author: String? = nil, parameters: PortaDSP.Params, formatVersion: Int = PortaPreset.currentFormatVersion) {
        self.formatVersion = formatVersion
        self.name = name
        self.author = author
        self.parameters = parameters
    }

    enum CodingKeys: String, CodingKey {
        case formatVersion
        case name
        case author
        case parameters
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decodeIfPresent(Int.self, forKey: .formatVersion) ?? PortaPreset.currentFormatVersion
        name = try container.decode(String.self, forKey: .name)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        parameters = try container.decode(PortaDSP.Params.self, forKey: .parameters)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(author, forKey: .author)
        try container.encode(parameters, forKey: .parameters)
    }

    public func isCompatible(with formatVersion: Int = PortaPreset.currentFormatVersion) -> Bool {
        self.formatVersion <= formatVersion
    }
}

public extension PortaPreset {
    static let factoryPresets: [PortaPreset] = [
        .cleanCassette,
        .warmBump,
        .crunchySaturation,
        .wobblyLoFi,
        .noisyVHS
    ]

    static var cleanCassette: PortaPreset {
        var params = PortaDSP.Params()
        params.wowDepth = 0.0004
        params.flutterDepth = 0.0002
        params.headBumpGainDb = 2.5
        params.headBumpFreqHz = 85.0
        params.satDriveDb = -8.0
        params.hissLevelDbFS = -70.0
        params.lpfCutoffHz = 14000.0
        params.azimuthJitterMs = 0.1
        params.crosstalkDb = -75.0
        params.dropoutRatePerMin = 0.1
        params.nrTrack4Bypass = true
        return PortaPreset(name: "Clean Cassette", author: "PortaDSP", parameters: params)
    }

    static var warmBump: PortaPreset {
        var params = PortaDSP.Params()
        params.wowDepth = 0.0007
        params.flutterDepth = 0.00035
        params.headBumpGainDb = 5.5
        params.headBumpFreqHz = 70.0
        params.satDriveDb = -3.0
        params.hissLevelDbFS = -62.0
        params.lpfCutoffHz = 12500.0
        params.azimuthJitterMs = 0.2
        params.crosstalkDb = -55.0
        params.dropoutRatePerMin = 0.3
        params.nrTrack4Bypass = false
        return PortaPreset(name: "Warm Bump", author: "PortaDSP", parameters: params)
    }

    static var crunchySaturation: PortaPreset {
        var params = PortaDSP.Params()
        params.wowDepth = 0.0012
        params.flutterDepth = 0.0008
        params.headBumpGainDb = 6.0
        params.headBumpFreqHz = 60.0
        params.satDriveDb = 4.0
        params.hissLevelDbFS = -52.0
        params.lpfCutoffHz = 9500.0
        params.azimuthJitterMs = 0.35
        params.crosstalkDb = -48.0
        params.dropoutRatePerMin = 1.6
        params.nrTrack4Bypass = false
        return PortaPreset(name: "Crunchy Saturation", author: "PortaDSP", parameters: params)
    }

    static var wobblyLoFi: PortaPreset {
        var params = PortaDSP.Params()
        params.wowDepth = 0.0022
        params.flutterDepth = 0.0015
        params.headBumpGainDb = 3.0
        params.headBumpFreqHz = 90.0
        params.satDriveDb = -2.0
        params.hissLevelDbFS = -58.0
        params.lpfCutoffHz = 8000.0
        params.azimuthJitterMs = 0.5
        params.crosstalkDb = -50.0
        params.dropoutRatePerMin = 1.2
        params.nrTrack4Bypass = true
        return PortaPreset(name: "Wobbly Lo-Fi", author: "PortaDSP", parameters: params)
    }

    static var noisyVHS: PortaPreset {
        var params = PortaDSP.Params()
        params.wowDepth = 0.0018
        params.flutterDepth = 0.0011
        params.headBumpGainDb = 1.5
        params.headBumpFreqHz = 95.0
        params.satDriveDb = -5.0
        params.hissLevelDbFS = -45.0
        params.lpfCutoffHz = 6500.0
        params.azimuthJitterMs = 0.6
        params.crosstalkDb = -42.0
        params.dropoutRatePerMin = 2.5
        params.nrTrack4Bypass = false
        return PortaPreset(name: "Noisy VHS", author: "PortaDSP", parameters: params)
    }
}
