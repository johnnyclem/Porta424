#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>

class Dropouts {
public:
    Dropouts() = default;

    void prepare(float sampleRate, int channels) {
        sampleRate_ = sampleRate > 1.0f ? sampleRate : 1.0f;
        channels_ = channels > 0 ? channels : 1;
        attackSamples_ = std::max(1, static_cast<int>(sampleRate_ * attackTimeSeconds_));
        releaseSamples_ = std::max(1, static_cast<int>(sampleRate_ * releaseTimeSeconds_));
        minHoldSamples_ = std::max(1, static_cast<int>(sampleRate_ * minHoldSeconds_));
        maxHoldSamples_ = std::max(minHoldSamples_, static_cast<int>(sampleRate_ * maxHoldSeconds_));
        reset();
    }

    void reset() {
        stage_ = Stage::Idle;
        stageSamplesRemaining_ = 0;
        holdSamplesRemaining_ = 0;
        envelope_ = 1.0f;
        dropoutsTriggered_ = 0;
    }

    void setRate(float ratePerMinute) {
        dropoutRatePerMinute_ = std::max(ratePerMinute, 0.0f);
    }

    void process(float* interleaved, int frames, int channels) {
        if (!interleaved || frames <= 0 || channels <= 0) {
            return;
        }

        if (channels != channels_) {
            channels_ = channels;
        }

        const float probability = computeTriggerProbability();

        for (int i = 0; i < frames; ++i) {
            const float gain = advance(probability);
            for (int c = 0; c < channels_; ++c) {
                interleaved[i * channels + c] *= gain;
            }
        }
    }

    int dropoutCount() const { return dropoutsTriggered_; }

private:
    enum class Stage { Idle, Attack, Hold, Release };

    float advance(float triggerProbability) {
        switch (stage_) {
            case Stage::Idle:
                envelope_ = 1.0f;
                if (dropoutRatePerMinute_ > 0.0f && randomFloat() < triggerProbability) {
                    startEvent();
                }
                break;
            case Stage::Attack:
                if (stageSamplesRemaining_ > 0) {
                    envelope_ -= attackStep_;
                    --stageSamplesRemaining_;
                }
                if (stageSamplesRemaining_ <= 0) {
                    envelope_ = minGain_;
                    holdSamplesRemaining_ = randomHoldSamples();
                    stage_ = Stage::Hold;
                }
                break;
            case Stage::Hold:
                if (--holdSamplesRemaining_ <= 0) {
                    stage_ = Stage::Release;
                    stageSamplesRemaining_ = releaseSamples_;
                }
                envelope_ = minGain_;
                break;
            case Stage::Release:
                if (stageSamplesRemaining_ > 0) {
                    envelope_ += releaseStep_;
                    --stageSamplesRemaining_;
                }
                if (stageSamplesRemaining_ <= 0) {
                    envelope_ = 1.0f;
                    stage_ = Stage::Idle;
                } else {
                    envelope_ = std::min(envelope_, 1.0f);
                }
                break;
        }

        envelope_ = std::clamp(envelope_, minGain_, 1.0f);
        return envelope_;
    }

    void startEvent() {
        stage_ = Stage::Attack;
        stageSamplesRemaining_ = attackSamples_;
        attackStep_ = (attackSamples_ > 0) ? (1.0f - minGain_) / static_cast<float>(attackSamples_) : (1.0f - minGain_);
        releaseStep_ = (releaseSamples_ > 0) ? (1.0f - minGain_) / static_cast<float>(releaseSamples_) : (1.0f - minGain_);
        envelope_ = 1.0f;
        ++dropoutsTriggered_;
    }

    float computeTriggerProbability() const {
        if (dropoutRatePerMinute_ <= 0.0f || sampleRate_ <= 0.0f) {
            return 0.0f;
        }
        const float eventsPerSecond = dropoutRatePerMinute_ / 60.0f;
        return eventsPerSecond / sampleRate_;
    }

    int randomHoldSamples() {
        if (maxHoldSamples_ <= minHoldSamples_) {
            return minHoldSamples_;
        }
        const float r = randomFloat();
        const float span = static_cast<float>(maxHoldSamples_ - minHoldSamples_);
        return minHoldSamples_ + static_cast<int>(std::round(r * span));
    }

    float randomFloat() {
        rngState_ = rngState_ * 1664525u + 1013904223u;
        return static_cast<float>((rngState_ >> 1) & 0x7FFFFFFFu) / static_cast<float>(0x7FFFFFFF);
    }

    Stage stage_ = Stage::Idle;
    float sampleRate_ = 48000.0f;
    int channels_ = 1;
    int stageSamplesRemaining_ = 0;
    int holdSamplesRemaining_ = 0;
    int attackSamples_ = 1;
    int releaseSamples_ = 1;
    int minHoldSamples_ = 1;
    int maxHoldSamples_ = 1;
    float attackStep_ = 0.0f;
    float releaseStep_ = 0.0f;
    float envelope_ = 1.0f;
    float dropoutRatePerMinute_ = 0.0f;
    int dropoutsTriggered_ = 0;
    uint32_t rngState_ = 0x1234567u;

    static constexpr float minGain_ = 0.25f;
    static constexpr float attackTimeSeconds_ = 0.004f;   // ~4 ms
    static constexpr float releaseTimeSeconds_ = 0.010f;  // ~10 ms
    static constexpr float minHoldSeconds_ = 0.010f;      // 10 ms
    static constexpr float maxHoldSeconds_ = 0.030f;      // 30 ms
};

