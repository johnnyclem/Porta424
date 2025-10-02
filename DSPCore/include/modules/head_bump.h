#pragma once

#include <algorithm>
#include <cmath>
#include <vector>
#include "module.h"

class HeadBump : public Module {
public:
    void prepare(float sampleRate, int maxBlockSize) override {
        (void)maxBlockSize;
        fs = sampleRate;
        lowStates.assign(8, 0.0f);
        updateCoefficients();
    }

    void setFrequency(float frequencyHz) {
        freq = std::clamp(frequencyHz, 10.0f, fs * 0.45f);
        updateCoefficients();
    }

    void setGainDb(float gain) {
        gainDb = gain;
        updateCoefficients();
    }

    void setMix(float m) {
        mix = std::clamp(m, 0.0f, 1.0f);
    }

    void reset() override {
        std::fill(lowStates.begin(), lowStates.end(), 0.0f);
    }

    void processBlock(float* interleavedBuffer, int numFrames, int numChannels) override {
        if (!interleavedBuffer || numFrames <= 0 || numChannels <= 0) {
            return;
        }

        ensureStateSize(numChannels);
        for (int i = 0; i < numFrames; ++i) {
            for (int c = 0; c < numChannels; ++c) {
                const int idx = i * numChannels + c;
                float x = interleavedBuffer[idx];
                float& state = lowStates[c];
                state += alpha * (x - state);
                float bumped = x + (gainLinear - 1.0f) * state;
                interleavedBuffer[idx] = x + mix * (bumped - x);
            }
        }
    }

private:
    float fs{48000.0f};
    float freq{60.0f};
    float gainDb{3.0f};
    float mix{1.0f};
    float alpha{0.0f};
    float gainLinear{1.0f};
    std::vector<float> lowStates{8, 0.0f};

    void ensureStateSize(int channels) {
        if ((int)lowStates.size() < channels) {
            lowStates.assign(channels, 0.0f);
        }
    }

    void updateCoefficients() {
        gainLinear = std::pow(10.0f, gainDb / 20.0f);
        const float omega = 2.0f * static_cast<float>(M_PI) * freq / std::max(fs, 1.0f);
        alpha = 1.0f - std::exp(-omega);
    }

class HeadBump {
public:
    void prepare(float sampleRate, int channels) {
        if (sampleRate > 0.0f) {
            sampleRate_ = sampleRate;
        }
        if (channels < 1) {
            channels = 1;
        }

        if (static_cast<int>(filters_.size()) != channels) {
            filters_.assign(static_cast<size_t>(channels), Filter{});
        } else {
            for (auto& filter : filters_) {
                filter.resetState();
            }
        }

        updateSmoothingCoefficient();
        auto unity = Coeffs::unity();
        for (auto& filter : filters_) {
            filter.setImmediate(unity);
        }
    }

    void reset() {
        for (auto& filter : filters_) {
            filter.resetState();
        }
    }

    void setParams(float freqHz, float gainDb) {
        if (filters_.empty()) {
            return;
        }

        if (!std::isfinite(freqHz)) {
            freqHz = defaultFrequency();
        }
        if (!std::isfinite(gainDb)) {
            gainDb = 0.0f;
        }

        freqHz = std::clamp(freqHz, minFrequency(), maxFrequency());
        if (std::fabs(gainDb) < 1.0e-4f) {
            auto unity = Coeffs::unity();
            for (auto& filter : filters_) {
                filter.setTarget(unity);
            }
            return;
        }

        auto coeffs = designPeaking(freqHz, gainDb);
        for (auto& filter : filters_) {
            filter.setTarget(coeffs);
        }
    }

    float processSample(float x, int channel) {
        if (filters_.empty()) {
            return x;
        }
        int idx = std::clamp(channel, 0, static_cast<int>(filters_.size()) - 1);
        return filters_[static_cast<size_t>(idx)].process(x, smoothingCoeff_);
    }

