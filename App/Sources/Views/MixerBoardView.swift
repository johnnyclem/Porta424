import SwiftUI

/// Portastudio 424–style six-channel mixer board.
///
/// Always vertically scrollable so faders + transport are reachable.
/// Wide layouts show all 6 strips; narrow layouts scroll strips horizontally.
struct MixerBoardView: View {
    @Environment(TapeDeckViewModel.self) private var environmentModel

    var onClose: () -> Void = {}

    var body: some View {
        @Bindable var viewModel = environmentModel

        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            let metrics = MixerLayoutMetrics(size: geo.size, isLandscape: isLandscape)

            ZStack {
                chassisBackground

                // Vertical scroll is the primary fix: portrait + short landscape
                // can always reach FX / PAN / REC / faders / transport.
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: metrics.sectionSpacing) {
                        header(viewModel: viewModel, metrics: metrics)
                            .padding(.horizontal, metrics.edgePadding)

                        Divider()
                            .overlay(Porta.bezel.opacity(0.45))
                            .padding(.horizontal, metrics.edgePadding)

                        channelRow(viewModel: viewModel, metrics: metrics)

                        Divider()
                            .overlay(Porta.bezel.opacity(0.45))
                            .padding(.horizontal, metrics.edgePadding)

                        bottomBar(viewModel: viewModel, metrics: metrics)
                            .padding(.horizontal, metrics.edgePadding)
                            .padding(.bottom, 12)
                    }
                    .padding(.top, metrics.topPadding)
                    // Extra bottom inset so transport clears home indicator while scrolling.
                    .padding(.bottom, metrics.bottomPadding + 24)
                    .frame(minWidth: geo.size.width)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .ignoresSafeArea(edges: .all)
        #if os(iOS)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        #endif
        .onChange(of: viewModel.dsp) { _, _ in viewModel.syncDSP() }
        .onChange(of: viewModel.channels) { _, _ in viewModel.syncMixer() }
        .onChange(of: viewModel.pitch) { _, _ in viewModel.syncMixer() }
    }

    // MARK: - Header

    private func header(viewModel: TapeDeckViewModel, metrics: MixerLayoutMetrics) -> some View {
        Group {
            if metrics.compactHeader {
                compactHeader(viewModel: viewModel, metrics: metrics)
            } else {
                fullHeader(viewModel: viewModel, metrics: metrics)
            }
        }
    }

    private func fullHeader(viewModel: TapeDeckViewModel, metrics: MixerLayoutMetrics) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("PORTASTUDIO 424")
                    .font(.system(size: metrics.titleSize, weight: .black, design: .rounded))
                    .foregroundStyle(Porta.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                HStack(spacing: 6) {
                    Text("mkIII")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(Porta.saturationOrange)
                    Text("· 6-CH MIXER")
                        .font(Porta.subtitleFont)
                        .tracking(1.5)
                        .foregroundStyle(Porta.labelLight)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 4)

            CassetteView(
                transportMode: viewModel.transportMode,
                tapePosition: viewModel.tapePosition
            )
            .frame(width: metrics.cassetteSize.width, height: metrics.cassetteSize.height)

            TapeCounterView(
                counterText: viewModel.counterString,
                isRunning: viewModel.isTransportActive,
                onReset: { viewModel.resetCounter() }
            )
            .scaleEffect(metrics.counterScale)
            .frame(width: 140 * metrics.counterScale)

            Spacer(minLength: 4)

            HStack(spacing: 4) {
                VUMeterView(value: viewModel.meterL, channel: "L")
                VUMeterView(value: viewModel.meterR, channel: "R")
            }
            .frame(width: metrics.vuSize.width, height: metrics.vuSize.height)

            deckButton
        }
    }

    private func compactHeader(viewModel: TapeDeckViewModel, metrics: MixerLayoutMetrics) -> some View {
        VStack(spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("PORTASTUDIO 424")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(Porta.label)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("mkIII  ·  MIXER")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Porta.labelLight)
                }
                Spacer()
                deckButton
            }

            HStack(spacing: 8) {
                CassetteView(
                    transportMode: viewModel.transportMode,
                    tapePosition: viewModel.tapePosition
                )
                .frame(width: 100, height: 58)

                TapeCounterView(
                    counterText: viewModel.counterString,
                    isRunning: viewModel.isTransportActive,
                    onReset: { viewModel.resetCounter() }
                )
                .scaleEffect(0.8)
                .frame(width: 120)

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    VUMeterView(value: viewModel.meterL, channel: "L")
                    VUMeterView(value: viewModel.meterR, channel: "R")
                }
                .frame(width: 120, height: 44)
            }
        }
    }

    private var deckButton: some View {
        Button {
            HapticEngine.buttonPress()
            onClose()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "recordingtape")
                    .font(.system(size: 14, weight: .bold))
                Text("DECK")
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .tracking(1)
            }
            .foregroundStyle(Porta.label)
            .frame(width: 42, height: 42)
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

    // MARK: - Channel Row

    private func channelRow(viewModel: TapeDeckViewModel, metrics: MixerLayoutMetrics) -> some View {
        let stripCount = viewModel.channels.count
        let masterWidth = metrics.masterWidth
        let gap = metrics.stripSpacing
        let totalGaps = CGFloat(stripCount) * gap + 1.5
        let available = metrics.contentWidth - masterWidth - totalGaps - metrics.edgePadding * 2
        let idealStrip = available / CGFloat(max(stripCount, 1))
        let stripWidth = metrics.fitAllStrips
            ? max(metrics.minStripWidth, min(metrics.maxStripWidth, idealStrip))
            : metrics.scrollStripWidth

        let strips = HStack(alignment: .top, spacing: gap) {
            ForEach(viewModel.channels.indices, id: \.self) { index in
                MixerChannelStrip(
                    viewModel: viewModel,
                    index: index,
                    width: stripWidth,
                    metrics: metrics
                )
            }

            Rectangle()
                .fill(Porta.bezel.opacity(0.4))
                .frame(width: 1.5)
                .padding(.vertical, 4)

            MixerMasterSection(viewModel: viewModel, width: masterWidth, metrics: metrics)
        }
        .padding(.horizontal, metrics.edgePadding)

        return Group {
            if metrics.fitAllStrips {
                strips
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    strips
                }
            }
        }
    }

    // MARK: - Bottom Bar

    private func bottomBar(viewModel: TapeDeckViewModel, metrics: MixerLayoutMetrics) -> some View {
        HStack(alignment: .center, spacing: 12) {
            TransportBar(viewModel: viewModel)
                .scaleEffect(metrics.transportScale, anchor: .leading)
                .fixedSize(horizontal: true, vertical: true)

            Spacer(minLength: 4)

            RetroKnob(
                value: Bindable(viewModel).pitch,
                title: "PITCH",
                accentColor: Porta.flutterBlue,
                size: metrics.pitchKnobSize,
                detents: [0.5]
            )

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
    }

    // MARK: - Chassis

    private var chassisBackground: some View {
        ZStack {
            Porta.chassis.ignoresSafeArea()
            Porta.ChassisGrain(density: 300, seed: 4242)
                .ignoresSafeArea()
            VStack {
                HStack { Porta.Screw(); Spacer(); Porta.Screw() }
                Spacer()
                HStack { Porta.Screw(); Spacer(); Porta.Screw() }
            }
            .padding(12)
        }
    }
}

