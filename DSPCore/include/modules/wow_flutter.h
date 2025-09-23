#pragma once

#include <algorithm>
#include <cmath>
#include "module.h"

class WowFlutter : public Module {
public:
    void prepare(float sampleRate, int maxBlockSize) override {
        (void)maxBlockSize;
        fs = sampleRate;
        resetPhase();
        updateIncrements();
    }

    void setWowDepth(float depth) {
        wowDepth = depth;
    }

    void setFlutterDepth(float depth) {
        flutterDepth = depth;
    }

    void setWowRate(float rateHz) {
        wowRate = rateHz;
        updateIncrements();
    }

    void setFlutterRate(float rateHz) {
        flutterRate = rateHz;
        updateIncrements();
    }

    void reset() override {
        resetPhase();
    }

    void processBlock(float* interleavedBuffer, int numFrames, int numChannels) override {
        if (!interleavedBuffer || numFrames <= 0 || numChannels <= 0) {
            return;
        }

        for (int i = 0; i < numFrames; ++i) {
            float wowMod = std::sin(wowPhase);
            float flutterMod = std::sin(flutterPhase);
            float modulation = 1.0f + wowDepth * wowMod + flutterDepth * flutterMod;

            for (int c = 0; c < numChannels; ++c) {
                const int idx = i * numChannels + c;
                interleavedBuffer[idx] *= modulation;
            }

            advancePhase();
        }
    }

private:
    float fs{48000.0f};
    float wowDepth{0.0006f};
    float flutterDepth{0.0003f};
    float wowRate{0.6f};
    float flutterRate{6.0f};
    float wowPhase{0.0f};
    float flutterPhase{0.0f};
    float wowIncrement{0.0f};
    float flutterIncrement{0.0f};

    void resetPhase() {
        wowPhase = 0.0f;
        flutterPhase = 0.0f;
    }

    void updateIncrements() {
        const float twoPi = 2.0f * static_cast<float>(M_PI);
        wowIncrement = twoPi * wowRate / std::max(fs, 1.0f);
        flutterIncrement = twoPi * flutterRate / std::max(fs, 1.0f);
    }

    void advancePhase() {
        wowPhase += wowIncrement;
        flutterPhase += flutterIncrement;
        const float twoPi = 2.0f * static_cast<float>(M_PI);
        if (wowPhase > twoPi) wowPhase -= twoPi;
        if (flutterPhase > twoPi) flutterPhase -= twoPi;
    }
};

