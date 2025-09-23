import SwiftUI

struct ContentView: View {
    @StateObject private var engineManager = AudioEngineManager()
    @State private var newPresetName = ""
    @State private var saveErrorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Text("PortaDSP AVAudioEngine Demo")
                .font(.title2)
                .multilineTextAlignment(.center)

            Text(engineManager.statusText)
                .font(.body)
                .multilineTextAlignment(.center)

            Button(engineManager.isRunning ? "Stop" : "Start") {
                if engineManager.isRunning {
                    engineManager.stop()
                } else {
                    engineManager.start()
                }
            }
            .buttonStyle(.borderedProminent)

            GroupBox("Presets") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Current preset: \(engineManager.currentPresetName)")
                        .font(.subheadline)

                    HStack(spacing: 12) {
                        TextField("Preset name", text: $newPresetName)
                            .textFieldStyle(.roundedBorder)
                        Button("Save") {
                            let trimmed = newPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
                            do {
                                try engineManager.saveCurrentPreset(named: trimmed)
                                newPresetName = ""
                            } catch {
                                saveErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                            }
                        }
                        .disabled(newPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    Divider()

                    Text("Factory presets")
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(engineManager.factoryPresets.enumerated()), id: \.offset) { index, preset in
                            Button(preset.name) {
                                engineManager.applyFactoryPreset(at: index)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    Divider()

                    HStack {
                        Text("Saved presets")
                            .font(.headline)
                        Spacer()
                        Button("Reload") {
                            engineManager.reloadUserPresets()
                        }
                        .buttonStyle(.bordered)
                    }

                    if engineManager.userPresets.isEmpty {
                        Text("No saved presets yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(engineManager.userPresets.enumerated()), id: \.offset) { _, preset in
                                Button(preset.name) {
                                    engineManager.applyUserPreset(preset)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .frame(maxWidth: 400)
        .alert("Unable to Save Preset", isPresented: Binding<Bool>(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveErrorMessage ?? "")
        }
    }
}
