#pragma once

#include <algorithm>
#include <cmath>
#include "module.h"

class Compander : public Module {
public:
    void prepare(float sampleRate, int maxBlockSize) override {
        (void)maxBlockSize;
        fs = sampleRate;
        reset();
        updateCoefficients();
    }

    void reset() override {
        envelope = 1.0e-6f;
    }

    void setThresholdDb(float db) {
        thresholdDb = db;
    }

    void setRatio(float r) {
        ratio = std::max(1.0f, r);
    }

    void setAttackMs(float ms) {
        attackMs = std::max(0.1f, ms);
        updateCoefficients();
    }

    void setReleaseMs(float ms) {
        releaseMs = std::max(0.1f, ms);
        updateCoefficients();
    }

    void processBlock(float* interleavedBuffer, int numFrames, int numChannels) override {
        if (!interleavedBuffer || numFrames <= 0 || numChannels <= 0) {
            return;
        }

        for (int i = 0; i < numFrames; ++i) {
            float detector = 0.0f;
            for (int c = 0; c < numChannels; ++c) {
                detector += std::fabs(interleavedBuffer[i * numChannels + c]);
            }
            detector /= static_cast<float>(numChannels);
            detector = std::max(detector, 1.0e-6f);

            float coeff = detector > envelope ? attackCoef : releaseCoef;
            envelope = coeff * envelope + (1.0f - coeff) * detector;

            float envDb = 20.0f * std::log10(envelope);
            float gainDb = 0.0f;
            if (envDb > thresholdDb) {
                float compressed = thresholdDb + (envDb - thresholdDb) / ratio;
                gainDb = compressed - envDb;
            }

            float gain = std::pow(10.0f, gainDb / 20.0f);
            for (int c = 0; c < numChannels; ++c) {
                int idx = i * numChannels + c;
                interleavedBuffer[idx] *= gain;
            }
        }
    }

private:
    float fs{48000.0f};
    float thresholdDb{-18.0f};
    float ratio{2.0f};
    float attackMs{10.0f};
    float releaseMs{100.0f};
    float attackCoef{0.0f};
    float releaseCoef{0.0f};
    float envelope{1.0e-6f};

    void updateCoefficients() {
        attackCoef = std::exp(-1.0f / ((attackMs / 1000.0f) * std::max(fs, 1.0f)));
        releaseCoef = std::exp(-1.0f / ((releaseMs / 1000.0f) * std::max(fs, 1.0f)));
    }

};

