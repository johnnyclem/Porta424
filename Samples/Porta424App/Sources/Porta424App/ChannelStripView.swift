import SwiftUI

struct ChannelStripView: View {
    @Binding var channel: Channel

    var body: some View {
        VStack(spacing: 10) {
            Text(channel.name)
                .font(.footnote.weight(.semibold))
                .padding(.top, 2)

            RotaryKnob(value: $channel.trim, title: "TRIM")
            HStack(spacing: 8) {
                RotaryKnob(value: $channel.hiEQ, title: "HI", size: 36)
                RotaryKnob(value: $channel.midEQ, title: "MID", size: 36)
                RotaryKnob(value: $channel.loEQ, title: "LOW", size: 36)
            }

            HStack(spacing: 8) {
                RotaryKnob(value: $channel.aux1, title: "FX1", size: 36)
                RotaryKnob(value: $channel.aux2, title: "FX2", size: 36)
                RotaryKnob(value: $channel.tapeCue, title: "CUE", size: 36)
            }

            RotaryKnob(value: $channel.pan, title: channel.isStereo ? "BAL" : "PAN", size: 40, detents: [0.5])

            HStack {
                VStack(spacing: 6) {
                    Toggle("L", isOn: $channel.assignL)
                        .toggleStyle(.button)
                    Toggle("R", isOn: $channel.assignR)
                        .toggleStyle(.button)
                }
                .font(.caption2)
                .frame(width: 42)

                VStack(spacing: 6) {
                    Toggle("MUTE", isOn: $channel.mute)
                        .toggleStyle(.button)
                    Toggle("SOLO", isOn: $channel.solo)
                        .toggleStyle(.button)
                }
                .font(.caption2)
            }

            VerticalFader(value: $channel.fader, label: "FADER")
                .frame(width: 64)

            if channel.index <= 4 {
                RecFunctionSwitch(channel: $channel)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.10, green: 0.18, blue: 0.28).opacity(0.9))
                .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 4)
        )
        .foregroundStyle(.white)
    }
}

struct RecFunctionSwitch: View {
    @Binding var channel: Channel

    var body: some View {
        VStack(spacing: 4) {
            Text("REC FUNCTION \(channel.name)")
                .font(.caption2)
                .opacity(0.8)
            Picker("", selection: $channel.recFunction) {
                ForEach(RecFunction.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .font(.caption2)
            Toggle("ARM", isOn: $channel.recArmed)
                .toggleStyle(.button)
                .font(.caption2)
                .tint(.red)
        }
        .padding(.top, 6)
    }
}
