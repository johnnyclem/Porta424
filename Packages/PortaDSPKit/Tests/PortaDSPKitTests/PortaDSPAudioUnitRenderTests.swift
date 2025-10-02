#if canImport(AudioToolbox) && canImport(AVFoundation)
import AudioToolbox
import AVFoundation
import XCTest
import Darwin
@testable import PortaDSPKit

final class PortaDSPAudioUnitRenderTests: XCTestCase {
    private let accuracy: Float = 1.0e-6

    func testInterleavedRenderingProducesExpectedSamples() throws {
        let frameSizes = [1, 2, 7, 64]
        for channels in 1...2 {
            for frames in frameSizes {
                try assertRenderMatchesExpected(
                    channels: channels,
                    frames: frames,
                    interleaved: true,
                    bypass: false,
                    offline: false
                )
            }
        }
    }

    func testPlanarRenderingProducesExpectedSamples() throws {
        let frameSizes = [1, 3, 8, 65]
        for channels in 1...2 {
            for frames in frameSizes {
                try assertRenderMatchesExpected(
                    channels: channels,
                    frames: frames,
                    interleaved: false,
                    bypass: false,
                    offline: false
                )
            }
        }
    }

    func testBypassLeavesInterleavedBufferUnmodified() throws {
        try assertRenderMatchesExpected(channels: 2, frames: 16, interleaved: true, bypass: true, offline: false)
    }

    func testBypassLeavesPlanarBufferUnmodified() throws {
        try assertRenderMatchesExpected(channels: 2, frames: 16, interleaved: false, bypass: true, offline: false)
    }

    func testOfflineInterleavedRenderingMatchesExpectedSamples() throws {
        try assertRenderMatchesExpected(
            channels: 2,
            frames: 32,
            interleaved: true,
            bypass: false,
            offline: true
        )
    }

    func testOfflinePlanarRenderingMatchesExpectedSamples() throws {
        try assertRenderMatchesExpected(
            channels: 2,
            frames: 31,
            interleaved: false,
            bypass: false,
            offline: true
        )
    }

    func testMaximumFramesToRenderAndTooManyFramesError() throws {
        let channels = 2
        let maxFrames: AUAudioFrameCount = 32

        let unit = try makeConfiguredUnit(channels: channels, interleaved: true, maximumFrames: maxFrames)
        defer { unit.deallocateRenderResources() }

        let validFrames = Int(maxFrames)
        var validBuffers = makeAudioBufferList(frames: validFrames, channels: channels, interleaved: true)
        defer { deallocateAudioBufferList(&validBuffers, interleaved: true, frames: validFrames, channels: channels) }

        let pullSamples = makeChannelSamples(frames: validFrames, channels: channels)

        let pullBlock: AURenderPullInputBlock = { flags, timestamp, frameCount, busNumber, data in
            XCTAssertEqual(frameCount, maxFrames)
            XCTAssertEqual(busNumber, 0)
            self.write(samples: pullSamples, to: data, interleaved: true, frames: validFrames, channels: channels)
            return noErr
        }

        var flags: AudioUnitRenderActionFlags = []
        var timestamp = AudioTimeStamp()
        let okStatus = withUnsafePointer(to: &timestamp) { tsPtr in
            unit.internalRenderBlock(&flags, tsPtr, maxFrames, 0, validBuffers.unsafeMutablePointer, nil, pullBlock)
        }
        XCTAssertEqual(okStatus, noErr)

        let oversizedFrames = Int(maxFrames + 1)
        var oversizedBuffers = makeAudioBufferList(frames: oversizedFrames, channels: channels, interleaved: true)
        defer { deallocateAudioBufferList(&oversizedBuffers, interleaved: true, frames: oversizedFrames, channels: channels) }

        var oversizedPullInvoked = false
        let oversizedPull: AURenderPullInputBlock = { _, _, _, _, _ in
            oversizedPullInvoked = true
            return noErr
        }

        flags = []
        timestamp = AudioTimeStamp()
        let errorStatus = withUnsafePointer(to: &timestamp) { tsPtr in
            unit.internalRenderBlock(&flags, tsPtr, maxFrames + 1, 0, oversizedBuffers.unsafeMutablePointer, nil, oversizedPull)
        }
        XCTAssertEqual(errorStatus, kAudioUnitErr_TooManyFramesToProcess)
        XCTAssertFalse(oversizedPullInvoked, "Pull block should not be invoked when too many frames are requested")
    }

    // MARK: - Helpers

