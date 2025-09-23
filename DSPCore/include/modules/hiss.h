#pragma once

#include <algorithm>
#include <cmath>
#include <random>
#include "module.h"

class Hiss : public Module {
public:
    void prepare(float sampleRate, int maxBlockSize) override {
        (void)sampleRate;
        (void)maxBlockSize;
        updateLevel();
    }

    void setLevelDbFS(float db) {
        levelDb = db;
        updateLevel();
    }

    void reset() override {
        rng.seed(12345u);
    }

    void processBlock(float* interleavedBuffer, int numFrames, int numChannels) override {
        if (!interleavedBuffer || numFrames <= 0 || numChannels <= 0) {
            return;
        }

        for (int i = 0; i < numFrames; ++i) {
            for (int c = 0; c < numChannels; ++c) {
                int idx = i * numChannels + c;
                interleavedBuffer[idx] += distribution(rng) * levelLinear;
            }
        }
    }

private:
    float levelDb{-70.0f};
    float levelLinear{0.0f};
    std::mt19937 rng{12345u};
    std::normal_distribution<float> distribution{0.0f, 1.0f};

    void updateLevel() {
        levelLinear = std::pow(10.0f, levelDb / 20.0f);
    }
};

