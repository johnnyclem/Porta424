#pragma once

class Module {
public:
    virtual ~Module() = default;
    virtual void prepare(float sampleRate, int maxBlockSize) = 0;
    virtual void processBlock(float* interleavedBuffer, int numFrames, int numChannels) = 0;
};

