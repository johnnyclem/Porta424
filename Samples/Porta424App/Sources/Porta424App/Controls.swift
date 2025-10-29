import SwiftUI

struct RotaryKnob: View {
    @Binding var value: Double
    var title: String = ""
    var size: CGFloat = 48
    var detents: [Double] = [0.5]
    var showValue: Bool = false

    private let angleMin: Angle = .degrees(-140)
    private let angleMax: Angle = .degrees(140)

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(white: 0.23),
                                Color(white: 0.15)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: .black.opacity(0.7), radius: 3, x: 0, y: 2)

                ForEach(0..<21, id: \.self) { i in
                    let fraction = Double(i) / 20.0
                    Tick(angle: angle(for: fraction), long: i % 5 == 0 ? 8 : 4)
                        .stroke(i % 5 == 0 ? Color.white.opacity(0.5) : Color.gray.opacity(0.5), lineWidth: 1)
                }

                ForEach(detents, id: \.self) { value in
                    Tick(angle: angle(for: value), long: 10)
                        .stroke(Color.orange, lineWidth: 1.5)
                }

                Capsule()
                    .fill(.white)
                    .frame(width: 3, height: size * 0.32)
                    .offset(y: -size * 0.16)
                    .rotationEffect(angle(for: self.value))
                    .shadow(radius: 1)
            }
            .frame(width: size, height: size)
            .gesture(knobGesture)
            .accessibilityValue(Text("\(Int(value * 100)) percent"))

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if showValue {
                Text(String(format: "%.2f", value))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func angle(for value: Double) -> Angle {
        Angle(degrees: angleMin.degrees + (angleMax.degrees - angleMin.degrees) * value)
    }

    private var knobGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                let delta = (-gesture.translation.height + gesture.translation.width) / 200.0
                value = max(0, min(1, value + delta))
            }
    }

    struct Tick: Shape {
        var angle: Angle
        var long: CGFloat = 6

        func path(in rect: CGRect) -> Path {
            var path = Path()
            let radius = min(rect.width, rect.height) / 2.0
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radians = CGFloat(angle.radians)
            let inner = CGPoint(
                x: center.x + cos(radians) * (radius - long - 4),
                y: center.y + sin(radians) * (radius - long - 4)
            )
            let outer = CGPoint(
                x: center.x + cos(radians) * (radius - 4),
                y: center.y + sin(radians) * (radius - 4)
            )
            path.move(to: inner)
            path.addLine(to: outer)
            return path
        }
    }
}

struct VerticalFader: View {
    @Binding var value: Double
    var label: String = ""
    var height: CGFloat = 170

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geometry in
                let trackWidth: CGFloat = 6
                ZStack {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [.gray.opacity(0.45), .black.opacity(0.5)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: trackWidth)
                        .padding(.horizontal, (geometry.size.width - trackWidth) / 2)

                    VStack {
                        ForEach(0..<11) { index in
                            Rectangle()
                                .fill(index % 5 == 0 ? Color.white.opacity(0.8) : Color.white.opacity(0.4))
                                .frame(width: index % 5 == 0 ? geometry.size.width * 0.6 : geometry.size.width * 0.4, height: 1)
                            Spacer()
                        }
                    }

                    let y = (1 - value) * (geometry.size.height - 24)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [Color(white: 0.8), Color(white: 0.3)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: geometry.size.width * 0.8, height: 24)
                        .shadow(radius: 3, y: 1)
                        .position(x: geometry.size.width / 2, y: y + 12)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { gesture in
                                    let value = 1 - min(max(0, gesture.location.y / geometry.size.height), 1)
                                    self.value = value
                                }
                        )
                }
            }
            .frame(height: height)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct VUSegmentMeter: View {
    var value: Double
    var segments: Int = 12

    var body: some View {
        VStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { index in
                let threshold = Double(index + 1) / Double(segments)
                Capsule()
                    .fill(segmentColor(threshold))
                    .opacity(value >= threshold ? 1 : 0.18)
                    .frame(width: 10, height: 8)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.black.opacity(0.7))
        )
    }

    private func segmentColor(_ threshold: Double) -> Color {
        if threshold > 0.85 { return .red }
        if threshold > 0.65 { return .yellow }
        return .green
    }
}
