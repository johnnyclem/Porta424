import SwiftUI

/// The full six-channel mixer board face of the Porta424 — a faithful recreation
/// of the TASCAM Portastudio 424 mkIII front panel, built from the same retro
/// controls (`RetroKnob`, `RetroFader`, `RetroTransportButton`) and warm cream
/// theme used across the rest of the app.
///
/// Layout (landscape — primary):
/// ```
/// ┌──────────────────────────────────────────────────────────────┐
/// │  TITLE        [Cassette]   [Tape Counter]      VU-L  VU-R  ✕  │
/// ├──────────────────────────────────────────────────────────────┤
/// │  CH1   CH2   CH3   CH4   CH5   CH6        ║   MASTER           │
/// │  trim  trim  ...                          ║                    │
/// │  EQ    EQ                                  ║   fader            │
/// │  fx    fx                                  ║                    │
/// │  pan   pan                                 ║                    │
/// │  fader fader                               ║                    │
/// ├──────────────────────────────────────────────────────────────┤
/// │  [transport]                       PITCH   POWER               │
/// └──────────────────────────────────────────────────────────────┘
/// ```
///
/// On compact widths the channel strips scroll horizontally so the board
/// remains usable on iPhone.
struct MixerBoardView: View {
    @Environment(TapeDeckViewModel.self) private var environmentModel

    /// Dismiss handler so the host can flip back to the tape-deck face.
    var onClose: () -> Void = {}

    var body: some View {
        @Bindable var viewModel = environmentModel

        ZStack {
            chassisBackground

            VStack(spacing: 10) {
                header(viewModel: viewModel)

                Divider()
                    .overlay(Porta.bezel.opacity(0.5))
                    .padding(.horizontal, 16)

                channelRow(viewModel: viewModel)

                Divider()
                    .overlay(Porta.bezel.opacity(0.5))
                    .padding(.horizontal, 16)

                bottomBar(viewModel: viewModel)
            }
            .padding(.vertical, 14)
        }
        .ignoresSafeArea(edges: .all)
        #if os(iOS)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        #endif
        .onChange(of: viewModel.dsp) { _, _ in
            viewModel.syncDSP()
        }
        .onChange(of: viewModel.channels) { _, _ in
            viewModel.syncMixer()
        }
        .onChange(of: viewModel.pitch) { _, _ in
            viewModel.syncMixer()
        }
    }

    // MARK: - Header

