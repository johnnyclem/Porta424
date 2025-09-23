import Foundation
import PortaDSPKit

struct PortaPresetStore {
    enum StoreError: LocalizedError {
        case emptyName

        var errorDescription: String? {
            switch self {
            case .emptyName:
                return "Enter a name before saving the preset."
            }
        }
    }

    private let fileManager: FileManager
    private let directoryURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let baseURL: URL
        if let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            baseURL = support
        } else if let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            baseURL = documents
        } else {
            baseURL = fileManager.temporaryDirectory
        }
        let presetsDirectory = baseURL.appendingPathComponent("PortaPresets", isDirectory: true)
        try? fileManager.createDirectory(at: presetsDirectory, withIntermediateDirectories: true)
        directoryURL = presetsDirectory
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
    }

    func loadPresets() -> [PortaPreset] {
        let urls = (try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)) ?? []
        return urls
            .filter { $0.pathExtension == PortaPreset.fileExtension }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(PortaPreset.self, from: data)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func savePreset(_ preset: PortaPreset) throws {
        guard !preset.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StoreError.emptyName
        }
        let url = fileURL(for: preset.name)
        let data = try encoder.encode(preset)
        try data.write(to: url, options: [.atomic])
    }

    private func fileURL(for name: String) -> URL {
        let allowed = CharacterSet.alphanumerics
        let parts = name.components(separatedBy: allowed.inverted).filter { !$0.isEmpty }
        let joined = parts.joined(separator: "-")
        let finalName = joined.isEmpty ? "Preset" : joined
        return directoryURL.appendingPathComponent(finalName).appendingPathExtension(PortaPreset.fileExtension)
    }
}
