#if canImport(AudioToolbox)
import AudioToolbox
import AVFoundation
import Foundation

public enum PortaDSPAudioUnitError: Error {
    case failedToCreateEngineNode
    case unsupportedPlatform
}

public final class PortaDSPAudioUnit: AUAudioUnit {
    // MARK: Component Registration

    public static let componentDescription = AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: PortaDSPAudioUnit.makeFourCC("Prt4"),
        componentManufacturer: PortaDSPAudioUnit.makeFourCC("Pdsp"),
        componentFlags: 0,
        componentFlagsMask: 0
    )

    private static let registration: Void = {
        AUAudioUnit.registerSubclass(
            PortaDSPAudioUnit.self,
            as: PortaDSPAudioUnit.componentDescription,
            name: "PortaDSPKit:PortaDSPAudioUnit",
            version: UInt32(0x0001_0000)
        )
    }()

    public static func register() {
        _ = registration
    }

    public static func makeEngineNode(
        engine: AVAudioEngine,
        options: AudioComponentInstantiationOptions = [],
        completionHandler: @escaping (AVAudioUnit?, PortaDSPAudioUnit?, Error?) -> Void
    ) {
        PortaDSPAudioUnit.register()
        AVAudioUnit.instantiate(with: PortaDSPAudioUnit.componentDescription, options: options) { unit, error in
            if let error {
                completionHandler(nil, nil, error)
                return
            }
            guard let resolvedUnit = unit else {
                completionHandler(nil, nil, PortaDSPAudioUnitError.failedToCreateEngineNode)
                return
            }
            engine.attach(resolvedUnit)
            guard let dspUnit = resolvedUnit.auAudioUnit as? PortaDSPAudioUnit else {
                engine.detach(resolvedUnit)
                completionHandler(nil, nil, PortaDSPAudioUnitError.failedToCreateEngineNode)
                return
            }
            completionHandler(resolvedUnit, dspUnit, nil)
        }
    }

    // MARK: Lifecycle

    private let inputBus: AUAudioUnitBus
    private let outputBus: AUAudioUnitBus
    private var interleavedScratch: UnsafeMutablePointer<Float>?
    private var scratchCapacity: Int = 0
    private var dspHandle: porta_dsp_handle?
    private var lastParams = PortaDSP.Params()

    public override var canProcessInPlace: Bool { true }

    public override init(componentDescription: AudioComponentDescription, options: AudioComponentInstantiationOptions = []) throws {
        let defaultFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: false
        )!
        inputBus = try AUAudioUnitBus(format: defaultFormat)
        outputBus = try AUAudioUnitBus(format: defaultFormat)
        try super.init(componentDescription: componentDescription, options: options)
        maximumFramesToRender = 4096
        inputBusses = AUAudioUnitBusArray(owner: self, busType: .input, busses: [inputBus])
        outputBusses = AUAudioUnitBusArray(owner: self, busType: .output, busses: [outputBus])
    }

    deinit {
        releaseDSP()
        releaseScratch()
    }

    // MARK: Parameter Handling

    public func updateParameters(_ params: PortaDSP.Params) {
        lastParams = params
        guard let handle = dspHandle else { return }
        var cParams = params.makeCParams()
        porta_update_params(handle, &cParams)
    }

    public func readMeters() -> [Float] {
        var meters = [Float](repeating: -120.0, count: 8)
        guard let handle = dspHandle else { return meters }
        porta_get_meters_dbfs(handle, &meters, Int32(meters.count))
        return meters
    }

    // MARK: Render Resources

    public override func allocateRenderResources() throws {
        try super.allocateRenderResources()
        guard inputBus.format.channelCount == outputBus.format.channelCount else {
            throw AUAudioUnitError(.formatNotSupported)
        }
        let channels = Int(outputBus.format.channelCount)
        let frames = Int(maximumFramesToRender)
        scratchCapacity = frames * channels
        interleavedScratch = UnsafeMutablePointer<Float>.allocate(capacity: scratchCapacity)
        interleavedScratch?.initialize(repeating: 0, count: scratchCapacity)
        dspHandle = porta_create(outputBus.format.sampleRate, Int32(frames), Int32(channels))
        updateParameters(lastParams)
    }

    public override func deallocateRenderResources() {
        releaseDSP()
        releaseScratch()
        super.deallocateRenderResources()
    }

    // MARK: Rendering

    public override var internalRenderBlock: AUInternalRenderBlock {
        { [weak self] actionFlags, timestamp, frameCount, outputBusNumber, outputData, renderEvents, pullInputBlock in
            guard let strongSelf = self else { return kAudioUnitErr_Uninitialized }
            guard let pullInputBlock = pullInputBlock else {
                strongSelf.silence(outputData, frameCount: frameCount)
                return noErr
            }
            guard let scratch = strongSelf.interleavedScratch,
                  let handle = strongSelf.dspHandle else {
                return pullInputBlock(actionFlags, timestamp, frameCount, outputBusNumber, outputData)
            }
            if frameCount > strongSelf.maximumFramesToRender {
                return kAudioUnitErr_TooManyFramesToProcess
            }
            var pullFlags: AudioUnitRenderActionFlags = []
            let status = pullInputBlock(&pullFlags, timestamp, frameCount, 0, outputData)
            if status != noErr { return status }
            let channels = Int(strongSelf.outputBus.format.channelCount)
            let frames = Int(frameCount)
            if strongSelf.outputBus.format.isInterleaved {
                strongSelf.copyInterleavedBuffer(outputData, to: scratch, frames: frames, channels: channels)
            } else {
                strongSelf.copyPlanarBuffer(outputData, to: scratch, frames: frames, channels: channels)
            }
            porta_process_interleaved(handle, scratch, Int32(frames), Int32(channels))
            guard !strongSelf.shouldBypassEffect else {
                return noErr
            }
            if strongSelf.outputBus.format.isInterleaved {
                strongSelf.writeInterleavedBuffer(from: scratch, to: outputData, frames: frames, channels: channels)
            } else {
                strongSelf.writePlanarBuffer(from: scratch, to: outputData, frames: frames, channels: channels)
            }
            return noErr
        }
    }

    // MARK: Helpers

    private func releaseScratch() {
        if let scratch = interleavedScratch {
            scratch.deinitialize(count: scratchCapacity)
            scratch.deallocate()
        }
        interleavedScratch = nil
        scratchCapacity = 0
    }

    private func releaseDSP() {
        if let handle = dspHandle {
            porta_destroy(handle)
        }
        dspHandle = nil
    }

    private func silence(_ list: UnsafeMutablePointer<AudioBufferList>?, frameCount: AUAudioFrameCount) {
        guard let list else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        let samples = Int(frameCount)
        for buffer in buffers {
            guard let data = buffer.mData else { continue }
            let count = samples * Int(buffer.mNumberChannels)
            data.bindMemory(to: Float.self, capacity: count).assign(repeating: 0, count: count)
        }
    }

    private func copyInterleavedBuffer(_ list: UnsafeMutablePointer<AudioBufferList>?, to dest: UnsafeMutablePointer<Float>, frames: Int, channels: Int) {
        guard let list else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        guard let data = buffers.first?.mData else { return }
        let count = frames * channels
        dest.assign(from: data.bindMemory(to: Float.self, capacity: count), count: count)
    }

    private func copyPlanarBuffer(_ list: UnsafeMutablePointer<AudioBufferList>?, to dest: UnsafeMutablePointer<Float>, frames: Int, channels: Int) {
        guard let list else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        let bufferCount = buffers.count
        guard bufferCount > 0 else {
            dest.assign(repeating: 0, count: frames * channels)
            return
        }
        for channel in 0..<channels {
            if channel >= bufferCount {
                var writePtr = dest.advanced(by: channel)
                for _ in 0..<frames {
                    writePtr.pointee = 0
                    writePtr = writePtr.advanced(by: channels)
                }
                continue
            }
            let audioBuffer = buffers[channel]
            guard let channelData = audioBuffer.mData else { continue }
            let src = channelData.bindMemory(to: Float.self, capacity: frames)
            var writePtr = dest.advanced(by: channel)
            for frame in 0..<frames {
                writePtr.pointee = src[frame]
                writePtr = writePtr.advanced(by: channels)
            }
        }
    }

    private func writeInterleavedBuffer(from source: UnsafeMutablePointer<Float>, to list: UnsafeMutablePointer<AudioBufferList>?, frames: Int, channels: Int) {
        guard let list else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        guard let data = buffers.first?.mData else { return }
        data.bindMemory(to: Float.self, capacity: frames * channels).assign(from: source, count: frames * channels)
    }

    private func writePlanarBuffer(from source: UnsafeMutablePointer<Float>, to list: UnsafeMutablePointer<AudioBufferList>?, frames: Int, channels: Int) {
        guard let list else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        let bufferCount = buffers.count
        for channel in 0..<bufferCount {
            guard channel < channels else {
                zeroChannel(buffers[channel], frames: frames)
                continue
            }
            guard let channelData = buffers[channel].mData else { continue }
            let dest = channelData.bindMemory(to: Float.self, capacity: frames)
            var readPtr = source.advanced(by: channel)
            for frame in 0..<frames {
                dest[frame] = readPtr.pointee
                readPtr = readPtr.advanced(by: channels)
            }
        }
    }

    private func zeroChannel(_ buffer: AudioBuffer, frames: Int) {
        guard let data = buffer.mData else { return }
        let count = frames * Int(buffer.mNumberChannels)
        data.bindMemory(to: Float.self, capacity: count).assign(repeating: 0, count: count)
    }

    private static func makeFourCC(_ string: String) -> FourCharCode {
        precondition(string.count == 4, "FourCC must be exactly 4 characters")
        var result: FourCharCode = 0
        for scalar in string.unicodeScalars {
            result = (result << 8) | FourCharCode(scalar.value)
        }
        return result
    }
}

