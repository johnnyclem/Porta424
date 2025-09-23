#pragma once

#include <algorithm>
#include <cmath>
#include <vector>
#include "module.h"

class HeadBump : public Module {
public:
    void prepare(float sampleRate, int maxBlockSize) override {
        (void)maxBlockSize;
        fs = sampleRate;
        lowStates.assign(8, 0.0f);
        updateCoefficients();
    }

    void setFrequency(float frequencyHz) {
        freq = std::clamp(frequencyHz, 10.0f, fs * 0.45f);
        updateCoefficients();
    }

    void setGainDb(float gain) {
        gainDb = gain;
        updateCoefficients();
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
                const int idx = i * numChannels + c;
                float x = interleavedBuffer[idx];
                float& state = lowStates[c];
                state += alpha * (x - state);
                float bumped = x + (gainLinear - 1.0f) * state;
                interleavedBuffer[idx] = x + mix * (bumped - x);
            }
        }
    }

private:
    float fs{48000.0f};
    float freq{60.0f};
    float gainDb{3.0f};
    float mix{1.0f};
    float alpha{0.0f};
    float gainLinear{1.0f};
    std::vector<float> lowStates{8, 0.0f};

    void ensureStateSize(int channels) {
        if ((int)lowStates.size() < channels) {
            lowStates.assign(channels, 0.0f);
        }
    }

    void updateCoefficients() {
        gainLinear = std::pow(10.0f, gainDb / 20.0f);
        const float omega = 2.0f * static_cast<float>(M_PI) * freq / std::max(fs, 1.0f);
        alpha = 1.0f - std::exp(-omega);
    }
};