    private func header(viewModel: TapeDeckViewModel) -> some View {
        HStack(alignment: .center, spacing: 16) {
            // Title block
            VStack(alignment: .leading, spacing: 2) {
                Text("PORTASTUDIO 424")
                    .font(Porta.titleFont)
                    .foregroundStyle(Porta.label)
                HStack(spacing: 6) {
                    Text("mkIII")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(Porta.saturationOrange)
                    Text("· 6-CHANNEL MIXER")
                        .font(Porta.subtitleFont)
                        .tracking(2)
                        .foregroundStyle(Porta.labelLight)
                }
            }

            Spacer(minLength: 8)

            // Cassette window
            CassetteView(
                transportMode: viewModel.transportMode,
                tapePosition: viewModel.tapePosition
            )
            .frame(width: 150, height: 86)

            // Tape counter
            TapeCounterView(
                counterText: viewModel.counterString,
                isRunning: viewModel.isTransportActive,
                onReset: { viewModel.resetCounter() }
            )

            Spacer(minLength: 8)

            // Stereo VU meters
            HStack(spacing: 6) {
                VUMeterView(value: viewModel.meterL, channel: "L")
                    .frame(width: 78, height: 58)
                VUMeterView(value: viewModel.meterR, channel: "R")
                    .frame(width: 78, height: 58)
            }

            // Return to the tape-deck face
            Button {
                HapticEngine.buttonPress()
                onClose()
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "cassette")
                        .font(.system(size: 16, weight: .bold))
                    Text("DECK")
                        .font(.system(size: 8, weight: .heavy, design: .rounded))
                        .tracking(1)
                }
                .foregroundStyle(Porta.label)
                .frame(width: 46, height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Porta.chassis)
                        .shadow(color: Porta.softShadow, radius: 2, x: 0, y: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Porta.bezel.opacity(0.5), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
    }

    // MARK: - Channel Row

    private func channelRow(viewModel: TapeDeckViewModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 6) {
                ForEach(viewModel.channels.indices, id: \.self) { index in
                    MixerChannelStrip(viewModel: viewModel, index: index)
                }

                // Vertical bezel separating channels from master
                Rectangle()
                    .fill(Porta.bezel.opacity(0.4))
                    .frame(width: 1.5)
                    .padding(.vertical, 6)

                MixerMasterSection(viewModel: viewModel)
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Bottom Bar

    private func bottomBar(viewModel: TapeDeckViewModel) -> some View {
        HStack(alignment: .center, spacing: 18) {
            TransportBar(viewModel: viewModel)

            Spacer(minLength: 8)

            // Pitch control (varispeed — not bandwidth)
            RetroKnob(
                value: Bindable(viewModel).pitch,
                title: "PITCH",
                accentColor: Porta.flutterBlue,
                size: 46,
                detents: [0.5]
            )

            // Power / reset
            Button {
                HapticEngine.transportTap()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    viewModel.stop()
                    viewModel.resetCounter()
                }
            } label: {
                Text("POWER")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Porta.transportRed)
                            .shadow(color: Porta.deepShadow, radius: 2, x: 0, y: 2)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
    }

    // MARK: - Chassis

    private var chassisBackground: some View {
        ZStack {
            Porta.chassis
                .ignoresSafeArea()

            Porta.ChassisGrain(density: 300, seed: 4242)
                .ignoresSafeArea()

            VStack {
                HStack {
                    Porta.Screw(); Spacer(); Porta.Screw()
                }
                Spacer()
                HStack {
                    Porta.Screw(); Spacer(); Porta.Screw()
                }
            }
            .padding(12)
        }
    }
}

// MARK: - Channel Strip

/// A single vertical channel strip: trim, input source, 3-band EQ, two FX sends,
/// pan, record-arm, and the channel fader with its level meter.
private struct MixerChannelStrip: View {
    @Bindable var viewModel: TapeDeckViewModel
    let index: Int

    private var channel: ChannelState { viewModel.channels[index] }

    var body: some View {
        VStack(spacing: 7) {
            // Channel number
            Text("\(channel.id)")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(Porta.label)

            // TRIM
            RetroKnob(
                value: $viewModel.channels[index].trim,
                title: "TRIM",
                accentColor: Porta.saturationOrange,
                size: 38,
                detents: [0.5]
            )

            // Input source toggle
            ChannelSourceToggle(
                source: channel.source,
                action: { viewModel.toggleSource(channelIndex: index) }
            )

            // 3-band EQ
            VStack(spacing: 5) {
                RetroKnob(
                    value: $viewModel.channels[index].eqHigh,
                    title: "HIGH",
                    accentColor: Porta.flutterBlue,
                    size: 32,
                    detents: [0.5]
                )
                RetroKnob(
                    value: $viewModel.channels[index].eqMid,
                    title: "MID",
                    accentColor: Porta.noisePurple,
                    size: 32,
                    detents: [0.5]
                )
                RetroKnob(
                    value: $viewModel.channels[index].eqLow,
                    title: "LOW",
                    accentColor: Porta.wowGreen,
                    size: 32,
                    detents: [0.5]
                )
            }

            // FX sends
            HStack(spacing: 8) {
                RetroKnob(
                    value: $viewModel.channels[index].fx1Send,
                    title: "FX1",
                    accentColor: Porta.transportBlue,
                    size: 28
                )
                RetroKnob(
                    value: $viewModel.channels[index].fx2Send,
                    title: "FX2",
                    accentColor: Porta.transportBlue,
                    size: 28
                )
            }

            // PAN
            RetroKnob(
                value: $viewModel.channels[index].pan,
                title: "PAN",
                accentColor: Porta.transportOrange,
                size: 36,
                detents: [0.5]
            )

            // Record arm
            ChannelArmButton(
                isArmed: channel.isArmed,
                action: { viewModel.toggleArm(channelIndex: index) }
            )

            // Channel fader
            RetroFader(
                value: $viewModel.channels[index].level,
                label: "CH \(channel.id)",
                capColor: channel.isArmed ? Porta.transportRed : Porta.faderCapGreen,
                height: 130,
                meterValue: faderMeter
            )
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .frame(width: 60)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Porta.well.opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    channel.isArmed ? Porta.transportRed.opacity(0.6) : Porta.bezel.opacity(0.25),
                    lineWidth: channel.isArmed ? 1.5 : 0.5
                )
        )
    }

    /// Per-channel meter from engine track levels (ch 1–4), scaled by fader.
    private var faderMeter: Double {
        let track = (index < viewModel.trackMeters.count) ? viewModel.trackMeters[index] : 0
        let base = track > 0.001 ? track : (viewModel.meterL + viewModel.meterR) / 2
        return max(0, min(1, base * channel.level))
    }
}

// MARK: - Master Section

private struct MixerMasterSection: View {
    @Bindable var viewModel: TapeDeckViewModel