public enum PortaDSPNodeFactory {
    public static func instantiate(options: AudioComponentInstantiationOptions = [], completionHandler: @escaping (AVAudioUnit?, Error?) -> Void) {
        PortaDSPAudioUnit.register()
        AVAudioUnit.instantiate(with: PortaDSPAudioUnit.componentDescription, options: options, completionHandler: completionHandler)
    }

    public static func instantiateSync(options: AudioComponentInstantiationOptions = []) throws -> AVAudioUnit {
        let semaphore = DispatchSemaphore(value: 0)
        var unit: AVAudioUnit?
        var caughtError: Error?
        instantiate(options: options) { audioUnit, error in
            unit = audioUnit
            caughtError = error
            semaphore.signal()
        }
        semaphore.wait()
        if let error = caughtError {
            throw error
        }
        guard let resolvedUnit = unit else {
            throw AUAudioUnitError(.failedInitialization)
        }
        return resolvedUnit
    }
}
#else
import Foundation

public enum PortaDSPAudioUnitError: Error {
    case failedToCreateEngineNode
    case unsupportedPlatform
}

public struct AudioComponentDescription: Sendable {
    public var componentType: UInt32
    public var componentSubType: UInt32
    public var componentManufacturer: UInt32
    public var componentFlags: UInt32
    public var componentFlagsMask: UInt32

