#pragma once

/**
 * Lightweight interface implemented by all DSP modules in this project. The
 * API mirrors the lifecycle used by common audio hosts: prepare → optional
 * reset → repeated processBlock calls.
 */
class Module {
public:
    virtual ~Module() = default;

    /** Allocate/resize any internal buffers before processing starts. */
    virtual void prepare(float sampleRate, int maxBlockSize) = 0;

    /** Optional hook to clear state (e.g. when seeking). */
    virtual void reset() {}

    /**
     * Process an interleaved buffer in place.
     * @param interleavedBuffer pointer to interleaved audio data
     * @param numFrames number of frames in the buffer
     * @param numChannels number of channels contained in the interleaved data
     */
    virtual void processBlock(float* interleavedBuffer, int numFrames, int numChannels) = 0;
};

