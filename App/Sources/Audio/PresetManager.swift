import Foundation
import PortaDSPKit

/// Actor managing preset persistence (save/load user presets as JSON files).
actor PresetManager {

    private let fileManager = FileManager.default

    private var presetDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let dir = appSupport.appendingPathComponent("Porta424/Presets", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Factory Presets

    func factoryPresets() -> [PresetItem] {
        PortaDSPPreset.factoryPresets.map { preset in
            PresetItem(
                id: "factory.\(preset.id)",
                name: preset.name,
                icon: iconForPreset(preset.name),
                isFactory: true
            )
        }
    }

    func factoryParameters(for presetId: String) -> PortaDSP.Params? {
        let name = presetId.replacingOccurrences(of: "factory.", with: "")
        return PortaDSPPreset.factoryPresets.first { $0.id == name }?.parameters
    }

    // MARK: - User Presets

    func loadUserPresets() -> [PresetItem] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: presetDirectory,
            includingPropertiesForKeys: nil
        ) else { return [] }

        return files
            .filter { $0.pathExtension == "portapreset" }
            .compactMap { url -> PresetItem? in
                guard let data = try? Data(contentsOf: url),
                      let preset = try? JSONDecoder().decode(PortaPreset.self, from: data)
                else { return nil }
                return PresetItem(
                    id: "user.\(url.deletingPathExtension().lastPathComponent)",
                    name: preset.name,
                    icon: "slider.horizontal.3",
                    isFactory: false
                )
            }
    }

    func loadUserParameters(for presetId: String) -> PortaDSP.Params? {
        let name = presetId.replacingOccurrences(of: "user.", with: "")
        let url = presetDirectory.appendingPathComponent("\(name).portapreset")
        guard let data = try? Data(contentsOf: url),
              let preset = try? JSONDecoder().decode(PortaPreset.self, from: data)
        else { return nil }
        return preset.parameters
    }

    func saveUserPreset(name: String, parameters: PortaDSP.Params) throws {
        let preset = PortaPreset(name: name, parameters: parameters)
        let data = try JSONEncoder().encode(preset)
        let safeName = name.replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
        let url = presetDirectory.appendingPathComponent("\(safeName).portapreset")
        try data.write(to: url, options: .atomic)
    }

    func deleteUserPreset(_ presetId: String) throws {
        let name = presetId.replacingOccurrences(of: "user.", with: "")
        let url = presetDirectory.appendingPathComponent("\(name).portapreset")
        try fileManager.removeItem(at: url)
    }

    // MARK: - Helpers

    private func iconForPreset(_ name: String) -> String {
        switch name {
        case "Clean Cassette": return "wave.3.right"
        case "Warm Bump": return "triangle.fill"
        case "Lo-Fi Warble": return "waveform.path"
        case "Crunchy Saturation": return "waveform.badge.magnifyingglass"
        case "Dusty Archive": return "square.grid.3x3.fill"
        default: return "music.note"
        }
    }
}
