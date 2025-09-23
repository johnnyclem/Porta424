#pragma once

#include <algorithm>
#include <random>
#include "module.h"

class Dropouts : public Module {
public:
    void prepare(float sampleRate, int maxBlockSize) override {
        fs = sampleRate;
        (void)maxBlockSize;
        updateProbability();
    }

    void setRatePerMinute(float rate) {
        dropoutRatePerMinute = std::max(0.0f, rate);
        updateProbability();
    }

    void setDropoutDurationMs(float ms) {
        dropoutDurationMs = std::max(1.0f, ms);
        updateProbability();
    }

    void reset() override {
        remainingDropoutSamples = 0;
        rng.seed(5489u);
    }

    void processBlock(float* interleavedBuffer, int numFrames, int numChannels) override {
        if (!interleavedBuffer || numFrames <= 0 || numChannels <= 0) {
            return;
        }

        for (int i = 0; i < numFrames; ++i) {
            if (remainingDropoutSamples > 0) {
                --remainingDropoutSamples;
                for (int c = 0; c < numChannels; ++c) {
                    interleavedBuffer[i * numChannels + c] = 0.0f;
                }
                continue;
            }

            if (dist(rng) < dropoutProbabilityPerSample) {
                remainingDropoutSamples = dropoutLengthSamples;
                for (int c = 0; c < numChannels; ++c) {
                    interleavedBuffer[i * numChannels + c] = 0.0f;
                }
            }
        }
    }

private:
    float fs{48000.0f};
    float dropoutRatePerMinute{0.1f};
    float dropoutDurationMs{15.0f};
    float dropoutProbabilityPerSample{0.0f};
    int dropoutLengthSamples{1};
    int remainingDropoutSamples{0};
    std::mt19937 rng{5489u};
    std::uniform_real_distribution<float> dist{0.0f, 1.0f};

    void updateProbability() {
        float ratePerSecond = dropoutRatePerMinute / 60.0f;
        dropoutProbabilityPerSample = ratePerSecond / std::max(fs, 1.0f);
        dropoutLengthSamples = static_cast<int>(dropoutDurationMs * 0.001f * fs);
        if (dropoutLengthSamples < 1) dropoutLengthSamples = 1;
    }
};

