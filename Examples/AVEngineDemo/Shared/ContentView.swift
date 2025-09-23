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

            MeterStack(levels: engineManager.meters)

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

private struct MeterStack: View {
    let levels: [Float]

    private let floor: Float = -120.0

    @ViewBuilder
    var body: some View {
        if levels.isEmpty {
            EmptyView()
        } else {
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                    MeterBar(level: level, index: index, floor: floor)
                }
            }
            .frame(height: 120)
            .frame(maxWidth: .infinity)
            .animation(.easeOut(duration: 0.08), value: levels)
            .accessibilityElement(children: .contain)
        }
    }
}

private struct MeterBar: View {
    let level: Float
    let index: Int
    let floor: Float

    private var normalized: CGFloat {
        let clamped = max(floor, min(0, level))
        return CGFloat((clamped - floor) / abs(floor))
    }

    private var displayLevel: Float {
        max(floor, min(0, level))
    }

    var body: some View {
        GeometryReader { proxy in
            let barHeight = max(proxy.size.height * normalized, 4)
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.secondary.opacity(0.15))
                RoundedRectangle(cornerRadius: 4)
                    .fill(LinearGradient(colors: [.green, .yellow, .red], startPoint: .bottom, endPoint: .top))
                    .frame(height: barHeight)
            }
            .accessibilityLabel("Channel \(index + 1)")
            .accessibilityValue(String(format: "%.0f dBFS", displayLevel))
        }
        .frame(width: 24)
    }
}
