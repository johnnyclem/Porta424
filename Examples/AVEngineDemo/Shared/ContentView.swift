import SwiftUI

struct ContentView: View {
    @StateObject private var engineManager = AudioEngineManager()

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

            VStack(alignment: .leading, spacing: 8) {
                Text("Hiss Level")
                    .font(.headline)

                Slider(
                    value: Binding(
                        get: { Double(engineManager.hissLevelDbFS) },
                        set: { engineManager.hissLevelDbFS = Float($0) }
                    ),
                    in: -120...0
                )

                Text(String(format: "%.1f dBFS", engineManager.hissLevelDbFS))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .frame(maxWidth: 400)
    }
}
