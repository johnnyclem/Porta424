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

            MeterStack(levels: engineManager.meters)

            Button(engineManager.isRunning ? "Stop" : "Start") {
                if engineManager.isRunning {
                    engineManager.stop()
                } else {
                    engineManager.start()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: 400)
    }
}

private struct MeterStack: View {
    let levels: [Float]

    @ViewBuilder
    var body: some View {
        if levels.isEmpty {
            EmptyView()
        } else {
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                    MeterBar(level: level, index: index)
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

    private var normalized: CGFloat {
        let floor = AudioEngineManager.meterFloor
        let clamped = max(floor, min(0, level))
        return CGFloat((clamped - floor) / abs(floor))
    }

    private var displayLevel: Float {
        let floor = AudioEngineManager.meterFloor
        return max(floor, min(0, level))
    }

    var body: some View {
        GeometryReader { proxy in
            let barHeight = proxy.size.height * normalized
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