    public init(
        componentType: UInt32 = 0,
        componentSubType: UInt32 = 0,
        componentManufacturer: UInt32 = 0,
        componentFlags: UInt32 = 0,
        componentFlagsMask: UInt32 = 0
    ) {
        self.componentType = componentType
        self.componentSubType = componentSubType
        self.componentManufacturer = componentManufacturer
        self.componentFlags = componentFlags
        self.componentFlagsMask = componentFlagsMask
    }
}

public struct AudioComponentInstantiationOptions: OptionSet, Sendable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }
}

public class AVAudioUnit {}
public class AVAudioEngine {}

public final class PortaDSPAudioUnit {
    public static let componentDescription = AudioComponentDescription()

    public init(
        componentDescription: AudioComponentDescription = PortaDSPAudioUnit.componentDescription,
        options: AudioComponentInstantiationOptions = []
    ) throws {
        throw PortaDSPAudioUnitError.unsupportedPlatform
    }

    public static func register() {}

    public static func makeEngineNode(
        engine: AVAudioEngine,
        options: AudioComponentInstantiationOptions = [],
        completionHandler: @escaping (AVAudioUnit?, PortaDSPAudioUnit?, Error?) -> Void
    ) {
        completionHandler(nil, nil, PortaDSPAudioUnitError.unsupportedPlatform)
    }
}

public enum PortaDSPNodeFactory {
    public static func instantiate(
        options: AudioComponentInstantiationOptions = [],
        completionHandler: @escaping (AVAudioUnit?, Error?) -> Void
    ) {
        completionHandler(nil, PortaDSPAudioUnitError.unsupportedPlatform)
    }

    public static func instantiateSync(options: AudioComponentInstantiationOptions = []) throws -> AVAudioUnit {
        throw PortaDSPAudioUnitError.unsupportedPlatform
    }
}
#endif
