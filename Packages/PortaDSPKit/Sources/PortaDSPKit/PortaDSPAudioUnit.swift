#if canImport(AudioToolbox)
import AudioToolbox
import AVFoundation
import Foundation

public enum PortaDSPAudioUnitError: Error {
    case failedToCreateEngineNode
    case unsupportedPlatform
}

public final class PortaDSPAudioUnit: AUAudioUnit {
    public enum ParameterID: Int, CaseIterable {
        case wowDepth
        case flutterDepth
        case headBumpGainDb
        case headBumpFreqHz
        case satDriveDb
        case hissLevelDbFS
        case lpfCutoffHz
        case azimuthJitterMs
        case crosstalkDb
        case dropoutRatePerMin
        case nrTrack4Bypass

        public var identifier: String { PortaDSPAudioUnit.definition(for: self).identifier }
        public var name: String { PortaDSPAudioUnit.definition(for: self).name }
        public var unit: AudioUnitParameterUnit { PortaDSPAudioUnit.definition(for: self).unit }
        public var minValue: AUValue { PortaDSPAudioUnit.definition(for: self).range.lowerBound }
        public var maxValue: AUValue { PortaDSPAudioUnit.definition(for: self).range.upperBound }
        public var defaultValue: AUValue { PortaDSPAudioUnit.definition(for: self).defaultValue }
        public var flags: AudioUnitParameterOptions { PortaDSPAudioUnit.definition(for: self).flags }
        public var range: ClosedRange<AUValue> { PortaDSPAudioUnit.definition(for: self).range }
        public var address: AUParameterAddress { AUParameterAddress(rawValue) }
    }

    private enum Storage {
        case float(WritableKeyPath<PortaDSP.Params, Float>)
        case bool(WritableKeyPath<PortaDSP.Params, Bool>)
    }

    private struct ParameterDefinition {
        let id: ParameterID
        let identifier: String
        let name: String
        let unit: AudioUnitParameterUnit
        let range: ClosedRange<AUValue>
        let defaultValue: AUValue
        let flags: AudioUnitParameterOptions
        let storage: Storage

        func value(from params: PortaDSP.Params) -> AUValue {
            switch storage {
            case let .float(keyPath):
                return params[keyPath: keyPath]
            case let .bool(keyPath):
                return params[keyPath: keyPath] ? 1.0 : 0.0
            }
        }

        func apply(value: AUValue, to params: inout PortaDSP.Params) {
            switch storage {
            case let .float(keyPath):
                params[keyPath: keyPath] = value
            case let .bool(keyPath):
                params[keyPath: keyPath] = value >= 0.5
            }
        }
    }

