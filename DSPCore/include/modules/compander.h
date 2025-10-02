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
#include <cstdint>
#include <vector>

class Compander {
public:
    Compander() = default;

    void prepare(float sampleRate, int channels) {
        sampleRate_ = sampleRate > 1.0f ? sampleRate : 1.0f;
        setChannelCount(channels);
        updateCoefficients();
    }

    void setChannelCount(int channels) {
        const int count = std::max(channels, 1);
        if ((int)states_.size() != count) {
            states_.assign(count, ChannelState{});
            bypassMask_.assign(count, 0);
        }
    }

    void setTrackBypass(int trackIndex, bool bypass) {
        if (trackIndex < 0) {
            return;
        }
        if (trackIndex >= (int)bypassMask_.size()) {
            setChannelCount(trackIndex + 1);
        }
        bypassMask_[trackIndex] = bypass ? 1 : 0;
    }

    void process(float* interleaved, int frames, int channels) {
        if (!interleaved || frames <= 0 || channels <= 0) {
            return;
        }

        if (channels != (int)states_.size()) {
            setChannelCount(channels);
        }

        for (int i = 0; i < frames; ++i) {
            for (int c = 0; c < channels; ++c) {
                if (c >= (int)states_.size() || bypassMask_[c]) {
                    continue;
                }

                const int index = i * channels + c;
                float sample = interleaved[index];
                float level = std::fabs(sample);
                level = std::max(level, detectorFloor_);

                ChannelState& state = states_[c];
                if (level > state.envelope) {
                    state.envelope = attackCoeff_ * (state.envelope - level) + level;
                } else {
                    state.envelope = releaseCoeff_ * (state.envelope - level) + level;
                }
                state.envelope = std::max(state.envelope, detectorFloor_);

                const float envDb = linearToDb(state.envelope);
                const float gainDb = compressionGain(envDb) + makeupGainDb_;
                const float targetGain = dbToLinear(gainDb);

                state.gain = gainSmoothing_ * state.gain + (1.0f - gainSmoothing_) * targetGain;
                interleaved[index] = sample * state.gain;
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

    struct ChannelState {
        float envelope = 1e-3f;
        float gain = 1.0f;
    };

    void updateCoefficients() {
        const float attackSeconds = 0.050f;
        const float releaseSeconds = 0.250f;
        attackCoeff_ = std::exp(-1.0f / (attackSeconds * sampleRate_));
        releaseCoeff_ = std::exp(-1.0f / (releaseSeconds * sampleRate_));
        gainSmoothing_ = std::exp(-1.0f / (0.020f * sampleRate_));
    }

    static float linearToDb(float value) {
        return 20.0f * std::log10(value);
    }

    static float dbToLinear(float db) {
        return std::pow(10.0f, db / 20.0f);
    }

    float compressionGain(float envDb) const {
        const float lowerKnee = thresholdDb_ - 0.5f * kneeWidthDb_;
        const float upperKnee = thresholdDb_ + 0.5f * kneeWidthDb_;

        if (envDb <= lowerKnee) {
            return 0.0f;
        }
        if (envDb >= upperKnee) {
            const float compressed = thresholdDb_ + (envDb - thresholdDb_) / ratio_;
            return compressed - envDb;
        }

        const float delta = envDb - lowerKnee;
        const float knee = kneeWidthDb_;
        const float softness = delta * delta / (2.0f * knee);
        return (1.0f / ratio_ - 1.0f) * softness;
    }

    float sampleRate_ = 48000.0f;
    std::vector<ChannelState> states_;
    std::vector<uint8_t> bypassMask_;

    float attackCoeff_ = 0.0f;
    float releaseCoeff_ = 0.0f;
    float gainSmoothing_ = 0.0f;

    static constexpr float detectorFloor_ = 1e-5f;
    static constexpr float thresholdDb_ = -24.0f;
    static constexpr float kneeWidthDb_ = 8.0f;
    static constexpr float ratio_ = 3.0f;
    static constexpr float makeupGainDb_ = 4.0f;
};

