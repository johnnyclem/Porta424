import SwiftUI

/// The transport control section with REW, FF, STOP, PLAY, and REC buttons.
/// Styled as chunky, tactile buttons matching the concept art's bright colors.
struct TransportBar: View {
    @Bindable var viewModel: TapeDeckViewModel

    var body: some View {
        VStack(spacing: 6) {
            // Button row
            HStack(spacing: 10) {
                RetroTransportButton(
                    icon: "backward.fill",
                    label: "REW",
                    color: Porta.transportBlue,
                    isActive: viewModel.transportMode == .rewinding
                ) {
                    viewModel.rewind()
                }

                RetroTransportButton(
                    icon: "forward.fill",
                    label: "FF",
                    color: Porta.transportBlue,
                    isActive: viewModel.transportMode == .fastForwarding
                ) {
                    viewModel.fastForward()
                }

                RetroTransportButton(
                    icon: "stop.fill",
                    label: "STOP",
                    color: Porta.transportOrange,
                    isActive: viewModel.transportMode == .stopped
                ) {
                    viewModel.stop()
                }

                RetroTransportButton(
                    icon: viewModel.transportMode == .paused ? "pause.fill" : "play.fill",
                    label: "PLAY",
                    color: Porta.transportGreen,
                    isActive: viewModel.transportMode == .playing || viewModel.transportMode == .recording
                ) {
                    viewModel.togglePlay()
                }

                RetroTransportButton(
                    icon: "circle.fill",
                    label: "REC",
                    color: Porta.transportRed,
                    isActive: viewModel.transportMode == .recording
                ) {
                    viewModel.toggleRecord()
                }
            }
        }
    }
}