    private func assertRenderMatchesExpected(
        channels: Int,
        frames: Int,
        interleaved: Bool,
        bypass: Bool,
        offline: Bool
    ) throws {
        let unit = try makeConfiguredUnit(channels: channels, interleaved: interleaved, maximumFrames: AUAudioFrameCount(max(frames, 1)))
        defer { unit.deallocateRenderResources() }
        unit.shouldBypassEffect = bypass

        let samples = makeChannelSamples(frames: frames, channels: channels)
        var buffers = makeAudioBufferList(frames: frames, channels: channels, interleaved: interleaved)
        defer { deallocateAudioBufferList(&buffers, interleaved: interleaved, frames: frames, channels: channels) }

        let pullBlock: AURenderPullInputBlock = { flags, _, frameCount, busNumber, data in
            if offline {
                XCTAssertNotNil(flags, "Offline rendering should provide action flags")
                if let flags {
                    XCTAssertTrue(flags.pointee.contains(.offline))
                }
            } else if let flags {
                XCTAssertFalse(flags.pointee.contains(.offline))
            }
            XCTAssertEqual(Int(frameCount), frames)
            XCTAssertEqual(busNumber, 0)
            self.write(samples: samples, to: data, interleaved: interleaved, frames: frames, channels: channels)
            return noErr
        }

        var flags: AudioUnitRenderActionFlags = offline ? [.offline] : []
        var timestamp = AudioTimeStamp()
        let status = withUnsafePointer(to: &timestamp) { tsPtr in
            unit.internalRenderBlock(&flags, tsPtr, AUAudioFrameCount(frames), 0, buffers.unsafeMutablePointer, nil, pullBlock)
        }
        XCTAssertEqual(status, noErr)

        let rendered = read(from: buffers, interleaved: interleaved, frames: frames, channels: channels)
        let expected = bypass ? samples : applyTanh(samples: samples)

        for channel in 0..<channels {
            for frame in 0..<frames {
                XCTAssertEqual(rendered[channel][frame], expected[channel][frame], accuracy: accuracy)
            }
        }
    }

    private func makeConfiguredUnit(channels: Int, interleaved: Bool, maximumFrames: AUAudioFrameCount) throws -> PortaDSPAudioUnit {
        let unit = try PortaDSPAudioUnit(componentDescription: PortaDSPAudioUnit.componentDescription)
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: AVAudioChannelCount(channels),
            interleaved: interleaved
        )!
        try unit.inputBusses[0].setFormat(format)
        try unit.outputBusses[0].setFormat(format)
        unit.maximumFramesToRender = maximumFrames
        try unit.allocateRenderResources()
        return unit
    }

    private func makeChannelSamples(frames: Int, channels: Int) -> [[Float]] {
        (0..<channels).map { channel in
            (0..<frames).map { frame in
                let base = Float(channel + 1) * 0.1
                let variation = Float(frame % 5) * 0.05
                return (frame % 2 == 0) ? base + variation : -(base + variation)
            }
        }
    }

    private func applyTanh(samples: [[Float]]) -> [[Float]] {
        samples.map { channelSamples in
            channelSamples.map { Darwin.tanhf($0) }
        }
    }

    private func makeAudioBufferList(frames: Int, channels: Int, interleaved: Bool) -> UnsafeMutableAudioBufferListPointer {
        let bufferCount = interleaved ? 1 : channels
        let buffers = AudioBufferList.allocate(maximumBuffers: bufferCount)
        buffers.count = bufferCount
        for index in 0..<bufferCount {
            let channelCount = interleaved ? channels : 1
            let sampleCount = interleaved ? frames * channels : frames
            let data = UnsafeMutablePointer<Float>.allocate(capacity: sampleCount)
            data.initialize(repeating: 0, count: sampleCount)
            buffers[index].mNumberChannels = UInt32(channelCount)
            buffers[index].mDataByteSize = UInt32(sampleCount * MemoryLayout<Float>.size)
            buffers[index].mData = UnsafeMutableRawPointer(data)
        }
        return buffers
    }

    private func deallocateAudioBufferList(_ buffers: inout UnsafeMutableAudioBufferListPointer, interleaved: Bool, frames: Int, channels: Int) {
        let sampleCount = interleaved ? frames * channels : frames
        for index in 0..<buffers.count {
            let channelSamples = interleaved ? sampleCount : frames * Int(buffers[index].mNumberChannels)
            if let data = buffers[index].mData {
                let pointer = data.assumingMemoryBound(to: Float.self)
                pointer.deinitialize(count: channelSamples)
                pointer.deallocate()
            }
        }
        buffers.deallocate()
    }

    private func write(samples: [[Float]], to list: UnsafeMutablePointer<AudioBufferList>?, interleaved: Bool, frames: Int, channels: Int) {
        guard let list else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        if interleaved {
            guard let data = buffers[0].mData else { return }
            let pointer = data.assumingMemoryBound(to: Float.self)
            for frame in 0..<frames {
                for channel in 0..<channels {
                    pointer[frame * channels + channel] = samples[channel][frame]
                }
            }
        } else {
            for channel in 0..<channels {
                guard let data = buffers[channel].mData else { continue }
                let pointer = data.assumingMemoryBound(to: Float.self)
                for frame in 0..<frames {
                    pointer[frame] = samples[channel][frame]
                }
            }
        }
    }

    private func read(from buffers: UnsafeMutableAudioBufferListPointer, interleaved: Bool, frames: Int, channels: Int) -> [[Float]] {
        if interleaved {
            guard let data = buffers[0].mData else { return Array(repeating: Array(repeating: 0, count: frames), count: channels) }
            let pointer = data.assumingMemoryBound(to: Float.self)
            return (0..<channels).map { channel in
                (0..<frames).map { frame in
                    pointer[frame * channels + channel]
                }
            }
        } else {
            return (0..<channels).map { channel in
                guard let data = buffers[channel].mData else { return Array(repeating: 0, count: frames) }
                let pointer = data.assumingMemoryBound(to: Float.self)
                return (0..<frames).map { frame in
                    pointer[frame]
                }
            }
        }
    }
}
#endif