    int channelCount() const {
        return static_cast<int>(filters_.size());
    }

private:
    struct Coeffs {
        float b0;
        float b1;
        float b2;
        float a1;
        float a2;

        static Coeffs unity() {
            return {1.0f, 0.0f, 0.0f, 0.0f, 0.0f};
        }
    };

    struct Filter {
        Coeffs current;
        Coeffs target;
        float z1;
        float z2;

        Filter()
        : current(Coeffs::unity()),
          target(Coeffs::unity()),
          z1(0.0f),
          z2(0.0f) {}

        void setTarget(const Coeffs& coeffs) {
            target = coeffs;
        }

        void setImmediate(const Coeffs& coeffs) {
            current = coeffs;
            target = coeffs;
        }

        void resetState() {
            z1 = 0.0f;
            z2 = 0.0f;
        }

        float process(float input, float smoothing) {
            if (smoothing > 0.0f && smoothing < 1.0f) {
                current.b0 += smoothing * (target.b0 - current.b0);
                current.b1 += smoothing * (target.b1 - current.b1);
                current.b2 += smoothing * (target.b2 - current.b2);
                current.a1 += smoothing * (target.a1 - current.a1);
                current.a2 += smoothing * (target.a2 - current.a2);
            } else {
                current = target;
            }

            float y = current.b0 * input + z1;
            float newZ1 = current.b1 * input - current.a1 * y + z2;
            float newZ2 = current.b2 * input - current.a2 * y;

            if (std::fabs(newZ1) < denormalLimit()) {
                newZ1 = 0.0f;
            }
            if (std::fabs(newZ2) < denormalLimit()) {
                newZ2 = 0.0f;
            }

            z1 = newZ1;
            z2 = newZ2;

            if (!std::isfinite(y)) {
                return 0.0f;
            }
            return y;
        }
    };

    float maxFrequency() const {
        return 0.45f * sampleRate_;
    }

    static constexpr float minFrequency() {
        return 10.0f;
    }

    static constexpr float defaultFrequency() {
        return 80.0f;
    }

    static constexpr float denormalLimit() {
        return 1.0e-20f;
    }

    void updateSmoothingCoefficient() {
        constexpr float smoothingTimeSeconds = 0.02f; // ~20 ms
        if (sampleRate_ <= 0.0f) {
            smoothingCoeff_ = 1.0f;
            return;
        }
        float alpha = -1.0f / (sampleRate_ * smoothingTimeSeconds);
        smoothingCoeff_ = 1.0f - std::exp(alpha);
        if (!std::isfinite(smoothingCoeff_) || smoothingCoeff_ < 0.0f) {
            smoothingCoeff_ = 1.0f;
        } else if (smoothingCoeff_ > 1.0f) {
            smoothingCoeff_ = 1.0f;
        }
    }

    Coeffs designPeaking(float freqHz, float gainDb) const {
        constexpr float qValue = 1.4f;
        constexpr float pi = 3.14159265358979323846f;
        float omega = 2.0f * pi * freqHz / sampleRate_;
        omega = std::clamp(omega, 0.0f, pi);
        float sinw = std::sin(omega);
        float cosw = std::cos(omega);
        float alpha = sinw / (2.0f * qValue);
        float a = std::pow(10.0f, gainDb / 40.0f);

        float b0 = 1.0f + alpha * a;
        float b1 = -2.0f * cosw;
        float b2 = 1.0f - alpha * a;
        float a0 = 1.0f + alpha / a;
        float a1 = -2.0f * cosw;
        float a2 = 1.0f - alpha / a;

        if (std::fabs(a0) < 1.0e-8f) {
            return Coeffs::unity();
        }

        b0 /= a0;
        b1 /= a0;
        b2 /= a0;
        a1 /= a0;
        a2 /= a0;

        return {b0, b1, b2, a1, a2};
    }

    float sampleRate_ = 48000.0f;
    float smoothingCoeff_ = 1.0f;
    std::vector<Filter> filters_;
};

