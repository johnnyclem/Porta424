import Foundation
import Porta424AudioEngine

// MARK: - App UI channel model → engine channel model
//
// App uses `ChannelState` (ids 1…6). Engine uses its own `ChannelState`
// (indices 1…4 mono + 5 & 7 stereo). Names collide across modules — always
// qualify engine types as `Porta424AudioEngine.ChannelState`.

enum MixerMapping {

    /// Map the six-channel board onto the engine's six strip slots.
    static func engineChannels(from board: [ChannelState]) -> [Porta424AudioEngine.ChannelState] {
        // Engine layout: indices 1,2,3,4,5,7
        let engineIndices = [1, 2, 3, 4, 5, 7]
        return engineIndices.enumerated().map { offset, engineIndex in
            let ui = board.first(where: { $0.id == (engineIndex == 7 ? 6 : engineIndex) })
                ?? board[safe: offset]
                ?? ChannelState(id: engineIndex == 7 ? 6 : engineIndex)

            var state = Porta424AudioEngine.ChannelState(
                index: engineIndex,
                isStereo: engineIndex >= 5
            )
            state.trim = Float(ui.trim)
            state.hiEQ = Float(ui.eqHigh)
            state.midEQ = Float(ui.eqMid)
            state.loEQ = Float(ui.eqLow)
            state.aux1 = Float(ui.fx1Send)
            state.aux2 = Float(ui.fx2Send)
            state.pan = Float(ui.pan)
            state.fader = Float(ui.level)
            state.mute = false
            state.assignL = true
            state.assignR = true
            state.recArmed = ui.isArmed && engineIndex <= 4
            // Armed tracks print from the stereo buss by default (classic Portastudio).
            state.recFunction = ui.isArmed && engineIndex <= 4 ? .buss : .safe
            // LINE with no alternate input source mutes the mic feed for MVP.
            state.inputMuted = (ui.source == .line)
            state.tapeCue = 0
            return state
        }
    }

    static func engineMaster(
        volume: Double,
        pitch: Double,
        effectReturn1: Double = 0,
        effectReturn2: Double = 0,
        phonesLevel: Double = 0.85
    ) -> MasterState {
        var master = MasterState()
        master.stereoFader = Float(max(0, min(1, volume)))
        master.pitch = Float(max(0, min(1, pitch)))
        master.effectReturn1 = Float(max(0, min(1, effectReturn1)))
        master.effectReturn2 = Float(max(0, min(1, effectReturn2)))
        master.phonesLevel = Float(max(0, min(1, phonesLevel)))
        return master
    }

    static func transportMode(
        isPlaying: Bool,
        isPaused: Bool,
        isRecording: Bool
    ) -> TransportMode {
        if isRecording { return .recording }
        if isPlaying && isPaused { return .paused }
        if isPlaying { return .playing }
        return .stopped
    }

    /// Normalize tape dBFS meters (-60…0) to 0…1 for UI VU needles.
    static func normalizeDbFS(_ db: Float) -> Double {
        Double(max(0, min(1, (db + 60) / 60)))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
