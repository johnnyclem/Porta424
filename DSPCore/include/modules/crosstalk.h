#pragma once

#include <algorithm>
#include <cmath>
#include "module.h"

class Crosstalk : public Module {
public:
    void prepare(float sampleRate, int maxBlockSize) override {
        (void)sampleRate;
        (void)maxBlockSize;
    }

    void setAmountDb(float db) {
        amountLinear = std::pow(10.0f, db / 20.0f);
    }

    void processBlock(float* interleavedBuffer, int numFrames, int numChannels) override {
        if (!interleavedBuffer || numFrames <= 0 || numChannels < 2) {
            return;
        }

        for (int i = 0; i < numFrames; ++i) {
            float sum = 0.0f;
            for (int c = 0; c < numChannels; ++c) {
                sum += interleavedBuffer[i * numChannels + c];
            }
            float average = sum / static_cast<float>(numChannels);
            for (int c = 0; c < numChannels; ++c) {
                int idx = i * numChannels + c;
                interleavedBuffer[idx] += amountLinear * (average - interleavedBuffer[idx]);
            }
        }
    }

private:
    float amountLinear{0.0f};
};

