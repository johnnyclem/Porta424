#pragma once

#include <algorithm>
#include <cmath>
#include <vector>
#include "module.h"

class HFLoss : public Module {
public:
    void prepare(float sampleRate, int maxBlockSize) override {
        (void)maxBlockSize;
        fs = sampleRate;
        states.assign(8, 0.0f);
        setCutoffHz(cutoffHz);
    }

    void setCutoffHz(float cutoff) {
        cutoffHz = std::clamp(cutoff, 1000.0f, fs * 0.49f);
        const float omega = 2.0f * static_cast<float>(M_PI) * cutoffHz / std::max(fs, 1.0f);
        alpha = 1.0f - std::exp(-omega);
    }

    void setMix(float m) {
        mix = std::clamp(m, 0.0f, 1.0f);
    }

    void processBlock(float* interleavedBuffer, int numFrames, int numChannels) override {
        if (!interleavedBuffer || numFrames <= 0 || numChannels <= 0) {
            return;
        }

        ensureStateSize(numChannels);
        for (int i = 0; i < numFrames; ++i) {
            for (int c = 0; c < numChannels; ++c) {
                int idx = i * numChannels + c;
                float x = interleavedBuffer[idx];
                float& state = states[c];
                state += alpha * (x - state);
                float filtered = state;
                interleavedBuffer[idx] = x + mix * (filtered - x);
            }
        }
    }

private:
    float fs{48000.0f};
    float cutoffHz{8000.0f};
    float alpha{0.0f};
    float mix{1.0f};
    std::vector<float> states{8, 0.0f};

    void ensureStateSize(int channels) {
        if ((int)states.size() < channels) {
            states.assign(channels, 0.0f);
        }
    }
};

