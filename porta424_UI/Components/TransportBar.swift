//
//  TransportBar.swift
//  porta424_UI
//
//  Created by John Clem on 10/22/25.
//

import SwiftUI

struct TransportBar: View {
    @Binding var isPlaying: Bool
    @Binding var isRecording: Bool
    @Binding var transportState: TimecodeAudioEngine.TransportState
    @Binding var isPaused: Bool
    
    let onRewind: () -> Void
    let onFastForward: () -> Void
    let onPlay: () -> Void
    let onPause: () -> Void
    let onStop: () -> Void
    let onRecord: () -> Void

    var body: some View {
        let isPlayingActive = transportState == .playing || transportState == .recording
        let isRecordingActive = transportState == .recording
        let isFFActive = transportState == .fastForward
        let isRWActive = transportState == .rewinding

        HStack(spacing: 16) {
            TransportButton(icon: "record.circle.fill", action: onRecord, isActive: isRecordingActive, color: .red)
            TransportButton(icon: "play.fill", action: onPlay, isActive: isPlayingActive)
            TransportButton(icon: "backward.fill", action: onRewind, isActive: isRWActive)
            TransportButton(icon: "forward.fill", action: onFastForward, isActive: isFFActive)
            TransportButton(icon: "stop.fill", action: onStop)
            TransportButton(icon: "pause.fill", action: onPause, isActive: isPaused)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(PortaColor.surface)
        .cornerRadius(16)
        .shadow(radius: 8, y: 4)
    }
}

struct TransportButton: View {
    let icon: String
    let action: () -> Void
    var isActive = false
    var color: Color = .white

    var body: some View {
        Button(action: {
            action()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(isActive ? PortaColor.accentOrange : .white.opacity(0.7))
                .frame(width: 68, height: 68)
                .background(isActive ? color.opacity(0.2) : Color.clear)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1.5))
        }
        .scaleEffect(isActive ? 1.1 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isActive)
    }
}

