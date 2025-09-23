#pragma once

#include <algorithm>
#include <cmath>
#include "module.h"

class Azimuth : public Module {
public:
    void prepare(float sampleRate, int maxBlockSize) override {
        (void)sampleRate;
        (void)maxBlockSize;
        updateMatrix();
    }

    void setAngleDegrees(float degrees) {
        angleDegrees = degrees;
        updateMatrix();
    }

    void setDepth(float d) {
        depth = std::clamp(d, 0.0f, 1.0f);
        updateMatrix();
    }

    void reset() override {
        updateMatrix();
    }

    void processBlock(float* interleavedBuffer, int numFrames, int numChannels) override {
        if (!interleavedBuffer || numFrames <= 0 || numChannels < 2) {
            return;
        }

        for (int i = 0; i < numFrames; ++i) {
            float* left = &interleavedBuffer[i * numChannels];
            float* right = &interleavedBuffer[i * numChannels + 1];
            float l = *left;
            float r = *right;
            float newL = matrix00 * l + matrix01 * r;
            float newR = matrix10 * l + matrix11 * r;
            *left = newL;
            *right = newR;
        }
    }

private:
    float angleDegrees{0.0f};
    float depth{1.0f};
    float matrix00{1.0f};
    float matrix01{0.0f};
    float matrix10{0.0f};
    float matrix11{1.0f};

    void updateMatrix() {
        const float radians = angleDegrees * static_cast<float>(M_PI) / 180.0f;
        const float c = std::cos(radians);
        const float s = std::sin(radians) * depth;
        matrix00 = c;
        matrix01 = s;
        matrix10 = -s;
        matrix11 = c;
    }
};