// MARK: - Layout Metrics

private struct MixerLayoutMetrics {
    let size: CGSize
    let isLandscape: Bool

    var edgePadding: CGFloat { isLandscape ? 10 : 10 }
    var sectionSpacing: CGFloat { isLandscape ? 6 : 8 }
    var topPadding: CGFloat { isLandscape ? 6 : 8 }
    var bottomPadding: CGFloat { isLandscape ? 6 : 8 }

    var contentWidth: CGFloat { size.width }

    /// Use compact chrome whenever height is limited (all landscape phones) or width is narrow.
    var compactHeader: Bool {
        isLandscape || size.width < 700 || size.height < 780
    }

    var fitAllStrips: Bool { size.width >= 560 }

    var minStripWidth: CGFloat { isLandscape ? 52 : 50 }
    var maxStripWidth: CGFloat { isLandscape ? 78 : 70 }
    var scrollStripWidth: CGFloat { 58 }
    var masterWidth: CGFloat { isLandscape ? 72 : 68 }
    var stripSpacing: CGFloat { 4 }

    var titleSize: CGFloat { isLandscape ? 18 : 20 }
    var cassetteSize: CGSize {
        isLandscape ? CGSize(width: 108, height: 62) : CGSize(width: 120, height: 70)
    }
    var counterScale: CGFloat { isLandscape ? 0.82 : 0.9 }
    var vuSize: CGSize {
        isLandscape ? CGSize(width: 120, height: 46) : CGSize(width: 132, height: 50)
    }
    var transportScale: CGFloat { size.width < 780 ? 0.85 : 0.95 }
    var pitchKnobSize: CGFloat { isLandscape ? 36 : 40 }

    /// Compact knobs so a full strip + fader fits in one landscape viewport more often.
    var trimSize: CGFloat { isLandscape ? 30 : 34 }
    var eqSize: CGFloat { isLandscape ? 24 : 28 }
    var fxSize: CGFloat { isLandscape ? 22 : 24 }
    var panSize: CGFloat { isLandscape ? 26 : 30 }

    /// Fixed fader travel — not “fill remaining,” which blew past the screen.
    var faderHeight: CGFloat {
        if isLandscape { return 100 }
        return 120
    }

    var stripVSpacing: CGFloat { isLandscape ? 3 : 5 }
}

// MARK: - Channel Strip

private struct MixerChannelStrip: View {
    @Bindable var viewModel: TapeDeckViewModel
    let index: Int
    var width: CGFloat = 60
    var metrics: MixerLayoutMetrics

