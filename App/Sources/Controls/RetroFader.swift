import SwiftUI

/// A vertical fader control styled after Tascam portastudio faders.
/// Features a grooved track, realistic cap with color accent, and LED meter.
struct RetroFader: View {
    @Binding var value: Double
    var label: String = ""
    var capColor: Color = Porta.faderCapGreen
    var height: CGFloat = 150
    var meterValue: Double = 0

    @GestureState private var isDragging = false

    private let trackWidth: CGFloat = 6
    private let capWidth: CGFloat = 32
    private let capHeight: CGFloat = 20

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 6) {
                // LED meter alongside fader
                LEDMeter(value: meterValue, segments: 10)
                    .frame(width: 8)

                // Fader track
                GeometryReader { geo in
                    let travelHeight = geo.size.height - capHeight
                    let capY = (1 - value) * travelHeight

                    ZStack(alignment: .top) {
                        // Track groove
                        faderTrack(in: geo)

                        // Scale markings
                        faderScale(in: geo)

                        // Fader cap
                        faderCap
                            .offset(y: capY)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .updating($isDragging) { _, state, _ in
                                        state = true
                                    }
                                    .onChanged { gesture in
                                        let normalized = 1 - min(max(0, gesture.location.y / geo.size.height), 1)
                                        let old = value
                                        value = normalized

                                        // Snap haptic near center
                                        if abs(normalized - 0.5) < 0.02 && abs(old - 0.5) >= 0.02 {
                                            HapticEngine.faderSnap()
                                        }
                                    }
                            )
                    }
                }
                .frame(width: capWidth + 10)
            }
            .frame(height: height)

            if !label.isEmpty {
                Text(label)
                    .font(Porta.labelFont)
                    .foregroundStyle(Porta.label)
                    .tracking(0.5)
            }
        }
    }

    private func faderTrack(in geo: GeometryProxy) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(
                LinearGradient(
                    colors: [Color(white: 0.25), Color(white: 0.18), Color(white: 0.25)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: trackWidth, height: geo.size.height)
            .position(x: (capWidth + 10) / 2, y: geo.size.height / 2)
            .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
    }

    private func faderScale(in geo: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<11, id: \.self) { i in
                if i > 0 { Spacer() }
                Rectangle()
                    .fill(Porta.label.opacity(i % 5 == 0 ? 0.4 : 0.2))
                    .frame(
                        width: i % 5 == 0 ? capWidth * 0.7 : capWidth * 0.4,
                        height: 1
                    )
            }
        }
        .frame(height: geo.size.height)
        .position(x: (capWidth + 10) / 2, y: geo.size.height / 2)
    }

    private var faderCap: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    LinearGradient(
                        colors: [
                            capColor.opacity(0.9),
                            capColor,
                            capColor.opacity(0.7)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            // Grip lines
            VStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: capWidth * 0.5, height: 1)
                }
            }
        }
        .frame(width: capWidth, height: capHeight)
        .shadow(color: Porta.deepShadow, radius: 3, x: 0, y: 2)
        .scaleEffect(isDragging ? CGSize(width: 1.1, height: 1.05) : .init(width: 1, height: 1))
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isDragging)
    }
}

/// Vertical LED segment meter (green → yellow → red) with subtle flicker.
struct LEDMeter: View {
    var value: Double
    var segments: Int = 10

    @State private var flickerSeed: UInt64 = 0

    var body: some View {
        VStack(spacing: 2) {
            ForEach((0..<segments).reversed(), id: \.self) { i in
                let threshold = Double(i + 1) / Double(segments)
                let isLit = value >= threshold
                RoundedRectangle(cornerRadius: 1)
                    .fill(segmentColor(for: i))
                    .opacity(isLit ? ledFlickerOpacity(segment: i) : 0.15)
                    .shadow(
                        color: isLit ? segmentColor(for: i).opacity(0.4) : .clear,
                        radius: isLit ? 2 : 0
                    )
                    .frame(height: 6)
            }
        }
        .onAppear { startFlicker() }
    }

    // Subtle per-segment brightness variation simulating real LED behavior
    private func ledFlickerOpacity(segment: Int) -> Double {
        let hash = (flickerSeed &+ UInt64(segment * 7)) % 100
        return 0.88 + Double(hash) / 100.0 * 0.12  // 0.88 to 1.0
    }

    private func startFlicker() {
        Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                flickerSeed = UInt64.random(in: 0...999)
            }
        }
    }

    private func segmentColor(for index: Int) -> Color {
        let fraction = Double(index) / Double(segments)
        if fraction >= 0.85 { return Porta.meterRed }
        if fraction >= 0.65 { return Porta.meterYellow }
        return Porta.meterGreen
    }
}
