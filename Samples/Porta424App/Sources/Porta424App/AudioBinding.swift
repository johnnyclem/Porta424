import SwiftUI
import Combine
import Porta424AudioEngine

extension Porta424ViewModel {
    func attachEngine(_ engine: Porta424Engine = .shared) {
        timerCancellable?.cancel()
        timerCancellable = nil
        engineCancellables.removeAll()

        engine.setChannels(channels.map { channel in
            var state = ChannelState(index: channel.index, isStereo: channel.isStereo)
            state.trim = Float(channel.trim)
            state.hiEQ = Float(channel.hiEQ)
            state.midEQ = Float(channel.midEQ)
            state.loEQ = Float(channel.loEQ)
            state.aux1 = Float(channel.aux1)
            state.aux2 = Float(channel.aux2)
            state.tapeCue = Float(channel.tapeCue)
            state.pan = Float(channel.pan)
            state.fader = Float(channel.fader)
            state.mute = channel.mute
            state.assignL = channel.assignL
            state.assignR = channel.assignR
            state.recFunction = mapRecFunction(channel.recFunction)
            state.recArmed = channel.recArmed
            return state
        })

        var masterState = MasterState()
        masterState.stereoFader = Float(master.stereoFader)
        masterState.effectReturn1 = Float(master.effectReturn1)
        masterState.effectReturn2 = Float(master.effectReturn2)
        masterState.phonesLevel = Float(master.phonesLevel)
        masterState.pitch = Float(master.pitch)
        engine.setMaster(masterState)

        $channels
            .dropFirst()
            .sink { [weak engine] channels in
                var updated: [ChannelState] = []
                updated.reserveCapacity(channels.count)
                for channel in channels {
                    var state = ChannelState(index: channel.index, isStereo: channel.isStereo)
                    state.trim = Float(channel.trim)
                    state.hiEQ = Float(channel.hiEQ)
                    state.midEQ = Float(channel.midEQ)
                    state.loEQ = Float(channel.loEQ)
                    state.aux1 = Float(channel.aux1)
                    state.aux2 = Float(channel.aux2)
                    state.tapeCue = Float(channel.tapeCue)
                    state.pan = Float(channel.pan)
                    state.fader = Float(channel.fader)
                    state.mute = channel.mute
                    state.assignL = channel.assignL
                    state.assignR = channel.assignR
                    state.recFunction = mapRecFunction(channel.recFunction)
                    state.recArmed = channel.recArmed
                    updated.append(state)
                }
                engine?.setChannels(updated)
            }
            .store(in: &engineCancellables)

        $master
            .dropFirst()
            .sink { [weak engine] master in
                var state = MasterState()
                state.stereoFader = Float(master.stereoFader)
                state.effectReturn1 = Float(master.effectReturn1)
                state.effectReturn2 = Float(master.effectReturn2)
                state.phonesLevel = Float(master.phonesLevel)
                state.pitch = Float(master.pitch)
                engine?.setMaster(state)
            }
            .store(in: &engineCancellables)

        engine.$meters
            .receive(on: DispatchQueue.main)
            .sink { [weak self] values in
                guard let self else { return }
                for index in 0..<min(values.count, self.meters.count) {
                    self.meters[index] = Double(values[index])
                }
            }
            .store(in: &engineCancellables)

        engine.$transport
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                self.transport.isPlaying = state.isPlaying
                self.transport.isPaused = state.isPaused
                self.transport.isRecording = state.isRecording
                self.transport.counterSeconds = state.position
                self.transport.ffwd = false
                self.transport.rew = false
            }
            .store(in: &engineCancellables)

    }

    func enginePlayPause() { Porta424Engine.shared.transportPlayPause() }
    func engineStop() { Porta424Engine.shared.transportStop() }
    func engineRecord() { Porta424Engine.shared.transportRecordToggle() }
    func engineFF() { Porta424Engine.shared.fastForward() }
    func engineREW() { Porta424Engine.shared.rewind() }
    func engineZero() { Porta424Engine.shared.zeroCounter() }

    private func mapRecFunction(_ function: RecFunction) -> Porta424AudioEngine.RecFunction {
        switch function {
        case .safe: return .safe
        case .buss: return .buss
        case .direct: return .direct
        }
    }
}
