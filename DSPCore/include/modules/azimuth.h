#pragma once

#include <algorithm>
#include <cmath>
#include <vector>

class Azimuth {
public:
    void prepare(float newSampleRate, int maxBlockSize)
    {
        sampleRate = newSampleRate;
        reservedBlockSize = maxBlockSize;
        updateBuffers();
        updateLfoIncrement();
    }

    void setBaseOffsetSamples(float samples)
    {
        baseOffsetSamples = std::max(0.0f, samples);
        updateBuffers();
    }

    void setJitterDepthSamples(float samples)
    {
        jitterDepthSamples = std::max(0.0f, samples);
        updateBuffers();
    }

    void setJitterRateHz(float hz)
    {
        jitterRateHz = std::max(0.0f, hz);
        updateLfoIncrement();
    }

    void process(float* left, float* right, int numSamples)
    {
        if (left == nullptr || right == nullptr || numSamples <= 0)
            return;

        if (delayBufferSize == 0)
            return;

        for (int i = 0; i < numSamples; ++i) {
            const float lfo = std::sin(lfoPhase);
            lfoPhase += lfoPhaseIncrement;
            if (lfoPhase > twoPi)
                lfoPhase -= twoPi;

            const float offsetLeft = baseOffsetSamples + jitterDepthSamples * lfo;
            const float offsetRight = baseOffsetSamples - jitterDepthSamples * lfo;

            const float outLeft = readInterpolated(0, offsetLeft);
            const float outRight = readInterpolated(1, offsetRight);

            writeSample(0, left[i]);
            writeSample(1, right[i]);

            left[i] = outLeft;
            right[i] = outRight;

            advanceWriteIndex();
        }
    }

private:
    void updateBuffers()
    {
        const int delay = static_cast<int>(std::ceil(baseOffsetSamples + jitterDepthSamples)) + 4;
        const int newSize = std::max(reservedBlockSize + delay, delay);
        if (newSize == delayBufferSize && delayBufferSize != 0)
            return;

        delayBufferSize = newSize;
        for (auto& buffer : delayBuffers)
            buffer.assign(delayBufferSize, 0.0f);
        writeIndex = 0;
    }

    void updateLfoIncrement()
    {
        if (sampleRate <= 0.0f) {
            lfoPhaseIncrement = 0.0f;
            return;
        }

        lfoPhaseIncrement = twoPi * jitterRateHz / sampleRate;
    }

    float readInterpolated(int channel, float delaySamples) const
    {
        if (delayBufferSize == 0)
            return 0.0f;

        const float maxDelay = static_cast<float>(delayBufferSize - 1);
        const float safeDelay = std::clamp(delaySamples, 0.0f, maxDelay);
        float readPos = static_cast<float>(writeIndex) - safeDelay;
        while (readPos < 0.0f)
            readPos += static_cast<float>(delayBufferSize);

        const int index0 = static_cast<int>(readPos) % delayBufferSize;
        const int index1 = (index0 + 1) % delayBufferSize;
        const float frac = readPos - static_cast<float>(static_cast<int>(readPos));

        const float y0 = delayBuffers[channel][index0];
        const float y1 = delayBuffers[channel][index1];
        return y0 + (y1 - y0) * frac;
    }

    void writeSample(int channel, float value)
    {
        delayBuffers[channel][writeIndex] = value;
    }

    void advanceWriteIndex()
    {
        if (delayBufferSize == 0)
            return;

        writeIndex = (writeIndex + 1) % delayBufferSize;
    }

    static constexpr float twoPi = 6.283185307179586476925286766559f;

    float sampleRate { 0.0f };
    int reservedBlockSize { 0 };

    float baseOffsetSamples { 0.0f };
    float jitterDepthSamples { 0.05f };
    float jitterRateHz { 0.3f };

    float lfoPhase { 0.0f };
    float lfoPhaseIncrement { 0.0f };

    int delayBufferSize { 0 };
    int writeIndex { 0 };
    std::vector<float> delayBuffers[2];
};
