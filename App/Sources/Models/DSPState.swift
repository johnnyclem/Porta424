import Foundation
import PortaDSPKit

/// Lightweight value type mirroring DSP parameters for UI binding.
/// All values normalized 0...1 unless noted.
struct DSPState: Equatable, Sendable {
    var saturation: Double = 0.35
    var wow: Double = 0.3
    var flutter: Double = 0.25
    var noise: Double = 0.2
    var bandwidth: Double = 0.7
    var inputGain: Double = 0.65
    var masterVolume: Double = 0.75

    /// Convert to PortaDSPKit parameters.
    func toParams() -> PortaDSP.Params {
        var p = PortaDSP.Params()
        // saturation: map 0-1 → -24 to +24 dB drive
        p.satDriveDb = Float(saturation * 48.0 - 24.0)
        // wow: map 0-1 → 0 to 0.005
        p.wowDepth = Float(wow * 0.005)
        // flutter: map 0-1 → 0 to 0.003
        p.flutterDepth = Float(flutter * 0.003)
        // noise: map 0-1 → -120 to -20 dBFS
        p.hissLevelDbFS = Float(noise * 100.0 - 120.0)
        // bandwidth: map 0-1 → 1kHz to 20kHz LPF
        p.lpfCutoffHz = Float(1000.0 + bandwidth * 19000.0)
        return p
    }

    /// Create from a PortaDSPKit preset's parameters.
    static func from(_ p: PortaDSP.Params) -> DSPState {
        DSPState(
            saturation: Double((p.satDriveDb + 24.0) / 48.0),
            wow: Double(p.wowDepth / 0.005),
            flutter: Double(p.flutterDepth / 0.003),
            noise: Double((p.hissLevelDbFS + 120.0) / 100.0),
            bandwidth: Double((p.lpfCutoffHz - 1000.0) / 19000.0),
            inputGain: 0.65,
            masterVolume: 0.75
        )
    }
}

/// Transport state for the tape deck.
enum TransportMode: Equatable, Sendable {
    case stopped
    case playing
    case paused
    case recording
    case rewinding
    case fastForwarding
}

/// Represents a loaded preset in the UI.
struct PresetItem: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let icon: String       // SF Symbol name
    let isFactory: Bool
}
