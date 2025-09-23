#pragma once

#include <algorithm>
#include <cmath>
#include <vector>
#include "module.h"

class Meters : public Module {
public:
    void prepare(float sampleRate, int maxBlockSize) override {
        (void)sampleRate;
        (void)maxBlockSize;
        currentChannels = 2;
        resetChannels(currentChannels);
    }

    void reset() override {
        resetChannels(currentChannels);
    }

    void clear() {
        std::fill(rmsAcc.begin(), rmsAcc.end(), 0.0f);
        std::fill(peak.begin(), peak.end(), 0.0f);
        sampleCount = 0;
    }

    void processBlock(float* interleavedBuffer, int numFrames, int numChannels) override {
        if (!interleavedBuffer || numFrames <= 0 || numChannels <= 0) {
            return;
        }

        if ((int)rmsAcc.size() != numChannels) {
            currentChannels = numChannels;
            resetChannels(currentChannels);
        }

        for (int i = 0; i < numFrames; ++i) {
            for (int c = 0; c < numChannels; ++c) {
                int idx = i * numChannels + c;
                float sample = interleavedBuffer[idx];
                rmsAcc[c] += sample * sample;
                peak[c] = std::max(peak[c], std::fabs(sample));
            }
            ++sampleCount;
        }
    }

    float rmsDb(int channel) const {
        if (channel < 0 || channel >= static_cast<int>(rmsAcc.size()) || sampleCount == 0) {
            return -120.0f;
        }
        float rms = std::sqrt(rmsAcc[channel] / static_cast<float>(sampleCount));
        return linearToDb(rms);
    }

    float peakDb(int channel) const {
        if (channel < 0 || channel >= static_cast<int>(peak.size())) {
            return -120.0f;
        }
        return linearToDb(peak[channel]);
    }

    int channels() const {
        return static_cast<int>(rmsAcc.size());
    }

private:
    std::vector<float> rmsAcc;
    std::vector<float> peak;
    int sampleCount{0};
    int currentChannels{2};

    void resetChannels(int channels) {
        int clamped = std::max(1, channels);
        rmsAcc.assign(clamped, 0.0f);
        peak.assign(clamped, 0.0f);
        sampleCount = 0;
    }

    static float linearToDb(float value) {
        return value > 1.0e-9f ? 20.0f * std::log10(value) : -120.0f;
    }
};

