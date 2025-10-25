import SwiftUI

struct Knob: View {
    var label: String
    @Binding var value: Double

    private let minAngle: Angle = .degrees(-140)
    private let maxAngle: Angle = .degrees(140)

    @State private var dragStartValue: Double = 0

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.95), Color(white: 0.76)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.black.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(radius: 2, x: 0, y: 1)

                Circle()
                    .stroke(Color.black.opacity(0.12), lineWidth: 6)

                Capsule()
                    .fill(Color.black.opacity(0.8))
                    .frame(width: 3, height: 16)
                    .offset(y: -22)
                    .rotationEffect(angle(for: value))
            }
            .frame(width: 64, height: 64)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let delta = -gesture.translation.height / 150
                        value = (dragStartValue + delta).clamped(to: 0...1)
                    }
                    .onEnded { _ in
                        dragStartValue = value
                    }
            )
            .onAppear {
                dragStartValue = value
            }

            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
    }

    private func angle(for value: Double) -> Angle {
        let span = maxAngle.degrees - minAngle.degrees
        return .degrees(minAngle.degrees + (span * value))
    }
}

struct MixerStrip: View {
    var title: String
    @Binding var value: Double

    var body: some View {
        VStack(spacing: 8) {
            Fader(value: $value)
                .frame(width: 68, height: 150)

            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) level")
        .accessibilityValue("\(Int(value * 100)) percent")
    }
}

struct Fader: View {
    @Binding var value: Double

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(white: 0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.black.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)

            VStack {
                Spacer(minLength: 8)
                ZStack {
                    Capsule()
                        .fill(Color(white: 0.82))
                        .frame(width: 8)
                    VStack(spacing: 12) {
                        ForEach(0..<9) { _ in
                            Rectangle()
                                .fill(Color.black.opacity(0.25))
                                .frame(width: 8, height: 1)
                        }
                    }
                }
                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity)

            GeometryReader { geometry in
                let height = geometry.size.height
                let y = (1 - value).clamped(to: 0...1) * (height - 24)

                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.98), Color(white: 0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.black.opacity(0.2), lineWidth: 1)
                    )
                    .frame(width: 36, height: 24)
                    .position(x: geometry.size.width / 2, y: y + 12)
                    .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 2)
                    .gesture(
                        DragGesture()
                            .onChanged { drag in
                                let position = (drag.location.y - 12) / (height - 24)
                                value = (1 - position).clamped(to: 0...1)
                            }
                    )
            }
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
