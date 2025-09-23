import PortaDSPKit
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

            ParameterControls(params: $engineManager.params)

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

private struct ParameterControls: View {
    @Binding var params: PortaDSP.Params

    var body: some View {
        GroupBox("Preset") {
            VStack(alignment: .leading, spacing: 16) {
                FloatParameterSlider(
                    title: "Wow Depth",
                    value: $params.wowDepth,
                    range: 0.0...0.003,
                    format: "%.4f"
                )
                FloatParameterSlider(
                    title: "Saturation Drive (dB)",
                    value: $params.satDriveDb,
                    range: -24.0...12.0,
                    format: "%.1f"
                )
                Toggle("Bypass NR Track 4", isOn: $params.nrTrack4Bypass)
            }
            .padding(.vertical, 4)
        }
    }
}

private struct FloatParameterSlider: View {
    let title: String
    @Binding var value: Float
    let range: ClosedRange<Double>
    let format: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, Double(value)))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { value = Float($0) }
                ),
                in: range
            )
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
