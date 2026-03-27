import SwiftUI

/// The main tape deck interface view.
/// Arranged in landscape orientation matching the concept art:
/// Left section: VU meters + tape counter + input/master faders
/// Center: Cassette window + transport controls
/// Right section: DSP params + presets
struct TapeDeckView: View {
    @Environment(TapeDeckViewModel.self) var viewModel

    var body: some View {
        GeometryReader { geo in
            let isCompact = geo.size.width < 700

            ZStack {
                // Chassis background
                chassisBackground

                if isCompact {
                    compactLayout
                } else {
                    landscapeLayout
                }
            }
            .ignoresSafeArea(edges: .all)
            .onChange(of: viewModel.dsp) { _, _ in
                viewModel.syncDSP()
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }

    // MARK: - Landscape Layout (Primary - matches concept art)

    private var landscapeLayout: some View {
        HStack(spacing: 0) {
            // Left panel: Title + VU Meters + Counter + Faders
            leftPanel
                .frame(maxWidth: .infinity)

            // Center panel: Cassette + Transport
            centerPanel
                .frame(maxWidth: .infinity)

            // Right panel: DSP Params + Presets
            rightPanel
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Compact Layout (Portrait fallback)

    private var compactLayout: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                headerBar

                HStack(spacing: 12) {
                    VUMeterView(value: viewModel.meterL, channel: "L")
                    CassetteView(
                        transportMode: viewModel.transportMode,
                        tapePosition: viewModel.tapePosition
                    )
                    VUMeterView(value: viewModel.meterR, channel: "R")
                }

                TapeCounterView(
                    counterText: viewModel.counterString,
                    isRunning: viewModel.isTransportActive,
                    onReset: { viewModel.resetCounter() }
                )

                TransportBar(viewModel: viewModel)

                HStack(spacing: 20) {
                    RetroFader(
                        value: Bindable(viewModel).dsp.inputGain,
                        label: "INPUT\nGAIN",
                        capColor: Porta.faderCapOrange,
                        height: 130,
                        meterValue: viewModel.meterL
                    )
                    .frame(width: 50)

                    DSPKnobsPanel(viewModel: viewModel)

                    RetroFader(
                        value: Bindable(viewModel).dsp.masterVolume,
                        label: "MASTER\nVOLUME",
                        capColor: Porta.faderCapGreen,
                        height: 130,
                        meterValue: viewModel.meterR
                    )
                    .frame(width: 50)
                }

                PresetPickerButton(viewModel: viewModel)
            }
            .padding(16)
        }
    }

    // MARK: - Left Panel

    private var leftPanel: some View {
        VStack(spacing: 12) {
            headerBar

            // VU Meters
            HStack(spacing: 12) {
                VUMeterView(value: viewModel.meterL, channel: "L")
                VUMeterView(value: viewModel.meterR, channel: "R")
            }
            .padding(8)
            .portaPanel(cornerRadius: 8)

            // Tape counter
            TapeCounterView(
                counterText: viewModel.counterString,
                isRunning: viewModel.isTransportActive,
                onReset: { viewModel.resetCounter() }
            )

            Spacer()

            // Faders
            HStack(spacing: 16) {
                RetroFader(
                    value: Bindable(viewModel).dsp.inputGain,
                    label: "INPUT\nGAIN",
                    capColor: Porta.faderCapOrange,
                    height: 140,
                    meterValue: viewModel.meterL
                )
                .frame(width: 50)

                RetroFader(
                    value: Bindable(viewModel).dsp.masterVolume,
                    label: "MASTER\nVOLUME",
                    capColor: Porta.faderCapGreen,
                    height: 140,
                    meterValue: viewModel.meterR
                )
                .frame(width: 50)
            }
            .padding(.bottom, 8)
        }
    }

    // MARK: - Center Panel

    private var centerPanel: some View {
        VStack(spacing: 14) {
            Spacer()

            // Cassette window
            CassetteView(
                transportMode: viewModel.transportMode,
                tapePosition: viewModel.tapePosition
            )
            .padding(8)
            .portaPanel(cornerRadius: 10)

            // Transport buttons
            TransportBar(viewModel: viewModel)

            Spacer()
        }
    }

    // MARK: - Right Panel

    private var rightPanel: some View {
        VStack(spacing: 12) {
            // DSP Params knobs
            DSPKnobsPanel(viewModel: viewModel)

            Spacer()

            // Presets button
            PresetPickerButton(viewModel: viewModel)

            Spacer()
        }
    }

    // MARK: - Shared Components

    private var headerBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 1) {
                Text("PORTA424")
                    .font(Porta.titleFont)
                    .foregroundStyle(Porta.label)

                Text("PORTA DSP KIT")
                    .font(Porta.subtitleFont)
                    .foregroundStyle(Porta.labelLight)
                    .tracking(2)
            }

            Spacer()

            // Cassette icon + settings
            HStack(spacing: 10) {
                Image(systemName: "cassette.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Porta.label.opacity(0.5))

                // Settings placeholder
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14))
                    .foregroundStyle(Porta.label.opacity(0.4))
            }
        }
    }

    // MARK: - Background

    private var chassisBackground: some View {
        ZStack {
            // Main chassis color
            Porta.chassis
                .ignoresSafeArea()

            // Subtle texture grain
            Canvas { context, size in
                // Gentle noise texture
                for _ in 0..<300 {
                    let x = Double.random(in: 0..<size.width)
                    let y = Double.random(in: 0..<size.height)
                    let opacity = Double.random(in: 0.01...0.04)
                    context.fill(
                        Path(CGRect(x: x, y: y, width: 1, height: 1)),
                        with: .color(.black.opacity(opacity))
                    )
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Screw decorations in corners
            VStack {
                HStack {
                    Porta.Screw()
                    Spacer()
                    Porta.Screw()
                }
                Spacer()
                HStack {
                    Porta.Screw()
                    Spacer()
                    Porta.Screw()
                }
            }
            .padding(12)
        }
    }
}
