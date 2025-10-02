import Foundation

public extension PortaDSP.Params {
    /// Serializes the parameter set into JSON data.
    /// - Parameter prettyPrinted: When `true`, the JSON output is formatted for readability.
    /// - Returns: Encoded JSON representation of the parameter set.
    func toJSON(prettyPrinted: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        if prettyPrinted {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        } else {
            encoder.outputFormatting = [.sortedKeys]
        }
        return try encoder.encode(self)
    }

    /// Creates a parameter set from JSON data previously produced by ``toJSON(prettyPrinted:)``.
    /// - Parameter data: Encoded parameter data.
    init(fromJSON data: Data) throws {
        let decoder = JSONDecoder()
        self = try decoder.decode(PortaDSP.Params.self, from: data)
    }
}
