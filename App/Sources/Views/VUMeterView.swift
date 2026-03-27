import SwiftUI

/// A skeuomorphic analog VU meter with a swinging needle, dB markings,
/// and a red zone. Faithfully recreates the classic Tascam VU look.
struct VUMeterView: View {
    var value: Double          // 0...1 normalized level
    var channel: String = "L"  // "L" or "R"

    // Needle angle: -45° (silence) to +45° (full scale)
    private let needleMin: Double = -40
    private let needleMax: Double = 40

    private var needleAngle: Double {
        // VU meters have logarithmic-ish response
        let clamped = max(0, min(1, value))
        let curved = pow(clamped, 0.6) // slight log curve
        return needleMin + (needleMax - needleMin) * curved
    }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                // Meter face background
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(red: 0.96, green: 0.94, blue: 0.90))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color(white: 0.50), lineWidth: 1)
                    )

                // Scale markings
                VUScale()
                    .padding(.top, 6)
                    .padding(.horizontal, 4)

                // Needle
                VUNeedle(angle: needleAngle)
                    .animation(.interpolatingSpring(stiffness: 120, damping: 12), value: needleAngle)

                // "VU" label
                Text("VU")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Porta.label.opacity(0.6))
                    .offset(y: 22)
            }
            .frame(width: 100, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Channel label
            Text(channel)
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundStyle(Porta.label.opacity(0.7))
        }
    }
}

/// The curved scale markings of a VU meter.
struct VUScale: View {
    // dB markings from left to right
    private let markings: [(label: String, position: Double, isRed: Bool)] = [
        ("-20", 0.0, false),
        ("-10", 0.15, false),
        ("-7", 0.25, false),
        ("-5", 0.35, false),
        ("-3", 0.47, false),
        ("-1", 0.60, false),
        ("0", 0.72, false),
        ("+1", 0.80, true),
        ("+2", 0.87, true),
        ("+3", 0.95, true),
    ]

    var body: some View {
        GeometryReader { geo in
            // Scale arc area
            ForEach(Array(markings.enumerated()), id: \.offset) { _, mark in
                let x = mark.position * geo.size.width
                VStack(spacing: 1) {
                    Text(mark.label)
                        .font(.system(size: 5, weight: .medium))
                        .foregroundStyle(mark.isRed ? Porta.meterRed : Porta.label.opacity(0.7))
                    Rectangle()
                        .fill(mark.isRed ? Porta.meterRed : Porta.label.opacity(0.5))
                        .frame(width: 0.5, height: 6)
                }
                .position(x: x, y: 12)
            }

            // Red zone background
            Rectangle()
                .fill(Porta.meterRed.opacity(0.08))
                .frame(width: geo.size.width * 0.28, height: geo.size.height * 0.5)
                .position(x: geo.size.width * 0.86, y: geo.size.height * 0.3)
        }
    }
}

/// The physical needle of the VU meter.
struct VUNeedle: View {
    var angle: Double

    var body: some View {
        GeometryReader { geo in
            let pivot = CGPoint(x: geo.size.width / 2, y: geo.size.height + 10)
            let needleLength = geo.size.height + 5

            Path { path in
                let radians = (angle - 90) * .pi / 180
                let tip = CGPoint(
                    x: pivot.x + cos(radians) * needleLength,
                    y: pivot.y + sin(radians) * needleLength
                )
                path.move(to: pivot)
                path.addLine(to: tip)
            }
            .stroke(Color(white: 0.15), lineWidth: 1)

            // Pivot dot
            Circle()
                .fill(Color(white: 0.20))
                .frame(width: 5, height: 5)
                .position(pivot)
        }
    }
}
