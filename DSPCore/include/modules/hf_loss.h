#pragma once

#include <algorithm>
#include <cmath>
#include <vector>
#include "module.h"

class HFLoss : public Module {
public:
    void prepare(float sampleRate, int maxBlockSize) override {
        (void)maxBlockSize;
        fs = sampleRate;
        states.assign(8, 0.0f);
        setCutoffHz(cutoffHz);
    }

    void setCutoffHz(float cutoff) {
        cutoffHz = std::clamp(cutoff, 1000.0f, fs * 0.49f);
        const float omega = 2.0f * static_cast<float>(M_PI) * cutoffHz / std::max(fs, 1.0f);
        alpha = 1.0f - std::exp(-omega);
    }

    void setMix(float m) {
        mix = std::clamp(m, 0.0f, 1.0f);
    }

    void reset() override {
        std::fill(states.begin(), states.end(), 0.0f);
    }

    void processBlock(float* interleavedBuffer, int numFrames, int numChannels) override {
        if (!interleavedBuffer || numFrames <= 0 || numChannels <= 0) {
            return;
        }

        ensureStateSize(numChannels);
        for (int i = 0; i < numFrames; ++i) {
            for (int c = 0; c < numChannels; ++c) {
                int idx = i * numChannels + c;
                float x = interleavedBuffer[idx];
                float& state = states[c];
                state += alpha * (x - state);
                float filtered = state;
                interleavedBuffer[idx] = x + mix * (filtered - x);
            }
        }
    }

private:
    float fs{48000.0f};
    float cutoffHz{8000.0f};
    float alpha{0.0f};
    float mix{1.0f};
    std::vector<float> states{8, 0.0f};

    void ensureStateSize(int channels) {
        if ((int)states.size() < channels) {
            states.assign(channels, 0.0f);
        }
    }
};

class HFLoss {
public:
    void prepare(float sampleRate, int maxChannels);
    void reset();

    void setCutoff(float cutoffHz);

    void process(float* interleaved, int frames, int channels);

private:
    struct ChannelState {
        float stage1 = 0.0f;
        float stage2 = 0.0f;
    };

    float sampleRate_ = 48000.0f;
    float cutoffTarget_ = 20000.0f;
    float gTarget_ = 1.0f;
    float gCurrent_ = 1.0f;

    std::vector<ChannelState> channels_;

    static float computeOnePoleCoefficient(float cutoffHz, float sampleRate);
    float smoothingAlpha(int frames) const;
};

inline void HFLoss::prepare(float sampleRate, int maxChannels) {
    sampleRate_ = std::max(sampleRate, 1.0f);
    channels_.assign(std::max(maxChannels, 1), ChannelState{});
    setCutoff(cutoffTarget_);
    gCurrent_ = gTarget_;
    reset();
}

inline void HFLoss::reset() {
    for (auto& ch : channels_) {
        ch.stage1 = 0.0f;
        ch.stage2 = 0.0f;
    }
}

inline void HFLoss::setCutoff(float cutoffHz) {
    cutoffTarget_ = std::clamp(cutoffHz, 20.0f, sampleRate_ * 0.49f);
    gTarget_ = computeOnePoleCoefficient(cutoffTarget_, sampleRate_);
}

inline float HFLoss::computeOnePoleCoefficient(float cutoffHz, float sampleRate) {
    float nyquist = sampleRate * 0.5f;
    if (cutoffHz >= nyquist * 0.98f) {
        return 1.0f;
    }
    float omega = 2.0f * static_cast<float>(M_PI) * std::max(cutoffHz, 1.0f) / sampleRate;
    float expTerm = std::exp(-omega);
    return 1.0f - expTerm;
}

inline float HFLoss::smoothingAlpha(int frames) const {
    if (frames <= 0) {
        return 1.0f;
    }
    constexpr float smoothingTime = 0.02f; // 20 ms time constant
    float blockTime = static_cast<float>(frames) / sampleRate_;
    float alpha = 1.0f - std::exp(-blockTime / smoothingTime);
    return std::clamp(alpha, 0.0f, 1.0f);
}

inline void HFLoss::process(float* interleaved, int frames, int channels) {
    if (!interleaved || frames <= 0 || channels <= 0) {
        return;
    }

    if ((int)channels_.size() < channels) {
        channels_.resize(channels);
    }

    float alpha = smoothingAlpha(frames);
    gCurrent_ += (gTarget_ - gCurrent_) * alpha;

    float g = gCurrent_;

    for (int frame = 0; frame < frames; ++frame) {
        for (int ch = 0; ch < channels; ++ch) {
            auto& state = channels_[ch];
            int idx = frame * channels + ch;
            float x = interleaved[idx];

            state.stage1 += g * (x - state.stage1);
            state.stage2 += g * (state.stage1 - state.stage2);
            interleaved[idx] = state.stage2;
        }
    }
}

