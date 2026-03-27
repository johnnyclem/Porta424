import SwiftUI

/// An animated cassette tape window with spinning reels and visible tape.
/// The reels spin at different speeds based on transport state, and the tape
/// "ribbon" adjusts width to simulate tape traveling between reels.
struct CassetteView: View {
    var transportMode: TransportMode
    var tapePosition: Double  // 0...1, how far along the tape we are

    @State private var reelRotation: Double = 0
    @State private var isAnimating = false

    // Reel speeds based on transport
    private var reelSpeed: Double {
        switch transportMode {
        case .playing, .recording: return 1.0
        case .fastForwarding: return 4.0
        case .rewinding: return -4.0
        case .paused: return 0.0
        case .stopped: return 0.0
        }
    }

    private var isSpinning: Bool {
        reelSpeed != 0
    }

    var body: some View {
        ZStack {
            // Cassette shell
            cassetteBody

            // Tape window
            ZStack {
                // Window background
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.55, green: 0.50, blue: 0.45),
                                Color(red: 0.50, green: 0.46, blue: 0.40),
                                Color(red: 0.45, green: 0.42, blue: 0.38)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 140, height: 82)

                // Inner window (where reels are visible)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(white: 0.88).opacity(0.6))
                    .frame(width: 120, height: 65)

                // Tape ribbon between reels
                tapeRibbon

                // Left reel (supply)
                CassetteReel(
                    rotation: reelRotation,
                    tapeRadius: leftReelRadius,
                    isSpinning: isSpinning
                )
                .offset(x: -30)

                // Right reel (takeup)
                CassetteReel(
                    rotation: -reelRotation,
                    tapeRadius: rightReelRadius,
                    isSpinning: isSpinning
                )
                .offset(x: 30)
            }
        }
        .onAppear { startReelTimer() }
        .onChange(of: transportMode) { _, _ in
            if isSpinning && !isAnimating {
                startReelTimer()
            }
        }
    }

    // Left reel gets smaller as tape plays (tape moves to right reel)
    private var leftReelRadius: CGFloat {
        let minR: CGFloat = 10
        let maxR: CGFloat = 22
        return maxR - CGFloat(tapePosition) * (maxR - minR)
    }

    private var rightReelRadius: CGFloat {
        let minR: CGFloat = 10
        let maxR: CGFloat = 22
        return minR + CGFloat(tapePosition) * (maxR - minR)
    }

    private var cassetteBody: some View {
        ZStack {
            // Outer shell
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.82, green: 0.78, blue: 0.72),
                            Color(red: 0.75, green: 0.71, blue: 0.65)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: Porta.deepShadow, radius: 6, x: 0, y: 4)

            // Label area at top
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(0.5))
                .frame(width: 130, height: 16)
                .offset(y: -38)

            // Bottom tape guide
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(white: 0.55))
                .frame(width: 100, height: 4)
                .offset(y: 42)
        }
        .frame(width: 170, height: 105)
    }

    private var tapeRibbon: some View {
        // Simple tape path from left reel to right reel through bottom guide
        Path { path in
            let leftCenter = CGPoint(x: 55, y: 41)
            let rightCenter = CGPoint(x: 115, y: 41)
            let bottomLeft = CGPoint(x: 50, y: 72)
            let bottomRight = CGPoint(x: 120, y: 72)

            path.move(to: CGPoint(x: leftCenter.x, y: leftCenter.y + leftReelRadius))
            path.addLine(to: bottomLeft)
            path.addLine(to: bottomRight)
            path.addLine(to: CGPoint(x: rightCenter.x, y: rightCenter.y + rightReelRadius))
        }
        .stroke(Color(red: 0.25, green: 0.18, blue: 0.12).opacity(0.7), lineWidth: 2)
        .frame(width: 170, height: 105)
        .offset(y: -12)
    }

    private func startReelTimer() {
        guard !isAnimating else { return }
        isAnimating = true
        Task { @MainActor in
            while isAnimating {
                try? await Task.sleep(for: .milliseconds(16)) // ~60fps
                if isSpinning {
                    reelRotation += reelSpeed * 3
                } else {
                    isAnimating = false
                }
            }
        }
    }
}

/// A single cassette reel with hub spokes and tape winding.
struct CassetteReel: View {
    var rotation: Double
    var tapeRadius: CGFloat
    var isSpinning: Bool

    private let hubRadius: CGFloat = 8
    private let spokeCount = 3

    var body: some View {
        ZStack {
            // Tape winding (brown circle)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.35, green: 0.25, blue: 0.15),
                            Color(red: 0.30, green: 0.20, blue: 0.12)
                        ],
                        center: .center,
                        startRadius: hubRadius,
                        endRadius: tapeRadius
                    )
                )
                .frame(width: tapeRadius * 2, height: tapeRadius * 2)

            // Hub
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(white: 0.70), Color(white: 0.50)],
                        center: .init(x: 0.4, y: 0.4),
                        startRadius: 0,
                        endRadius: hubRadius
                    )
                )
                .frame(width: hubRadius * 2, height: hubRadius * 2)
                .overlay(
                    Circle()
                        .strokeBorder(Color(white: 0.40), lineWidth: 0.5)
                )

            // Spokes (rotate with reel)
            ForEach(0..<spokeCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(white: 0.45))
                    .frame(width: 2, height: hubRadius * 1.4)
                    .offset(y: -hubRadius * 0.2)
                    .rotationEffect(.degrees(Double(i) * (360.0 / Double(spokeCount)) + rotation))
            }
        }
        .animation(isSpinning ? nil : .easeOut(duration: 0.5), value: isSpinning)
    }
}