    private static let parameterDefinitions: [ParameterDefinition] = {
        let defaults = PortaDSP.Params()
        let baseFlags: AudioUnitParameterOptions = [.flag_IsReadable, .flag_IsWritable]
        return [
            ParameterDefinition(
                id: .wowDepth,
                identifier: "wowDepth",
                name: "Wow Depth",
                unit: .generic,
                range: 0.0...0.005,
                defaultValue: defaults.wowDepth,
                flags: baseFlags,
                storage: .float(\.wowDepth)
            ),
            ParameterDefinition(
                id: .flutterDepth,
                identifier: "flutterDepth",
                name: "Flutter Depth",
                unit: .generic,
                range: 0.0...0.003,
                defaultValue: defaults.flutterDepth,
                flags: baseFlags,
                storage: .float(\.flutterDepth)
            ),
            ParameterDefinition(
                id: .headBumpGainDb,
                identifier: "headBumpGainDb",
                name: "Head Bump Gain",
                unit: .decibels,
                range: -12.0...12.0,
                defaultValue: defaults.headBumpGainDb,
                flags: baseFlags,
                storage: .float(\.headBumpGainDb)
            ),
            ParameterDefinition(
                id: .headBumpFreqHz,
                identifier: "headBumpFreqHz",
                name: "Head Bump Freq",
                unit: .hertz,
                range: 20.0...200.0,
                defaultValue: defaults.headBumpFreqHz,
                flags: baseFlags,
                storage: .float(\.headBumpFreqHz)
            ),
            ParameterDefinition(
                id: .satDriveDb,
                identifier: "satDriveDb",
                name: "Saturation Drive",
                unit: .decibels,
                range: -24.0...24.0,
                defaultValue: defaults.satDriveDb,
                flags: baseFlags,
                storage: .float(\.satDriveDb)
            ),
            ParameterDefinition(
                id: .hissLevelDbFS,
                identifier: "hissLevelDbFS",
                name: "Hiss Level",
                unit: .decibels,
                range: -120.0...0.0,
                defaultValue: defaults.hissLevelDbFS,
                flags: baseFlags,
                storage: .float(\.hissLevelDbFS)
            ),
            ParameterDefinition(
                id: .lpfCutoffHz,
                identifier: "lpfCutoffHz",
                name: "Low-Pass Cutoff",
                unit: .hertz,
                range: 1_000.0...20_000.0,
                defaultValue: defaults.lpfCutoffHz,
                flags: baseFlags,
                storage: .float(\.lpfCutoffHz)
            ),
            ParameterDefinition(
                id: .azimuthJitterMs,
                identifier: "azimuthJitterMs",
                name: "Azimuth Jitter",
                unit: .milliseconds,
                range: 0.0...2.0,
                defaultValue: defaults.azimuthJitterMs,
                flags: baseFlags,
                storage: .float(\.azimuthJitterMs)
            ),
            ParameterDefinition(
                id: .crosstalkDb,
                identifier: "crosstalkDb",
                name: "Crosstalk",
                unit: .decibels,
                range: -120.0...0.0,
                defaultValue: defaults.crosstalkDb,
                flags: baseFlags,
                storage: .float(\.crosstalkDb)
            ),
            ParameterDefinition(
                id: .dropoutRatePerMin,
                identifier: "dropoutRatePerMin",
                name: "Dropout Rate",
                unit: .rate,
                range: 0.0...10.0,
                defaultValue: defaults.dropoutRatePerMin,
                flags: baseFlags,
                storage: .float(\.dropoutRatePerMin)
            ),
            ParameterDefinition(
                id: .nrTrack4Bypass,
                identifier: "nrTrack4Bypass",
                name: "NR Track 4 Bypass",
                unit: .boolean,
                range: 0.0...1.0,
                defaultValue: defaults.nrTrack4Bypass ? 1.0 : 0.0,
                flags: baseFlags,
                storage: .bool(\.nrTrack4Bypass)
            )
        ]
    }()

    private static let parameterDefinitionsByID: [ParameterID: ParameterDefinition] = {
        var map: [ParameterID: ParameterDefinition] = [:]
        for definition in parameterDefinitions {
            map[definition.id] = definition
        }
        return map
    }()

    static func definition(for id: ParameterID) -> ParameterDefinition {
        guard let definition = parameterDefinitionsByID[id] else {
            fatalError("Missing definition for parameter id \(id)")
        }
        return definition
    }

    private static func definition(forAddress address: AUParameterAddress) -> ParameterDefinition? {
        guard let id = ParameterID(rawValue: Int(address)) else { return nil }
        return parameterDefinitionsByID[id]
    }

    private let parameterTreeImpl: AUParameterTree
    private let parameterMap: [ParameterID: AUParameter]
    private var parameterObserverToken: AUParameterObserverToken?

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
    private lazy var internalFactoryPresets: [AUAudioUnitPreset] = {
        PortaPreset.factoryPresets.enumerated().map { index, preset in
            let descriptor = AUAudioUnitPreset()
            descriptor.number = index
            descriptor.name = preset.name
            return descriptor
        }
    }()
    private var currentPresetSelection: AUAudioUnitPreset?

    public override var canProcessInPlace: Bool { true }
    public override var parameterTree: AUParameterTree? { parameterTreeImpl }

    public override init(componentDescription: AudioComponentDescription, options: AudioComponentInstantiationOptions = []) throws {
        var map: [ParameterID: AUParameter] = [:]
        for definition in PortaDSPAudioUnit.parameterDefinitions {
            let parameter = AUParameterTree.createParameter(
                withIdentifier: definition.identifier,
                name: definition.name,
                address: definition.id.address,
                min: definition.range.lowerBound,
                max: definition.range.upperBound,
                unit: definition.unit,
                unitName: nil,
                flags: definition.flags,
                valueStrings: nil,
                dependentParameters: nil
            )
            parameter.value = definition.defaultValue
            map[definition.id] = parameter
        }
        parameterMap = map
        let orderedParameters = ParameterID.allCases.compactMap { map[$0] }
        parameterTreeImpl = AUParameterTree.createTree(withChildren: orderedParameters)
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
        parameterObserverToken = parameterTreeImpl.token(byAddingParameterObserver: { [weak self] address, value in
            self?.handleParameterChange(address: address, value: value)
        })
    }

