#pragma once

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <random>
#include <vector>

class WowFlutter {
public:
    WowFlutter() = default;

    void prepare(float sampleRate, int /*maxBlockSize*/) {
        mSampleRate = std::max(sampleRate, 1.0f);

        const float wowMaxSeconds = 0.01f;
        const float flutterMaxSeconds = 0.0025f;
        const float bufferMargin = 0.005f;

        mWowDepthMaxSamples = mSampleRate * wowMaxSeconds;
        mFlutterDepthMaxSamples = mSampleRate * flutterMaxSeconds;

        const auto maxDelaySeconds = wowMaxSeconds + flutterMaxSeconds + bufferMargin;
        const std::size_t minBuffer = 4u;
        mDelayBufferLength = std::max<std::size_t>(static_cast<std::size_t>(mSampleRate * maxDelaySeconds), minBuffer);
        mDelayBuffer.assign(mDelayBufferLength, 0.0f);
        mWriteIndex = 0;
        randomizePhase();

        mPhaseDriftInterval = std::max(1, static_cast<int>(mSampleRate * 0.5f));
        mPhaseDriftCounter = mPhaseDriftInterval;
        mCurrentModulation = 0.0f;
    }

    void reset() {
        std::fill(mDelayBuffer.begin(), mDelayBuffer.end(), 0.0f);
        mWriteIndex = 0;
        randomizePhase();
        mPhaseDriftCounter = mPhaseDriftInterval;
        mCurrentModulation = 0.0f;
    }

    void setWowDepth(float depth) { mWowDepth = std::clamp(depth, 0.0f, 1.0f); }
    void setFlutterDepth(float depth) { mFlutterDepth = std::clamp(depth, 0.0f, 1.0f); }
    void setWowRate(float hz) { mWowRate = std::max(hz, 0.0f); }
    void setFlutterRate(float hz) { mFlutterRate = std::max(hz, 0.0f); }

    float processSample(float input) {
        if (mDelayBuffer.empty()) {
            return input;
        }

        updatePhaseDrift();
        advancePhases();

        const float wow = std::sin(mWowPhase) * (mWowDepth * mWowDepthMaxSamples);
        const float flutter = std::sin(mFlutterPhase) * (mFlutterDepth * mFlutterDepthMaxSamples);
        float modulationSamples = wow + flutter;

        const float baseDelay = static_cast<float>(mDelayBufferLength - 2);
        float readDelay = std::clamp(baseDelay + modulationSamples, 1.0f, static_cast<float>(mDelayBufferLength - 2));
        mCurrentModulation = modulationSamples / mSampleRate;

        mDelayBuffer[mWriteIndex] = input;

        float readIndex = static_cast<float>(mWriteIndex) - readDelay;
        while (readIndex < 0.0f) {
            readIndex += static_cast<float>(mDelayBufferLength);
        }

        const std::size_t index0 = static_cast<std::size_t>(readIndex);
        const std::size_t index1 = (index0 + 1) % mDelayBufferLength;
        const float frac = readIndex - static_cast<float>(index0);

        const float y0 = mDelayBuffer[index0];
        const float y1 = mDelayBuffer[index1];
        const float output = y0 + (y1 - y0) * frac;

        mWriteIndex = (mWriteIndex + 1) % mDelayBufferLength;

        return output;
    }

    void process(float* samples, std::size_t count) {
        if (!samples) {
            return;
        }
        for (std::size_t i = 0; i < count; ++i) {
            samples[i] = processSample(samples[i]);
        }
    }

    float getCurrentModulation() const { return mCurrentModulation; }

    void randomizePhase() {
        std::uniform_real_distribution<float> dist(0.0f, twoPi());
        mWowPhase = dist(mRng);
        mFlutterPhase = dist(mRng);
    }

private:
    static constexpr float twoPi() { return 6.283185307179586476925286766559f; }

    void advancePhases() {
        const float wowInc = twoPi() * mWowRate / mSampleRate;
        const float flutterInc = twoPi() * mFlutterRate / mSampleRate;

        mWowPhase = wrapPhase(mWowPhase + wowInc + mWowDriftOffset);
        mFlutterPhase = wrapPhase(mFlutterPhase + flutterInc);
    }

    void updatePhaseDrift() {
        if (--mPhaseDriftCounter <= 0) {
            std::uniform_real_distribution<float> dist(-1.0f, 1.0f);
            const float driftAmount = 0.002f;
            mWowDriftOffset = dist(mRng) * driftAmount;
            mPhaseDriftCounter = mPhaseDriftInterval;
        }
    }

    static float wrapPhase(float phase) {
        const float twoPiValue = twoPi();
        if (phase >= twoPiValue) {
            phase -= twoPiValue;
        } else if (phase < 0.0f) {
            phase += twoPiValue;
        }
        return phase;
    }

    float mSampleRate = 44100.0f;
    float mWowDepth = 0.5f;
    float mFlutterDepth = 0.25f;
    float mWowRate = 0.4f;
    float mFlutterRate = 5.0f;

    float mWowPhase = 0.0f;
    float mFlutterPhase = 0.0f;
    float mWowDepthMaxSamples = 0.0f;
    float mFlutterDepthMaxSamples = 0.0f;
    float mWowDriftOffset = 0.0f;

    std::vector<float> mDelayBuffer;
    std::size_t mDelayBufferLength = 0;
    std::size_t mWriteIndex = 0;

    int mPhaseDriftInterval = 44100;
    int mPhaseDriftCounter = 44100;

    float mCurrentModulation = 0.0f;

    std::mt19937 mRng{std::random_device{}()};
};