    private var channel: ChannelState { viewModel.channels[index] }

    var body: some View {
        VStack(spacing: metrics.stripVSpacing) {
            Text("\(channel.id)")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(Porta.label)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Porta.chassisDark.opacity(0.5)))

            RetroKnob(
                value: $viewModel.channels[index].trim,
                title: "TRIM",
                accentColor: Porta.saturationOrange,
                size: metrics.trimSize,
                detents: [0.5]
            )

            ChannelSourceToggle(
                source: channel.source,
                action: { viewModel.toggleSource(channelIndex: index) }
            )

            VStack(spacing: metrics.isLandscape ? 2 : 3) {
                RetroKnob(
                    value: $viewModel.channels[index].eqHigh,
                    title: "HIGH",
                    accentColor: Porta.flutterBlue,
                    size: metrics.eqSize,
                    detents: [0.5]
                )
                RetroKnob(
                    value: $viewModel.channels[index].eqMid,
                    title: "MID",
                    accentColor: Porta.noisePurple,
                    size: metrics.eqSize,
                    detents: [0.5]
                )
                RetroKnob(
                    value: $viewModel.channels[index].eqLow,
                    title: "LOW",
                    accentColor: Porta.wowGreen,
                    size: metrics.eqSize,
                    detents: [0.5]
                )
            }

            HStack(spacing: 2) {
                RetroKnob(
                    value: $viewModel.channels[index].fx1Send,
                    title: "FX1",
                    accentColor: Porta.transportBlue,
                    size: metrics.fxSize
                )
                RetroKnob(
                    value: $viewModel.channels[index].fx2Send,
                    title: "FX2",
                    accentColor: Porta.transportBlue,
                    size: metrics.fxSize
                )
            }

            RetroKnob(
                value: $viewModel.channels[index].pan,
                title: "PAN",
                accentColor: Porta.transportOrange,
                size: metrics.panSize,
                detents: [0.5]
            )

            ChannelArmButton(
                isArmed: channel.isArmed,
                action: { viewModel.toggleArm(channelIndex: index) }
            )

            RetroFader(
                value: $viewModel.channels[index].level,
                label: "",
                capColor: channel.isArmed ? Porta.transportRed : Porta.faderCapGreen,
                height: metrics.faderHeight,
                meterValue: faderMeter
            )
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 2)
        .frame(width: width, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Porta.well.opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    channel.isArmed ? Porta.transportRed.opacity(0.65) : Porta.bezel.opacity(0.28),
                    lineWidth: channel.isArmed ? 1.5 : 0.5
                )
        )
    }

    private var faderMeter: Double {
        let track = (index < viewModel.trackMeters.count) ? viewModel.trackMeters[index] : 0
        let base = track > 0.001 ? track : (viewModel.meterL + viewModel.meterR) / 2
        return max(0, min(1, base * channel.level))
    }
}

// MARK: - Master Section

private struct MixerMasterSection: View {
    @Bindable var viewModel: TapeDeckViewModel
    var width: CGFloat = 72
    var metrics: MixerLayoutMetrics

    var body: some View {
        VStack(spacing: 8) {
            Text("MASTER")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(Porta.sectionTitle)

            Spacer(minLength: 0)

            RetroFader(
                value: $viewModel.dsp.masterVolume,
                label: "L–R",
                capColor: Porta.faderCapOrange,
                height: metrics.faderHeight + 36,
                meterValue: (viewModel.meterL + viewModel.meterR) / 2
            )
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .frame(width: width)
        // Match channel strip intrinsic height (top-aligned).
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Porta.well.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Porta.bezel.opacity(0.35), lineWidth: 0.5)
        )
    }
}

// MARK: - Small Controls

private struct ChannelSourceToggle: View {
    let source: ChannelSource
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                segment(title: "MIC", isOn: source == .mic)
                segment(title: "LINE", isOn: source == .line)
            }
            .frame(height: 14)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Porta.well.opacity(0.7))
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
            .font(.system(size: 6, weight: .heavy, design: .rounded))
            .foregroundStyle(isOn ? .white : Porta.labelLight)
            .frame(maxWidth: .infinity)
            .frame(height: 14)
            .background(
                RoundedRectangle(cornerRadius: 2)
                    .fill(isOn ? Porta.transportBlue : Color.clear)
                    .padding(1)
            )
    }
}

private struct ChannelArmButton: View {
    let isArmed: Bool
    let action: () -> Void

    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Circle()
                    .fill(isArmed ? Porta.transportRed : Porta.meterOff)
                    .frame(width: 7, height: 7)
                    .shadow(
                        color: isArmed ? Porta.transportRed.opacity(0.7) : .clear,
                        radius: isArmed ? 3 : 0
                    )
                Text("REC")
                    .font(.system(size: 7.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(isArmed ? Porta.transportRed : Porta.labelLight)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
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
            .scaleEffect(isArmed && pulse ? 1.05 : 1.0)
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
