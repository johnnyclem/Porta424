#pragma once

#include <cmath>

/**
 * Simple stereo crosstalk model.
 *
 * The implementation exposes a single parameter, ``crosstalkDb``, that is
 * expressed as an attenuation in decibels for the amount of signal that
 * bleeds from the opposite channel.  A value of ``-60`` therefore means that
 * one channel will receive the other with an attenuation of sixty decibels.
 */
class Crosstalk {
public:
    void prepare(float /*sampleRate*/, int /*maxBlockSize*/) {}

    void setAmountDb(float db)
    {
        crosstalkDb = db;
        crosstalkGain = std::pow(10.0f, crosstalkDb / 20.0f);
    }

    /**
     * Applies the crosstalk bleed to a stereo buffer.
     *
     * ``left`` and ``right`` must point to buffers with at least ``numSamples``
     * elements.  The method is intentionally in-place to avoid extra
     * allocations while still keeping the behaviour deterministic.
     */
    void process(float* left, float* right, int numSamples) const
    {
        if (left == nullptr || right == nullptr || numSamples <= 0)
            return;

        const float bleed = crosstalkGain;
        for (int i = 0; i < numSamples; ++i) {
            const float l = left[i];
            const float r = right[i];
            left[i] = l + r * bleed;
            right[i] = r + l * bleed;
        }
    }

    float getAmountDb() const { return crosstalkDb; }

private:
    float crosstalkDb { -120.0f };
    float crosstalkGain { 0.0f };
};