    var body: some View {
        VStack(spacing: 7) {
            Porta.SectionLabel(text: "MASTER")

            RetroFader(
                value: $viewModel.dsp.masterVolume,
                label: "L–R",
                capColor: Porta.faderCapOrange,
                height: 188,
                meterValue: viewModel.isTransportActive
                    ? (viewModel.meterL + viewModel.meterR) / 2
                    : 0
            )

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .frame(width: 78)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Porta.well.opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Porta.bezel.opacity(0.3), lineWidth: 0.5)
        )
    }
}

// MARK: - Small Controls

/// MIC / LINE input source selector for a channel.
private struct ChannelSourceToggle: View {
    let source: ChannelSource
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                segment(title: "MIC", isOn: source == .mic)
                segment(title: "LINE", isOn: source == .line)
            }
            .frame(height: 16)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Porta.well.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Porta.bezel.opacity(0.4), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func segment(title: String, isOn: Bool) -> some View {
        Text(title)
            .font(.system(size: 7, weight: .heavy, design: .rounded))
            .foregroundStyle(isOn ? .white : Porta.labelLight)
            .frame(maxWidth: .infinity)
            .frame(height: 16)
            .background(
                RoundedRectangle(cornerRadius: 2)
                    .fill(isOn ? Porta.transportBlue : Color.clear)
                    .padding(1)
            )
    }
}

/// Per-channel record-arm button. Glows red and breathes while armed.
private struct ChannelArmButton: View {
    let isArmed: Bool
    let action: () -> Void

    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Circle()
                    .fill(isArmed ? Porta.transportRed : Porta.meterOff)
                    .frame(width: 8, height: 8)
                    .shadow(color: isArmed ? Porta.transportRed.opacity(0.7) : .clear,
                            radius: isArmed ? 3 : 0)
                Text("REC")
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .foregroundStyle(isArmed ? Porta.transportRed : Porta.labelLight)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isArmed ? Porta.transportRed.opacity(0.12) : Porta.chassis)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(
                        isArmed ? Porta.transportRed.opacity(0.7) : Porta.bezel.opacity(0.4),
                        lineWidth: isArmed ? 1 : 0.5
                    )
            )
            .scaleEffect(isArmed && pulse ? 1.06 : 1.0)
        }
        .buttonStyle(.plain)
        .onChange(of: isArmed) { _, armed in
            pulse = armed
        }
        .animation(
            isArmed ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true) : .default,
            value: pulse
        )
    }
}

#if DEBUG
#Preview("Mixer Board") {
    MixerBoardView()
        .environment(TapeDeckViewModel())
}
#endif
