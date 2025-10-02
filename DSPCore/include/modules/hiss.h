#pragma once

#include <cmath>
#include <cstdint>
#include <random>
#include <vector>

class Hiss {
public:
    Hiss();

    void prepare(float sampleRate, int maxChannels);
    void reset();

    void setLevelDbFS(float levelDb);
    void setSeed(uint64_t seed);

    void process(float* interleaved, int frames, int channels);

private:
    struct ChannelState {
        float prevWhite = 0.0f;
    };

    float levelDb_ = -120.0f;
    float levelLinear_ = 0.0f;

    float tiltAmount_ = 0.35f;
    float tiltNorm_ = 1.0f;

    std::mt19937_64 rng_;
    std::normal_distribution<float> normal_{0.0f, 1.0f};

    std::vector<ChannelState> channels_;

    void updateTiltNormalization();
};

inline Hiss::Hiss() {
    updateTiltNormalization();
    std::random_device rd;
    uint64_t seed = (static_cast<uint64_t>(rd()) << 32) ^ static_cast<uint64_t>(rd());
    setSeed(seed);
    setLevelDbFS(levelDb_);
}

inline void Hiss::updateTiltNormalization() {
    float t = tiltAmount_;
    tiltNorm_ = 1.0f / std::sqrt(std::max(1.0f + 2.0f * t + 2.0f * t * t, 1e-6f));
}

inline void Hiss::prepare(float sampleRate, int maxChannels) {
    (void)sampleRate;
    channels_.assign(std::max(maxChannels, 1), ChannelState{});
    reset();
}

inline void Hiss::reset() {
    for (auto& ch : channels_) {
        ch.prevWhite = 0.0f;
    }
}

inline void Hiss::setLevelDbFS(float levelDb) {
    levelDb_ = levelDb;
    if (levelDb <= -200.0f) {
        levelLinear_ = 0.0f;
    } else {
        levelLinear_ = std::pow(10.0f, levelDb * 0.05f);
    }
}

inline void Hiss::setSeed(uint64_t seed) {
    rng_.seed(seed);
}

inline void Hiss::process(float* interleaved, int frames, int channels) {
    if (!interleaved || frames <= 0 || channels <= 0) {
        return;
    }

    if ((int)channels_.size() < channels) {
        channels_.resize(channels);
    }

    const float level = levelLinear_;
    if (level <= 0.0f) {
        return;
    }

    for (int frame = 0; frame < frames; ++frame) {
        for (int ch = 0; ch < channels; ++ch) {
            auto& state = channels_[ch];
            float white = normal_(rng_);
            float colored = ((1.0f + tiltAmount_) * white - tiltAmount_ * state.prevWhite) * tiltNorm_;
            state.prevWhite = white;

            int idx = frame * channels + ch;
            interleaved[idx] += colored * level;
        }
    }
}

