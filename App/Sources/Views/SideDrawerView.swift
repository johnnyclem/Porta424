import SwiftUI

/// The iPad side drawer — a persistent left panel (1/3 width) containing all utility
/// controls that don't fit on the main tape deck surface: DSP parameters, faders,
/// presets, and tape/sample browser.
struct SideDrawerView: View {
    @Bindable var viewModel: TapeDeckViewModel

    @State private var selectedTab: DrawerTab = .effects

    var body: some View {
        VStack(spacing: 0) {
            // Drawer header
            drawerHeader

            // Tab selector
            drawerTabBar

            // Scrollable content area
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    switch selectedTab {
                    case .effects:
                        effectsSection
                    case .presets:
                        presetsSection
                    case .tapes:
                        tapesSection
                    }
                }
                .padding(14)
            }

            Spacer(minLength: 0)

            // Faders always visible at bottom
            fadersSection
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
        }
        .background(drawerBackground)
    }

    // MARK: - Drawer Tabs

    enum DrawerTab: String, CaseIterable {
        case effects = "EFFECTS"
        case presets = "PRESETS"
        case tapes = "TAPES"

        var icon: String {
            switch self {
            case .effects: return "dial.medium"
            case .presets: return "list.bullet.rectangle.portrait"
            case .tapes: return "cassette"
            }
        }
    }

    // MARK: - Header

    private var drawerHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text("PORTA424")
                    .font(Porta.titleFont)
                    .foregroundStyle(Porta.label)
                Text("UTILITY DRAWER")
                    .font(Porta.subtitleFont)
                    .foregroundStyle(Porta.labelLight)
                    .tracking(2)
            }

            Spacer()

            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 14))
                .foregroundStyle(Porta.label.opacity(0.4))
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    // MARK: - Tab Bar

    private var drawerTabBar: some View {
        HStack(spacing: 0) {
            ForEach(DrawerTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedTab = tab
                    }
                    HapticEngine.buttonPress()
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 12))
                        Text(tab.rawValue)
                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                            .tracking(0.5)
                    }
                    .foregroundStyle(selectedTab == tab ? Porta.label : Porta.labelLight)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        selectedTab == tab
                            ? Porta.panel
                            : Color.clear
                    )
                    .overlay(alignment: .bottom) {
                        if selectedTab == tab {
                            Rectangle()
                                .fill(Porta.saturationOrange)
                                .frame(height: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .background(Porta.chassisDark.opacity(0.5))
    }

    // MARK: - Effects Tab

    private var effectsSection: some View {
        VStack(spacing: 14) {
            // DSP Knobs
            DSPKnobsPanel(viewModel: viewModel)

            // Additional info
            HStack {
                Porta.SectionLabel(text: "SIGNAL CHAIN")
                Spacer()
            }
            .padding(.horizontal, 4)

            // Signal flow diagram
            signalFlowView
        }
    }

    private var signalFlowView: some View {
        HStack(spacing: 6) {
            signalStage("INPUT", icon: "mic.fill", color: Porta.faderCapOrange)
            signalArrow
            signalStage("DSP", icon: "waveform", color: Porta.flutterBlue)
            signalArrow
            signalStage("TAPE", icon: "cassette.fill", color: Porta.saturationOrange)
            signalArrow
            signalStage("OUT", icon: "speaker.wave.2.fill", color: Porta.faderCapGreen)
        }
        .padding(10)
        .portaPanel(cornerRadius: 8)
    }

    private func signalStage(_ label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .rounded))
                .foregroundStyle(Porta.labelLight)
        }
        .frame(maxWidth: .infinity)
    }

    private var signalArrow: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(Porta.bezel)
    }

    // MARK: - Presets Tab

    private var presetsSection: some View {
        VStack(spacing: 12) {
            // Factory presets
            presetGroup("FACTORY PRESETS", presets: viewModel.factoryPresets)

            // User presets
            presetGroup("USER PRESETS", presets: viewModel.userPresets, showEmpty: true)

            // Save button
            Button {
                viewModel.saveCurrentAsPreset()
                HapticEngine.presetSelect()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Porta.transportGreen)
                    Text("SAVE CURRENT AS PRESET")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Porta.label)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Porta.panel)
                        .shadow(color: Porta.softShadow, radius: 2, y: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Porta.transportGreen.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func presetGroup(_ title: String, presets: [PresetItem], showEmpty: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Porta.SectionLabel(text: title)
                Spacer()
                Text("\(presets.count)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Porta.labelLight)
            }
            .padding(.horizontal, 4)

            if presets.isEmpty && showEmpty {
                Text("No user presets yet")
                    .font(.system(size: 11))
                    .foregroundStyle(Porta.labelLight)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .portaPanel(cornerRadius: 6)
            } else {
                VStack(spacing: 2) {
                    ForEach(presets) { preset in
                        drawerPresetRow(preset)
                    }
                }
                .portaPanel(cornerRadius: 8)
            }
        }
    }

    private func drawerPresetRow(_ preset: PresetItem) -> some View {
        Button {
            HapticEngine.presetSelect()
            viewModel.loadPreset(preset)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: preset.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(preset.isFactory ? Porta.saturationOrange : Porta.transportBlue)
                    .frame(width: 18)

                Text(preset.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Porta.label)
                    .lineLimit(1)

                Spacer()

                if preset.id == viewModel.activePresetId {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Porta.transportGreen)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                preset.id == viewModel.activePresetId
                    ? Porta.transportGreen.opacity(0.08)
                    : Color.clear
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tapes Tab

    private var tapesSection: some View {
        VStack(spacing: 14) {
            // Tape types
            tapeTypeSelector

            // Sample / parts browser placeholder
            sampleBrowser
        }
    }

    private var tapeTypeSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Porta.SectionLabel(text: "TAPE TYPE")
                Spacer()
            }
            .padding(.horizontal, 4)

            VStack(spacing: 2) {
                tapeTypeRow("Type I — Normal (Fe₂O₃)", icon: "cassette", selected: true)
                tapeTypeRow("Type II — Chrome (CrO₂)", icon: "cassette.fill", selected: false)
                tapeTypeRow("Type IV — Metal (Pure Metal)", icon: "opticaldisc.fill", selected: false)
            }
            .portaPanel(cornerRadius: 8)
        }
    }

    private func tapeTypeRow(_ name: String, icon: String, selected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(selected ? Porta.saturationOrange : Porta.labelLight)
                .frame(width: 18)
            Text(name)
                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Porta.label : Porta.labelLight)
                .lineLimit(1)
            Spacer()
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Porta.transportGreen)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(selected ? Porta.transportGreen.opacity(0.06) : Color.clear)
    }

    private var sampleBrowser: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Porta.SectionLabel(text: "SAMPLES & PARTS")
                Spacer()
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 10))
                    .foregroundStyle(Porta.labelLight)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 2) {
                sampleRow("Drum Loop — 120 BPM", icon: "waveform", duration: "0:04")
                sampleRow("Bass Line — Am", icon: "waveform", duration: "0:08")
                sampleRow("Guitar Riff — Clean", icon: "waveform", duration: "0:06")
                sampleRow("Vocal Chop — Dry", icon: "waveform", duration: "0:02")
                sampleRow("Ambient Pad — Lush", icon: "waveform", duration: "0:12")
                sampleRow("Field Recording — Rain", icon: "waveform", duration: "0:30")
            }
            .portaPanel(cornerRadius: 8)

            // Drag hint
            HStack(spacing: 4) {
                Image(systemName: "hand.draw")
                    .font(.system(size: 9))
                Text("Drag samples onto the tape deck")
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(Porta.labelLight)
            .padding(.horizontal, 4)
        }
    }

    private func sampleRow(_ name: String, icon: String, duration: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(Porta.flutterBlue)
                .frame(width: 18)
            Text(name)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Porta.label)
                .lineLimit(1)
            Spacer()
            Text(duration)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Porta.labelLight)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    // MARK: - Faders (Always Visible)

    private var fadersSection: some View {
        VStack(spacing: 6) {
            // Divider line
            Rectangle()
                .fill(Porta.bezel.opacity(0.3))
                .frame(height: 1)
                .padding(.horizontal, 4)

            HStack(spacing: 20) {
                RetroFader(
                    value: Bindable(viewModel).dsp.inputGain,
                    label: "INPUT\nGAIN",
                    capColor: Porta.faderCapOrange,
                    height: 110,
                    meterValue: viewModel.meterL
                )
                .frame(width: 44)

                RetroFader(
                    value: Bindable(viewModel).dsp.masterVolume,
                    label: "MASTER\nVOLUME",
                    capColor: Porta.faderCapGreen,
                    height: 110,
                    meterValue: viewModel.meterR
                )
                .frame(width: 44)
            }
        }
    }

    // MARK: - Drawer Background

    private var drawerBackground: some View {
        ZStack {
            Porta.chassisDark.opacity(0.3)
            Porta.chassis

            // Subtle vertical groove texture
            HStack {
                Spacer()
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Porta.deepShadow.opacity(0.15), Color.clear],
                            startPoint: .trailing,
                            endPoint: .leading
                        )
                    )
                    .frame(width: 6)
            }
        }
    }
}