    deinit {
        releaseDSP()
        releaseScratch()
    }

    // MARK: Parameter Handling

    public func updateParameters(_ params: PortaDSP.Params) {
        lastParams = params
        for definition in PortaDSPAudioUnit.parameterDefinitions {
            guard let parameter = parameterMap[definition.id] else { continue }
            let value = definition.value(from: params)
            if let token = parameterObserverToken {
                parameter.setValue(value, originator: token)
            } else {
                parameter.value = value
            }
        }
        pushParametersToDSP()
    }

    public func currentParameters() -> PortaDSP.Params {
        lastParams
    }

    public func exportPresetDictionary() -> [String: Any] {
        var dictionary: [String: Any] = [:]
        let snapshot = lastParams
        for definition in PortaDSPAudioUnit.parameterDefinitions {
            switch definition.storage {
            case let .float(keyPath):
                dictionary[definition.identifier] = snapshot[keyPath: keyPath]
            case let .bool(keyPath):
                dictionary[definition.identifier] = snapshot[keyPath: keyPath]
            }
        }
        return dictionary
    }

    public func applyPresetDictionary(_ dictionary: [String: Any]) {
        var updated = lastParams
        for definition in PortaDSPAudioUnit.parameterDefinitions {
            guard let rawValue = dictionary[definition.identifier] else { continue }
            switch definition.storage {
            case let .float(keyPath):
                if let number = rawValue as? NSNumber {
                    updated[keyPath: keyPath] = number.floatValue
                } else if let value = rawValue as? Float {
                    updated[keyPath: keyPath] = value
                } else if let value = rawValue as? Double {
                    updated[keyPath: keyPath] = Float(value)
                }
            case let .bool(keyPath):
                if let boolValue = rawValue as? Bool {
                    updated[keyPath: keyPath] = boolValue
                } else if let number = rawValue as? NSNumber {
                    updated[keyPath: keyPath] = number.boolValue
                }
            }
        }
        updateParameters(updated)
        setParameters(params, clearPresetSelection: true)
    }

    public func readMeters() -> [Float] {
        var meters = [Float](repeating: -120.0, count: 8)
        guard let handle = dspHandle else { return meters }
        porta_get_meters_dbfs(handle, &meters, Int32(meters.count))
        return meters
    }

    private func handleParameterChange(address: AUParameterAddress, value: AUValue) {
        guard let definition = PortaDSPAudioUnit.definition(forAddress: address) else { return }
        var updated = lastParams
        definition.apply(value: value, to: &updated)
        lastParams = updated
        pushParametersToDSP()
    }

    private func pushParametersToDSP() {
        guard let handle = dspHandle else { return }
        var cParams = lastParams.makeCParams()

    public override var supportsUserPresets: Bool { true }

    public override var factoryPresets: [AUAudioUnitPreset]? {
        internalFactoryPresets
    }

    public override var currentPreset: AUAudioUnitPreset? {
        get { currentPresetSelection }
        set {
            guard let newValue else {
                currentPresetSelection = nil
                return
            }
            if let index = factoryPresetIndex(for: newValue.number) {
                applyFactoryPreset(at: index)
            } else {
                currentPresetSelection = newValue
            }
        }
    }

    public func applyFactoryPreset(at index: Int) {
        guard index >= 0, index < PortaPreset.factoryPresets.count else { return }
        let preset = PortaPreset.factoryPresets[index]
        currentPresetSelection = internalFactoryPresets[index]
        applyPresetParameters(preset.parameters)
    }

    private func factoryPresetIndex(for number: Int) -> Int? {
        let index = number
        guard index >= 0, index < internalFactoryPresets.count else { return nil }
        return index
    }

    private func applyPresetParameters(_ params: PortaDSP.Params) {
        setParameters(params, clearPresetSelection: false)
    }

    private func setParameters(_ params: PortaDSP.Params, clearPresetSelection: Bool) {
        lastParams = params
        if clearPresetSelection {
            currentPresetSelection = nil
        }
        guard let handle = dspHandle else { return }
        var cParams = params.makeCParams()
        porta_update_params(handle, &cParams)
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
        applyPresetParameters(lastParams)
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

    public func updateParameters(_ params: PortaDSP.Params) {}

    public func currentParameters() -> PortaDSP.Params { PortaDSP.Params() }

    public func exportPresetDictionary() -> [String: Any] { [:] }

    public func applyPresetDictionary(_ dictionary: [String: Any]) {}
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
