#pragma once

#include <algorithm>
#include <cmath>

/**
 * Simple biquad (second-order IIR) filter implementation used by several tape
 * processing modules. The class exposes coefficient design helpers for the
 * small set of filters required by the project and keeps only the minimal
 * state (two delay elements) necessary for Direct Form I processing.
 */
class Biquad {
public:
    /** Reset the filter delay elements to zero. */
    void reset() {
        z1_ = 0.0f;
        z2_ = 0.0f;
    }

    /**
     * Process a single sample using the current coefficients.
     * The implementation is intentionally branch-free and fast, because these
     * filters run on every sample in tight inner loops.
     */
    float process(float input) {
        const float output = b0_ * input + z1_;
        z1_ = b1_ * input - a1_ * output + z2_;
        z2_ = b2_ * input - a2_ * output;
        return output;
    }

    /** Design and apply a low-shelf filter. */
    void setLowShelf(float sampleRate, float frequency, float gainDb, float q = 0.7071f) {
        computeShelf(sampleRate, frequency, gainDb, q, /*highShelf=*/false);
    }

    /** Design and apply a high-shelf filter. */
    void setHighShelf(float sampleRate, float frequency, float gainDb, float q = 0.7071f) {
        computeShelf(sampleRate, frequency, gainDb, q, /*highShelf=*/true);
    }

    /** Design and apply a peaking EQ filter. */
    void setPeaking(float sampleRate, float frequency, float gainDb, float q) {
        const float fs = std::max(sampleRate, 1.0f);
        const float A = dbToLinear(gainDb);
        const float w0 = 2.0f * static_cast<float>(M_PI) * clampFrequency(frequency, fs);
        const float alpha = std::sin(w0) / (2.0f * std::max(q, 1.0e-6f));
        const float cosw0 = std::cos(w0);

        const float b0Num = 1.0f + alpha * A;
        const float b1Num = -2.0f * cosw0;
        const float b2Num = 1.0f - alpha * A;
        const float a0Den = 1.0f + alpha / A;
        const float a1Den = -2.0f * cosw0;
        const float a2Den = 1.0f - alpha / A;

        normalize(b0Num, b1Num, b2Num, a0Den, a1Den, a2Den);
    }

    /** Design and apply a simple low-pass filter. */
    void setLowpass(float sampleRate, float cutoff, float q = 0.7071f) {
        const float fs = std::max(sampleRate, 1.0f);
        const float w0 = 2.0f * static_cast<float>(M_PI) * clampFrequency(cutoff, fs);
        const float alpha = std::sin(w0) / (2.0f * std::max(q, 1.0e-6f));
        const float cosw0 = std::cos(w0);

        const float b0Num = (1.0f - cosw0) * 0.5f;
        const float b1Num = 1.0f - cosw0;
        const float b2Num = (1.0f - cosw0) * 0.5f;
        const float a0Den = 1.0f + alpha;
        const float a1Den = -2.0f * cosw0;
        const float a2Den = 1.0f - alpha;

        normalize(b0Num, b1Num, b2Num, a0Den, a1Den, a2Den);
    }

private:
    // Filter coefficients.
    float b0_{1.0f};
    float b1_{0.0f};
    float b2_{0.0f};
    float a1_{0.0f};
    float a2_{0.0f};

    // Delay elements for the IIR state.
    float z1_{0.0f};
    float z2_{0.0f};

    static float dbToLinear(float db) { return std::pow(10.0f, db / 20.0f); }

    static float clampFrequency(float frequency, float sampleRate) {
        const float nyquist = 0.5f * sampleRate;
        return std::clamp(frequency, 0.0f, nyquist);
    }

    void computeShelf(float sampleRate, float frequency, float gainDb, float q, bool highShelf) {
        const float fs = std::max(sampleRate, 1.0f);
        const float A = dbToLinear(gainDb);
        const float w0 = 2.0f * static_cast<float>(M_PI) * clampFrequency(frequency, fs);
        const float alpha = std::sin(w0) / (2.0f * std::max(q, 1.0e-6f));
        const float cosw0 = std::cos(w0);
        const float beta = 2.0f * std::sqrt(A) * alpha;

        float b0Num = 0.0f;
        float b1Num = 0.0f;
        float b2Num = 0.0f;
        float a0Den = 1.0f;
        float a1Den = 0.0f;
        float a2Den = 0.0f;

        if (highShelf) {
            b0Num =    A * ((A + 1.0f) + (A - 1.0f) * cosw0 + beta);
            b1Num = -2.0f * A * ((A - 1.0f) + (A + 1.0f) * cosw0);
            b2Num =    A * ((A + 1.0f) + (A - 1.0f) * cosw0 - beta);
            a0Den =        (A + 1.0f) - (A - 1.0f) * cosw0 + beta;
            a1Den =    2.0f * ((A - 1.0f) - (A + 1.0f) * cosw0);
            a2Den =        (A + 1.0f) - (A - 1.0f) * cosw0 - beta;
        } else {
            b0Num =    A * ((A + 1.0f) - (A - 1.0f) * cosw0 + beta);
            b1Num =  2.0f * A * ((A - 1.0f) - (A + 1.0f) * cosw0);
            b2Num =    A * ((A + 1.0f) - (A - 1.0f) * cosw0 - beta);
            a0Den =        (A + 1.0f) + (A - 1.0f) * cosw0 + beta;
            a1Den =   -2.0f * ((A - 1.0f) + (A + 1.0f) * cosw0);
            a2Den =        (A + 1.0f) + (A - 1.0f) * cosw0 - beta;
        }

        normalize(b0Num, b1Num, b2Num, a0Den, a1Den, a2Den);
    }

    void normalize(float b0Num, float b1Num, float b2Num, float a0Den, float a1Den, float a2Den) {
        // Protect against degenerate filters by falling back to a passthrough.
        if (!std::isfinite(a0Den) || std::fabs(a0Den) < 1.0e-12f) {
            b0_ = 1.0f;
            b1_ = b2_ = a1_ = a2_ = 0.0f;
            reset();
            return;
        }

        const float invA0 = 1.0f / a0Den;
        b0_ = b0Num * invA0;
        b1_ = b1Num * invA0;
        b2_ = b2Num * invA0;
        a1_ = a1Den * invA0;
        a2_ = a2Den * invA0;
        reset();
    }
};

