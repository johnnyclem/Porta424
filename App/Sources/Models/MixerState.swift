import Foundation

/// Per-channel mixer state for the Porta424 six-channel board.
///
/// All continuous values are normalized `0...1`. `pan` follows the hardware
/// convention where `0` is hard-left, `0.5` is center, and `1` is hard-right.
/// EQ knobs are centered at `0.5` (flat); their detent snaps back to flat.
struct ChannelState: Identifiable, Equatable, Sendable {
    /// Channel number as printed on the chassis (1...6).
    let id: Int

    var trim: Double = 0.6
    var eqHigh: Double = 0.5
    var eqMid: Double = 0.5
    var eqLow: Double = 0.5
    var fx1Send: Double = 0.0
    var fx2Send: Double = 0.0
    var pan: Double = 0.5
    var level: Double = 0.65   // channel fader
    var source: ChannelSource = .line
    var isArmed: Bool = false  // record-armed to the assigned tape track
}

/// Input source selection for a mixer channel.
enum ChannelSource: String, Equatable, Sendable {
    case mic = "MIC"
    case line = "LINE"

    mutating func toggle() {
        self = (self == .mic) ? .line : .mic
    }
}

extension Array where Element == ChannelState {
    /// The standard six-channel Porta424 board, numbered 1...6.
    static var defaultBoard: [ChannelState] {
        (1...6).map { ChannelState(id: $0) }
    }
}
