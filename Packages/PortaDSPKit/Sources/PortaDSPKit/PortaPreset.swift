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

    /// Build a serializable preset from the in-app / AU factory catalog.
    public init(factory: PortaDSPPreset, author: String? = "PortaDSP") {
        self.formatVersion = PortaPreset.currentFormatVersion
        self.name = factory.name
        self.author = author
        self.parameters = factory.parameters
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
    /// Single source of truth: mirrors `PortaDSPPreset.factoryPresets`.
    static let factoryPresets: [PortaPreset] = PortaDSPPreset.factoryPresets.map {
        PortaPreset(factory: $0)
    }

    static var cleanCassette: PortaPreset { PortaPreset(factory: .cleanCassette) }
    static var warmBump: PortaPreset { PortaPreset(factory: .warmBump) }
    static var loFiWarble: PortaPreset { PortaPreset(factory: .loFiWarble) }
    static var crunchySaturation: PortaPreset { PortaPreset(factory: .crunchySaturation) }
    static var dustyArchive: PortaPreset { PortaPreset(factory: .dustyArchive) }

    // Legacy aliases kept so older host code continues to compile.
    @available(*, deprecated, renamed: "loFiWarble")
    static var wobblyLoFi: PortaPreset { .loFiWarble }

    @available(*, deprecated, renamed: "dustyArchive")
    static var noisyVHS: PortaPreset { .dustyArchive }
}
