#pragma once

#include <algorithm>
#include <cmath>

class Biquad {
public:
    static constexpr float pi = 3.14159265358979323846f;
    struct Coefficients {
        float b0 = 1.0f;
        float b1 = 0.0f;
        float b2 = 0.0f;
        float a1 = 0.0f;
        float a2 = 0.0f;

        static Coefficients identity() { return {1.0f, 0.0f, 0.0f, 0.0f, 0.0f}; }
    };

    void prepare(float sampleRate) {
        sampleRate_ = sampleRate > 0.0f ? sampleRate : 48000.0f;
        reset();
    }

    void reset() {
        z1_ = 0.0f;
        z2_ = 0.0f;
    }

    void setCoefficients(const Coefficients& coeffs) { coeffs_ = coeffs; }

    float processSample(float x) {
        const float y = coeffs_.b0 * x + coeffs_.b1 * z1_ + coeffs_.b2 * z2_ - coeffs_.a1 * y1_ - coeffs_.a2 * y2_;
        z2_ = z1_;
        z1_ = x;
        y2_ = y1_;
        y1_ = y;
        return y;
    }

    float sampleRate() const { return sampleRate_; }

    void setSampleRate(float sampleRate) { sampleRate_ = sampleRate > 0.0f ? sampleRate : sampleRate_; }

    static Coefficients designLowShelf(float sampleRate, float freqHz, float gainDb, float slope = 1.0f) {
        if (sampleRate <= 0.0f) {
            return Coefficients::identity();
        }

        float clampedFreq = std::clamp(freqHz, 0.0f, 0.5f * sampleRate);
        float w0 = 2.0f * pi * clampedFreq / sampleRate;
        float cosw = std::cos(w0);
        float sinw = std::sin(w0);

        float A = gainToA(gainDb);
        float S = std::max(slope, 1.0e-6f);
        float alpha = sinw / 2.0f * std::sqrt((A + 1.0f / A) * (1.0f / S - 1.0f) + 2.0f);
        float beta = 2.0f * std::sqrt(A) * alpha;

        float b0 =    A * ((A + 1.0f) - (A - 1.0f) * cosw + beta);
        float b1 =  2.0f * A * ((A - 1.0f) - (A + 1.0f) * cosw);
        float b2 =    A * ((A + 1.0f) - (A - 1.0f) * cosw - beta);
        float a0 =        (A + 1.0f) + (A - 1.0f) * cosw + beta;
        float a1 =   -2.0f * ((A - 1.0f) + (A + 1.0f) * cosw);
        float a2 =        (A + 1.0f) + (A - 1.0f) * cosw - beta;

        return normalize(b0, b1, b2, a0, a1, a2);
    }

    static Coefficients designHighShelf(float sampleRate, float freqHz, float gainDb, float slope = 1.0f) {
        if (sampleRate <= 0.0f) {
            return Coefficients::identity();
        }

        float clampedFreq = std::clamp(freqHz, 0.0f, 0.5f * sampleRate);
        float w0 = 2.0f * pi * clampedFreq / sampleRate;
        float cosw = std::cos(w0);
        float sinw = std::sin(w0);

        float A = gainToA(gainDb);
        float S = std::max(slope, 1.0e-6f);
        float alpha = sinw / 2.0f * std::sqrt((A + 1.0f / A) * (1.0f / S - 1.0f) + 2.0f);
        float beta = 2.0f * std::sqrt(A) * alpha;

        float b0 =    A * ((A + 1.0f) + (A - 1.0f) * cosw + beta);
        float b1 = -2.0f * A * ((A - 1.0f) + (A + 1.0f) * cosw);
        float b2 =    A * ((A + 1.0f) + (A - 1.0f) * cosw - beta);
        float a0 =        (A + 1.0f) - (A - 1.0f) * cosw + beta;
        float a1 =    2.0f * ((A - 1.0f) - (A + 1.0f) * cosw);
        float a2 =        (A + 1.0f) - (A - 1.0f) * cosw - beta;

        return normalize(b0, b1, b2, a0, a1, a2);
    }

    static Coefficients designPeaking(float sampleRate, float freqHz, float q, float gainDb) {
        if (sampleRate <= 0.0f) {
            return Coefficients::identity();
        }

        float clampedFreq = std::clamp(freqHz, 0.0f, 0.5f * sampleRate);
        float w0 = 2.0f * pi * clampedFreq / sampleRate;
        float cosw = std::cos(w0);
        float sinw = std::sin(w0);

        float A = gainToA(gainDb);
        float Q = std::max(q, 1.0e-6f);
        float alpha = sinw / (2.0f * Q);

        float b0 = 1.0f + alpha * A;
        float b1 = -2.0f * cosw;
        float b2 = 1.0f - alpha * A;
        float a0 = 1.0f + alpha / A;
        float a1 = -2.0f * cosw;
        float a2 = 1.0f - alpha / A;

        return normalize(b0, b1, b2, a0, a1, a2);
    }

    static float dbToLinear(float db) {
        return std::pow(10.0f, db / 20.0f);
    }

private:
    static float gainToA(float gainDb) {
        return std::pow(10.0f, gainDb / 40.0f);
    }

    static Coefficients normalize(float b0, float b1, float b2, float a0, float a1, float a2) {
        if (!std::isfinite(a0) || std::fabs(a0) < 1.0e-12f) {
            return Coefficients::identity();
        }

        float invA0 = 1.0f / a0;
        return {b0 * invA0, b1 * invA0, b2 * invA0, a1 * invA0, a2 * invA0};
    }

    float sampleRate_ = 48000.0f;
    Coefficients coeffs_ = Coefficients::identity();
    float z1_ = 0.0f;
    float z2_ = 0.0f;
    float y1_ = 0.0f;
    float y2_ = 0.0f;
};

