import SwiftUI

/// The DSP Parameters panel with four effect knobs (Saturation, Wow, Flutter, Noise)
/// and a Bandwidth slider. Each knob has a unique accent color and animated ring.
struct DSPKnobsPanel: View {
    @Bindable var viewModel: TapeDeckViewModel

    var body: some View {
        VStack(spacing: 10) {
            // Section header with dotted border accent
            HStack {
                Porta.SectionLabel(text: "DSP PARAMS")
                Spacer()
                // Settings dots
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .fill(Porta.label.opacity(0.3))
                            .frame(width: 3, height: 3)
                    }
                }
            }
            .padding(.horizontal, 8)

            // Effect knobs - 2x2 grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                RetroKnob(
                    value: $viewModel.dsp.saturation,
                    title: "SATURATION",
                    accentColor: Porta.saturationOrange,
                    size: 52,
                    detents: [0.5]
                )
                RetroKnob(
                    value: $viewModel.dsp.wow,
                    title: "WOW",
                    accentColor: Porta.wowGreen,
                    size: 52,
                    detents: [0.0]
                )
                RetroKnob(
                    value: $viewModel.dsp.flutter,
                    title: "FLUTTER",
                    accentColor: Porta.flutterBlue,
                    size: 52,
                    detents: [0.0]
                )
                RetroKnob(
                    value: $viewModel.dsp.noise,
                    title: "NOISE",
                    accentColor: Porta.noisePurple,
                    size: 52,
                    detents: [0.0]
                )
            }
            .padding(.horizontal, 4)

            // Bandwidth slider
            BandwidthSlider(value: $viewModel.dsp.bandwidth)
                .padding(.horizontal, 8)
                .padding(.top, 4)
        }
        .padding(10)
        .portaPanel(cornerRadius: 10)
    }
}

/// A horizontal slider styled as a vintage bandwidth control.
struct BandwidthSlider: View {
    @Binding var value: Double

    @GestureState private var isDragging = false

    var body: some View {
        VStack(spacing: 5) {
            Text("BANDWIDTH")
                .font(Porta.labelFont)
                .foregroundStyle(Porta.label)
                .tracking(1)

            GeometryReader { geo in
                let trackHeight: CGFloat = 6
                let thumbSize: CGFloat = 18

                ZStack(alignment: .leading) {
                    // Track background
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [Color(white: 0.22), Color(white: 0.30), Color(white: 0.22)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: trackHeight)
                        .shadow(color: .black.opacity(0.3), radius: 1, y: 1)

                    // Filled portion
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [Porta.bezel.opacity(0.5), Porta.bezel.opacity(0.3)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: value * geo.size.width, height: trackHeight)

                    // Scale marks
                    ForEach(0..<11, id: \.self) { i in
                        let x = Double(i) / 10.0 * geo.size.width
                        Rectangle()
                            .fill(Porta.label.opacity(i % 5 == 0 ? 0.4 : 0.2))
                            .frame(width: 1, height: i % 5 == 0 ? 10 : 6)
                            .position(x: x, y: geo.size.height / 2)
                    }

                    // Thumb
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [Color(white: 0.75), Color(white: 0.45)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: thumbSize, height: thumbSize + 4)
                        .shadow(color: Porta.deepShadow, radius: 2, y: 1)
                        .overlay(
                            // Grip line
                            Rectangle()
                                .fill(Color(white: 0.35))
                                .frame(width: thumbSize * 0.5, height: 1)
                        )
                        .position(
                            x: value * (geo.size.width - thumbSize) + thumbSize / 2,
                            y: geo.size.height / 2
                        )
                        .scaleEffect(isDragging ? 1.1 : 1.0)
                        .animation(.spring(response: 0.2), value: isDragging)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($isDragging) { _, state, _ in state = true }
                        .onChanged { gesture in
                            let newValue = min(max(0, gesture.location.x / geo.size.width), 1)
                            value = newValue
                        }
                )
            }
            .frame(height: 26)
        }
    }
}
