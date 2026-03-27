import SwiftUI

/// A skeuomorphic rotary knob inspired by vintage Tascam portastudio controls.
/// Features realistic lighting, tick marks, and an accent-colored ring indicator.
struct RetroKnob: View {
    @Binding var value: Double
    var title: String = ""
    var accentColor: Color = Porta.saturationOrange
    var size: CGFloat = 56
    var detents: [Double] = []
    var tickCount: Int = 21

    // Rotation range: -140 to +140 degrees
    private let minAngle: Double = -140
    private let maxAngle: Double = 140

    @State private var lastDragValue: Double?
    @GestureState private var isDragging = false

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                // Outer ring indicator (accent color arc)
                Circle()
                    .trim(from: 0, to: CGFloat(value))
                    .stroke(
                        accentColor,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(minAngle - 90))
                    .frame(width: size + 10, height: size + 10)
                    .opacity(0.8)

                // Tick marks
                ForEach(0..<tickCount, id: \.self) { i in
                    let fraction = Double(i) / Double(tickCount - 1)
                    let isMajor = i % 5 == 0
                    tickMark(fraction: fraction, isMajor: isMajor)
                }

                // Knob body
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(white: 0.38),
                                Color(white: 0.22),
                                Color(white: 0.18)
                            ],
                            center: .init(x: 0.4, y: 0.35),
                            startRadius: 0,
                            endRadius: size * 0.5
                        )
                    )
                    .frame(width: size, height: size)
                    .shadow(color: Porta.deepShadow, radius: 4, x: 0, y: 3)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color(white: 0.45), Color(white: 0.15)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    )

                // Knurled texture ring
                ForEach(0..<24, id: \.self) { i in
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 1, height: size * 0.12)
                        .offset(y: -size * 0.38)
                        .rotationEffect(.degrees(Double(i) * 15))
                }

                // Position indicator line
                Capsule()
                    .fill(Color.white)
                    .frame(width: 2.5, height: size * 0.28)
                    .offset(y: -size * 0.18)
                    .rotationEffect(currentAngle)
                    .shadow(color: .white.opacity(0.3), radius: 2)
            }
            .frame(width: size + 14, height: size + 14)
            .contentShape(Circle().inset(by: -10))
            .gesture(knobDragGesture)
            .scaleEffect(isDragging ? 1.05 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isDragging)
            .accessibilityValue("\(Int(value * 100))%")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: value = min(1, value + 0.05)
                case .decrement: value = max(0, value - 0.05)
                @unknown default: break
                }
            }

            if !title.isEmpty {
                Text(title)
                    .font(Porta.labelFont)
                    .foregroundStyle(Porta.label)
                    .tracking(0.5)
            }
        }
    }

    private var currentAngle: Angle {
        .degrees(minAngle + (maxAngle - minAngle) * value)
    }

    private func tickMark(fraction: Double, isMajor: Bool) -> some View {
        let angle = Angle(degrees: minAngle + (maxAngle - minAngle) * fraction)
        let len: CGFloat = isMajor ? 6 : 3
        let radius = (size + 14) / 2
        return Capsule()
            .fill(isMajor ? Porta.label.opacity(0.6) : Porta.labelLight.opacity(0.4))
            .frame(width: isMajor ? 1.5 : 1, height: len)
            .offset(y: -(radius - len / 2 - 1))
            .rotationEffect(angle)
    }

    private var knobDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isDragging) { _, state, _ in
                state = true
            }
            .onChanged { gesture in
                let delta: Double
                if let last = lastDragValue {
                    let dy = -(gesture.translation.height - last)
                    delta = dy / 150.0
                } else {
                    delta = 0
                }
                lastDragValue = gesture.translation.height

                let newValue = max(0, min(1, value + delta))

                // Check for detent snap
                for detent in detents {
                    if abs(newValue - detent) < 0.03 && abs(value - detent) >= 0.03 {
                        value = detent
                        HapticEngine.knobDetent()
                        return
                    }
                }

                // Tick haptic every ~5% change
                let oldStep = Int(value * 20)
                let newStep = Int(newValue * 20)
                if oldStep != newStep {
                    HapticEngine.knobTick()
                }

                value = newValue
            }
            .onEnded { _ in
                lastDragValue = nil
            }
    }
}
