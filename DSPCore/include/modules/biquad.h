#pragma once

#include <cmath>

struct Biquad {
    float b0{1.0f};
    float b1{0.0f};
    float b2{0.0f};
    float a1{0.0f};
    float a2{0.0f};
    float z1{0.0f};
    float z2{0.0f};

    void reset() {
        z1 = 0.0f;
        z2 = 0.0f;
    }

    float process(float input) {
        float output = b0 * input + z1;
        z1 = b1 * input - a1 * output + z2;
        z2 = b2 * input - a2 * output;
        return output;
    }

    static float dbToLinear(float db) {
        return std::pow(10.0f, db / 20.0f);
    }

    void setLowShelf(float sampleRate, float frequency, float gainDb, float q = 0.7071f) {
        const float A = dbToLinear(gainDb);
        const float w0 = 2.0f * static_cast<float>(M_PI) * frequency / sampleRate;
        const float alpha = std::sin(w0) / (2.0f * q);
        const float cosw0 = std::cos(w0);
        const float beta = 2.0f * std::sqrt(A) * alpha;

        float b0Num =    A * ((A + 1.0f) - (A - 1.0f) * cosw0 + beta);
        float b1Num =  2.0f * A * ((A - 1.0f) - (A + 1.0f) * cosw0);
        float b2Num =    A * ((A + 1.0f) - (A - 1.0f) * cosw0 - beta);
        float a0Den =        (A + 1.0f) + (A - 1.0f) * cosw0 + beta;
        float a1Den =   -2.0f * ((A - 1.0f) + (A + 1.0f) * cosw0);
        float a2Den =        (A + 1.0f) + (A - 1.0f) * cosw0 - beta;

        normalize(b0Num, b1Num, b2Num, a0Den, a1Den, a2Den);
    }

    void setHighShelf(float sampleRate, float frequency, float gainDb, float q = 0.7071f) {
        const float A = dbToLinear(gainDb);
        const float w0 = 2.0f * static_cast<float>(M_PI) * frequency / sampleRate;
        const float alpha = std::sin(w0) / (2.0f * q);
        const float cosw0 = std::cos(w0);
        const float beta = 2.0f * std::sqrt(A) * alpha;

        float b0Num =    A * ((A + 1.0f) + (A - 1.0f) * cosw0 + beta);
        float b1Num = -2.0f * A * ((A - 1.0f) + (A + 1.0f) * cosw0);
        float b2Num =    A * ((A + 1.0f) + (A - 1.0f) * cosw0 - beta);
        float a0Den =        (A + 1.0f) - (A - 1.0f) * cosw0 + beta;
        float a1Den =    2.0f * ((A - 1.0f) - (A + 1.0f) * cosw0);
        float a2Den =        (A + 1.0f) - (A - 1.0f) * cosw0 - beta;

        normalize(b0Num, b1Num, b2Num, a0Den, a1Den, a2Den);
    }

    void setPeaking(float sampleRate, float frequency, float gainDb, float q) {
        const float A = dbToLinear(gainDb);
        const float w0 = 2.0f * static_cast<float>(M_PI) * frequency / sampleRate;
        const float alpha = std::sin(w0) / (2.0f * q);
        const float cosw0 = std::cos(w0);

        float b0Num = 1.0f + alpha * A;
        float b1Num = -2.0f * cosw0;
        float b2Num = 1.0f - alpha * A;
        float a0Den = 1.0f + alpha / A;
        float a1Den = -2.0f * cosw0;
        float a2Den = 1.0f - alpha / A;

        normalize(b0Num, b1Num, b2Num, a0Den, a1Den, a2Den);
    }

    void setLowpass(float sampleRate, float cutoff, float q = 0.7071f) {
        const float w0 = 2.0f * static_cast<float>(M_PI) * cutoff / sampleRate;
        const float alpha = std::sin(w0) / (2.0f * q);
        const float cosw0 = std::cos(w0);

        float b0Num = (1.0f - cosw0) * 0.5f;
        float b1Num = 1.0f - cosw0;
        float b2Num = (1.0f - cosw0) * 0.5f;
        float a0Den = 1.0f + alpha;
        float a1Den = -2.0f * cosw0;
        float a2Den = 1.0f - alpha;

        normalize(b0Num, b1Num, b2Num, a0Den, a1Den, a2Den);
    }

private:
    void normalize(float b0Num, float b1Num, float b2Num, float a0Den, float a1Den, float a2Den) {
        b0 = b0Num / a0Den;
        b1 = b1Num / a0Den;
        b2 = b2Num / a0Den;
        a1 = a1Den / a0Den;
        a2 = a2Den / a0Den;
    }
};

