import SwiftUI

/// A dropdown-style preset picker that shows factory and user presets.
/// Designed to match the concept art's popover list.
struct PresetPickerButton: View {
    @Bindable var viewModel: TapeDeckViewModel
    @State private var showingPresets = false

    var body: some View {
        VStack(spacing: 6) {
            Button {
                HapticEngine.buttonPress()
                showingPresets = true
            } label: {
                HStack(spacing: 4) {
                    Text("PRESETS...")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(Porta.label)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Porta.panel)
                        .shadow(color: Porta.softShadow, radius: 2, y: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Porta.bezel.opacity(0.4), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingPresets) {
                PresetListView(viewModel: viewModel, isPresented: $showingPresets)
            }
        }
    }
}

/// The preset list inside the popover.
struct PresetListView: View {
    @Bindable var viewModel: TapeDeckViewModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Factory presets section
            sectionHeader("FACTORY PRESETS")

            ForEach(viewModel.factoryPresets) { preset in
                presetRow(preset)
            }

            Divider()
                .padding(.vertical, 4)

            // User presets section
            sectionHeader("USER PRESETS")

            if viewModel.userPresets.isEmpty {
                Text("No user presets")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            } else {
                ForEach(viewModel.userPresets) { preset in
                    presetRow(preset)
                }
            }

            Divider()
                .padding(.vertical, 4)

            // Save current as preset
            Button {
                viewModel.saveCurrentAsPreset()
                HapticEngine.presetSelect()
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Porta.transportGreen)
                    Text("Save Current...")
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .frame(minWidth: 200)
        .background(.background)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .foregroundStyle(.secondary)
            .tracking(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
    }

    private func presetRow(_ preset: PresetItem) -> some View {
        Button {
            HapticEngine.presetSelect()
            viewModel.loadPreset(preset)
            isPresented = false
        } label: {
            HStack(spacing: 8) {
                Image(systemName: preset.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(preset.isFactory ? Porta.saturationOrange : Porta.transportBlue)
                    .frame(width: 16)
                Text("[\(preset.name)]")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                if preset.id == viewModel.activePresetId {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Porta.transportGreen)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            preset.id == viewModel.activePresetId
                ? Porta.transportGreen.opacity(0.08)
                : Color.clear
        )
    }
}
