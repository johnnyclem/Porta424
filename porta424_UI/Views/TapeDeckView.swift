//
//  TapeDeckView.swift
//  porta424_UI
//
//  Created by John Clem on 10/22/25.
//

import SwiftUI
import Combine

// MARK: - CassetteTapeView (compact, portrait-friendly)
private struct CassetteTapeView: View {
    let rotation: Double
    let title: String

    var body: some View {
        ZStack {
            // Body
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [Color.black.opacity(0.9), Color.black.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

            VStack(spacing: 8) {
                // Label strip
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(white: 0.95))
                    .frame(height: 28)
                    .overlay(
                        HStack {
                            Text(title)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.black.opacity(0.8))
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                    )
                    .padding(.horizontal, 10)

                // Window with spools
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )

                    HStack(spacing: 36) {
                        spool
                        Capsule()
                            .fill(Color.cyan.opacity(0.5))
                            .frame(width: 56, height: 6)
                            .blur(radius: 0.5)
                        spool
                    }
                    .padding(.horizontal, 22)
                }
                .frame(height: 64)
                .padding(.horizontal, 10)

                // Screws row
                HStack { spacerScrew; Spacer(); spacerScrew }
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
            }
            .padding(.vertical, 10)
        }
        .frame(height: 140)
    }

    private var spool: some View {
        ZStack {
            Circle()
                .fill(Color.gray.opacity(0.15))
                .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
                .frame(width: 60, height: 60)
            Circle()
                .fill(Color.black)
                .frame(width: 18, height: 18)
            // simple spokes
            ForEach(0..<6) { i in
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 2, height: 18)
                    .offset(y: -20)
                    .rotationEffect(.degrees(Double(i) * 60))
            }
        }
        .rotationEffect(.degrees(rotation))
    }

    private var spacerScrew: some View {
        Circle()
            .fill(Color.black.opacity(0.9))
            .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
            .frame(width: 10, height: 10)
    }
}

struct TapeDeckView: View {
    @ObservedObject private var audio = TimecodeAudioEngine.shared
    @State private var reelRotation: Double = 0

    private let timer = Timer.publish(every: 0.016, on: .main, in: .common).autoconnect()

    // MARK: - Layout helpers
    private var horizontalPadding: CGFloat { 16 }

    var body: some View {
        ZStack {
            PortaColor.background.ignoresSafeArea()

            VStack(spacing: 12) {
                // Cassette Header
                CassetteTapeView(rotation: reelRotation, title: "V.N")
                    .padding(.horizontal, horizontalPadding)
                    .onReceive(timer) { _ in
                        updateRotation()
                    }

                // Timecode / State row
                HStack(alignment: .lastTextBaseline) {
                    Text(audio.displayTimecode)
                        .font(.system(size: 28, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white)
                        .opacity(0.9)
                        .accessibilityLabel("Timecode")
                    Spacer()
                    Text(String(describing: audio.transportState).uppercased())
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .id(audio.transportState)
                        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: audio.transportState)
                }
                .padding(.horizontal, horizontalPadding)

                // Faders 2x2 grid (portrait-optimized)
                Grid(alignment: .center, horizontalSpacing: 18, verticalSpacing: 8) {
                    GridRow {
                        fader(index: 0)
                        fader(index: 1)
                    }
                    GridRow {
                        fader(index: 2)
                        fader(index: 3)
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 4)

                // VU Meters row
                HStack(spacing: 12) {
                    ForEach(0..<4) { i in
                        VUMeter(level: CGFloat(audio.trackLevels[i]))
                    }
                }
                .frame(height: 80)
                .padding(.horizontal, horizontalPadding)

                Spacer(minLength: 8)

                // Transport with prominent Record
                TransportBar(
                    isPlaying: $audio.isPlaying,
                    isRecording: $audio.isRecording,
                    transportState: $audio.transportState,
                    isPaused: $audio.isPaused,
                    onRewind: { audio.rewind() },
                    onFastForward: { audio.fastForward() },
                    onPlay: { audio.play() },
                    onPause: { audio.pause() },
                    onStop: { audio.stop() },
                    onRecord: { audio.record() }
                )
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, 8)
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Subviews
    private func fader(index i: Int) -> some View {
        VStack(spacing: 6) {
            Text("TRK \(i+1)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))

            Slider(value: Binding(
                get: { Double(audio.trackGains[i]) },
                set: { audio.trackGains[i] = Float($0) }
            ), in: 0.0...1.5)
            .rotationEffect(.degrees(-90))
            .frame(width: 160)
            .padding(.vertical, 4)
            .tint(PortaColor.accentOrange)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.white.opacity(0.2), lineWidth: 1)
            )

            Text(String(format: "%.1f", audio.trackGains[i]))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Rotation update
    private func updateRotation() {
        let state = audio.transportState
        let deltaTime = 0.016
        let targetRPM: Double
        switch state {
        case .playing: targetRPM = 3.0
        case .recording: targetRPM = 3.0
        case .fastForward: targetRPM = 12.0
        case .rewinding: targetRPM = -12.0
        case .stopped: targetRPM = 0.0
        case .pausedPlayback: targetRPM = 0.0
        case .pausedRecording: targetRPM = 0.0
        }
        let degreesPerSecond = 360.0 * targetRPM / 60.0
        let step = degreesPerSecond * (deltaTime * 60.0)
        withAnimation(.linear(duration: deltaTime)) {
            reelRotation += step
        }
    }
}

// MARK: - Preview
#Preview {
    TapeDeckView()
        .preferredColorScheme(.dark)
}
