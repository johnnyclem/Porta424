#pragma once

#include <algorithm>
#include <vector>
#include "module.h"
#include "biquad.h"

class EQ : public Module {
public:
    void prepare(float sampleRate, int maxBlockSize) override {
        (void)maxBlockSize;
        fs = sampleRate;
        resetChannels(2);
    }

    void reset() override {
        resetChannels(currentChannels);
    }

    void setLowGainDb(float db) {
        lowGainDb = db;
        updateCoefficients();
    }

    void setMidGainDb(float db) {
        midGainDb = db;
        updateCoefficients();
    }

    void setHighGainDb(float db) {
        highGainDb = db;
        updateCoefficients();
    }

    void setMidFrequency(float freq) {
        midFrequency = std::clamp(freq, 200.0f, fs * 0.45f);
        updateCoefficients();
    }

    void setMidQ(float qValue) {
        midQ = std::clamp(qValue, 0.2f, 10.0f);
        updateCoefficients();
    }

    void processBlock(float* interleavedBuffer, int numFrames, int numChannels) override {
        if (!interleavedBuffer || numFrames <= 0 || numChannels <= 0) {
            return;
        }

        ensureStateSize(numChannels);
        for (int i = 0; i < numFrames; ++i) {
            for (int c = 0; c < numChannels; ++c) {
                int idx = i * numChannels + c;
                float sample = interleavedBuffer[idx];
                sample = lowShelfStates[c].process(sample);
                sample = peakStates[c].process(sample);
                sample = highShelfStates[c].process(sample);
                interleavedBuffer[idx] = sample;
            }
        }
    }

private:
    float fs{48000.0f};
    float lowGainDb{0.0f};
    float midGainDb{0.0f};
    float highGainDb{0.0f};
    float midFrequency{1000.0f};
    float midQ{0.7071f};

    std::vector<Biquad> lowShelfStates;
    std::vector<Biquad> peakStates;
    std::vector<Biquad> highShelfStates;
    int currentChannels{2};

    void ensureStateSize(int channels) {
        if (channels > currentChannels) {
            resetChannels(channels);
        }
    }

    void resetChannels(int channels) {
        currentChannels = std::max(1, channels);
        lowShelfStates.assign(currentChannels, Biquad{});
        peakStates.assign(currentChannels, Biquad{});
        highShelfStates.assign(currentChannels, Biquad{});
        updateCoefficients();
    }

    void updateCoefficients() {
        Biquad lowTemplate;
        Biquad peakTemplate;
        Biquad highTemplate;
        lowTemplate.setLowShelf(fs, 120.0f, lowGainDb);
        peakTemplate.setPeaking(fs, midFrequency, midGainDb, midQ);
        highTemplate.setHighShelf(fs, 6000.0f, highGainDb);

        for (auto& b : lowShelfStates) {
            b = lowTemplate;
            b.reset();
        }
        for (auto& b : peakStates) {
            b = peakTemplate;
            b.reset();
        }
        for (auto& b : highShelfStates) {
            b = highTemplate;
            b.reset();
        }
    }
};

