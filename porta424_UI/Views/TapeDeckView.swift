//
//  TapeDeckView.swift
//  porta424_UI
//
//  Created by John Clem on 10/22/25.
//

import SwiftUI
import Combine

struct TapeDeckView: View {
    @ObservedObject private var audio = TimecodeAudioEngine.shared
    @State private var reelRotation: Double = 0
    @State private var isDragging = false
    
    private let timer = Timer.publish(every: 0.016, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            PortaColor.background.ignoresSafeArea()
            
            VStack(spacing: 32) {
                // Tape Label
                Text("TAPE 30 01")
                    .font(PortaFont.tapeLabel())
                    .foregroundColor(.white.opacity(0.8))
                
                // Reels
                ReelAssemblyView(rotation: reelRotation)
                    .frame(height: 260)
                    .onReceive(timer) { _ in
                        let state = audio.transportState
                        let deltaTime = 0.016
                        
                        // RPM per state
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
                        
                        // Convert RPM to deg per tick
                        let degreesPerSecond = 360.0 * targetRPM / 60.0
                        let step = degreesPerSecond * (deltaTime * 60.0)
                        
                        withAnimation(.linear(duration: deltaTime)) {
                            reelRotation += step
                        }
                    }
                
                Text(String(describing: audio.transportState).uppercased())
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .scale))
                    .id(audio.transportState)
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: audio.transportState)
                
                // Track Pots
                HStack(alignment: .bottom, spacing: 24) {
                    ForEach(0..<4, id: \.self) { i in
                        VStack(spacing: 8) {
                            // Label
                            Text("TRK \(i+1)")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(.white.opacity(0.7))

                            // Vertical slider
                            Slider(value: Binding(
                                get: { Double(audio.trackGains[i]) },
                                set: { audio.trackGains[i] = Float($0) }
                            ), in: 0.0...1.5)
                            .rotationEffect(.degrees(-90))
                            .frame(width: 220) // long axis after rotation
                            .padding(.vertical, 6)
                            .tint(PortaColor.accentOrange)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(.white.opacity(0.2), lineWidth: 1)
                            )

                            // Value readout
                            Text(String(format: "%.1f", audio.trackGains[i]))
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .frame(width: 56)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 4)
                
                // VU Meters
                HStack(spacing: 12) {
                    ForEach(0..<4) { i in
                        VUMeter(level: CGFloat(audio.trackLevels[i]))
                    }
                }
                .frame(height: 120)
                .padding(.horizontal, 24)
                
                Spacer()
                
                // Transport
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
                .padding(.top, 12)
                .scaleEffect(1.15)
            }
            .padding(.bottom, 16)
        }
    }
}

