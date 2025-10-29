import SwiftUI

struct TransportSectionView: View {
    @EnvironmentObject var viewModel: Porta424ViewModel

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                CassetteWindow()
                VStack {
                    Text("METERS 1–4")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach(0..<4) { index in
                            VUSegmentMeter(value: viewModel.meters[index])
                        }
                    }
                }
            }

            HStack(spacing: 16) {
                CounterView(text: viewModel.counterString)
                VStack(spacing: 6) {
                    Text("PITCH")
                        .font(.caption2)
                    Slider(value: $viewModel.master.pitch, in: 0...1)
                        .frame(width: 160)
                }
                VStack(spacing: 6) {
                    Text("PHONES")
                        .font(.caption2)
                    RotaryKnob(value: $viewModel.master.phonesLevel, title: "", size: 44)
                }
            }

            HStack(spacing: 18) {
                TransportButton(systemName: "backward.end.fill", label: "ZERO") {
                    viewModel.engineZero()
                }
                TransportButton(systemName: "backward.fill", label: "REW") {
                    viewModel.engineREW()
                }
                TransportButton(systemName: "stop.fill", label: "STOP") {
                    viewModel.engineStop()
                }
                TransportButton(
                    systemName: viewModel.transport.isPaused ? "pause.fill" : "play.fill",
                    label: viewModel.transport.isPaused ? "PAUSE" : "PLAY"
                ) {
                    viewModel.enginePlayPause()
                }
                TransportButton(systemName: "forward.fill", label: "FFWD") {
                    viewModel.engineFF()
                }
                TransportButton(
                    systemName: viewModel.transport.isRecording ? "record.circle.fill" : "record.circle",
                    tint: .red,
                    label: "RECORD"
                ) {
                    viewModel.engineRecord()
                }
            }
            .padding(.top, 6)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.12, green: 0.20, blue: 0.32))
                .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 4)
        )
        .foregroundStyle(.white)
    }
}

struct TransportButton: View {
    var systemName: String
    var tint: Color = .white
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemName)
                    .font(.title2)
                    .foregroundStyle(tint)
                Text(label)
                    .font(.caption2)
            }
            .frame(width: 64, height: 54)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.3))
            )
        }
        .buttonStyle(.plain)
    }
}

struct CassetteWindow: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.7))
            HStack(spacing: 26) {
                Reel()
                Reel()
            }
        }
        .frame(width: 160, height: 90)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.15))
        )
    }

    struct Reel: View {
        var body: some View {
            ZStack {
                Circle()
                    .strokeBorder(Color.gray.opacity(0.7), lineWidth: 2)
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 44, height: 44)
                ForEach(0..<6) { index in
                    Capsule()
                        .fill(Color.gray.opacity(0.6))
                        .frame(width: 4, height: 12)
                        .offset(y: -16)
                        .rotationEffect(.degrees(Double(index) / 6.0 * 360))
                }
            }
            .frame(width: 60, height: 60)
        }
    }
}

struct CounterView: View {
    var text: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.85))
            Text(text)
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.red)
                .shadow(color: Color.red.opacity(0.6), radius: 6)
        }
        .frame(width: 130, height: 52)
    }
}
