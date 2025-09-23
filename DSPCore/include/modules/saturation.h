#pragma once

#include <algorithm>
#include <cmath>
#include "module.h"

class Saturation : public Module {
public:
    void prepare(float sampleRate, int maxBlockSize) override {
        (void)maxBlockSize;
        fs = sampleRate;
        update();
    }

    void setDriveDb(float db) {
        driveDb = db;
        update();
    }

    void setOutputGainDb(float db) {
        outputGainDb = db;
        update();
    }

    void processBlock(float* interleavedBuffer, int numFrames, int numChannels) override {
        if (!interleavedBuffer || numFrames <= 0 || numChannels <= 0) {
            return;
        }

        for (int i = 0; i < numFrames; ++i) {
            for (int c = 0; c < numChannels; ++c) {
                const int idx = i * numChannels + c;
                float x = interleavedBuffer[idx];
                const float driven = x * driveLinear;
                float y = std::tanh(driven);
                interleavedBuffer[idx] = y * outputGainLinear;
            }
        }
    }

private:
    float fs{48000.0f};
    float driveDb{0.0f};
    float outputGainDb{0.0f};
    float driveLinear{1.0f};
    float outputGainLinear{1.0f};

    void update() {
        driveLinear = std::pow(10.0f, driveDb / 20.0f);
        outputGainLinear = std::pow(10.0f, outputGainDb / 20.0f);
    }
};

