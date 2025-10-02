#include "PortaDSPBridge.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <vector>

#include "../../../../DSPCore/dsp_context.h"
#include "../../../../DSPCore/include/modules/azimuth.h"
#include "../../../../DSPCore/include/modules/compander.h"
#include "../../../../DSPCore/include/modules/crosstalk.h"
#include "../../../../DSPCore/include/modules/dropouts.h"
#include "../../../../DSPCore/include/modules/head_bump.h"
#include "../../../../DSPCore/include/modules/hf_loss.h"
#include "../../../../DSPCore/include/modules/hiss.h"
#include "../../../../DSPCore/include/modules/wow_flutter.h"

namespace {

struct SaturationStage {
    void prepare(float /*sampleRate*/, int /*channels*/) {
        driveLinearState_ = 1.0f;
        trimState_ = 1.0f;
        targetDriveLinear_ = 1.0f;
        targetTrim_ = 1.0f;
        processedSamples_ = 0;
        blockSamples_ = 1;
        bypass_ = true;
    }

    void setDriveDb(float driveDb) {
        if (!std::isfinite(driveDb)) {
            driveDb = 0.0f;
        }
        const bool newBypass = std::fabs(driveDb) < 1.0e-3f;
        if (newBypass) {
            targetDriveLinear_ = 1.0f;
            targetTrim_ = 1.0f;
        } else {
            targetDriveLinear_ = std::max(dbToLinear(driveDb), 1.0e-6f);
            targetTrim_ = computeTrim(driveDb);
        }
        bypass_ = newBypass;
    }

    void startBlock(int frames) {
        blockSamples_ = std::max(frames, 1);
        processedSamples_ = 0;
        driveStep_ = (targetDriveLinear_ - driveLinearState_) / static_cast<float>(blockSamples_);
        trimStep_ = (targetTrim_ - trimState_) / static_cast<float>(blockSamples_);
    }

    float processSample(float input) {
        if (processedSamples_ < blockSamples_) {
            driveLinearState_ += driveStep_;
            trimState_ += trimStep_;
            ++processedSamples_;
        }
        if (bypass_) {
            return input;
        }
        const float driven = driveLinearState_ * input;
        const float shaped = std::tanh(driven);
        return shaped * trimState_;
    }

private:
    static float dbToLinear(float db) {
        return std::pow(10.0f, db / 20.0f);
    }

    static float computeTrim(float driveDb) {
        constexpr int kTableSize = 64;
        constexpr float kMinDb = -60.0f;
        constexpr float kMaxDb = 40.0f;
        constexpr float kStepDb = (kMaxDb - kMinDb) / (kTableSize - 1);

        static std::once_flag once;
        static float table[kTableSize];
        std::call_once(once, [] {
            for (int i = 0; i < kTableSize; ++i) {
                float db = kMinDb + kStepDb * static_cast<float>(i);
                const float linear = dbToLinear(db);
                // RMS of tanh() drive for a sine wave.
                constexpr int kSineSamples = 2048;
                double acc = 0.0;
                const double omega = 2.0 * std::acos(-1.0) / static_cast<double>(kSineSamples);
                for (int n = 0; n < kSineSamples; ++n) {
                    const double phase = omega * (n + 0.5);
                    const double x = std::sin(phase);
                    const double y = std::tanh(static_cast<double>(linear) * x);
                    acc += y * y;
                }
                const double rmsOut = std::sqrt(acc / static_cast<double>(kSineSamples));
                constexpr double rmsIn = 0.7071067811865476; // RMS of a full-scale sine wave
                table[i] = rmsOut > 1e-12 ? static_cast<float>(rmsIn / rmsOut) : 1.0f;
            }
        });

        if (driveDb <= kMinDb) {
            return table[0];
        }
        if (driveDb >= kMaxDb) {
            return table[kTableSize - 1];
        }

        const float position = (driveDb - kMinDb) / kStepDb;
        const int index = static_cast<int>(std::floor(position));
        const float frac = position - static_cast<float>(index);
        const float a = table[index];
        const float b = table[index + 1];
        return a + (b - a) * frac;
    }

    float driveLinearState_ = 1.0f;
    float trimState_ = 1.0f;
    float targetDriveLinear_ = 1.0f;
    float targetTrim_ = 1.0f;
    float driveStep_ = 0.0f;
    float trimStep_ = 0.0f;
    int blockSamples_ = 1;
    int processedSamples_ = 0;
    bool bypass_ = true;
};

struct PortaStubContext {
    double sampleRate = 48000.0;
    int maxBlock = 512;
    int maxTracks = 2;

    std::atomic<porta_params_t> params;
    porta_params_t currentParams{};

    DSPContext dsp;
    std::vector<WowFlutter> wowFlutter;
    HeadBump headBump;
    SaturationStage saturation;
    HFLoss hfLoss;
    Hiss hiss;
    Azimuth azimuth;
    Crosstalk crosstalk;

    std::vector<float> channelScratch;
    std::vector<float> tempLeft;
    std::vector<float> tempRight;
    std::vector<float> rmsAcc;
    std::vector<int> rmsCount;

    int currentChannels = 0;
};

porta_params_t makeDefaultParams() {
    porta_params_t p{};
    p.wowDepth = 0.0006f;
    p.flutterDepth = 0.0003f;
    p.headBumpGainDb = 2.0f;
    p.headBumpFreqHz = 80.0f;
    p.satDriveDb = -6.0f;
    p.hissLevelDbFS = -60.0f;
    p.lpfCutoffHz = 12000.0f;
    p.azimuthJitterMs = 0.2f;
    p.crosstalkDb = -60.0f;
    p.dropoutRatePerMin = 0.2f;
    p.nrTrack4Bypass = 0;
    return p;
}

void updateModuleParameters(PortaStubContext& ctx, const porta_params_t& p) {
    ctx.headBump.setParams(p.headBumpFreqHz, p.headBumpGainDb);
    ctx.saturation.setDriveDb(p.satDriveDb);
    float cutoffHz = p.lpfCutoffHz;
    if (!std::isfinite(cutoffHz) || cutoffHz <= 0.0f) {
        cutoffHz = static_cast<float>(ctx.sampleRate) * 0.45f;
    }
    ctx.hfLoss.setCutoff(cutoffHz);
    ctx.hiss.setLevelDbFS(p.hissLevelDbFS);
    ctx.crosstalk.setAmountDb(p.crosstalkDb);

    float jitterDepthSamples = 0.0f;
    if (std::isfinite(p.azimuthJitterMs) && p.azimuthJitterMs > 0.0f) {
        jitterDepthSamples = static_cast<float>(ctx.sampleRate) * (p.azimuthJitterMs * 0.001f);
    }
    ctx.azimuth.setBaseOffsetSamples(0.0f);
    ctx.azimuth.setJitterDepthSamples(jitterDepthSamples);
    ctx.azimuth.setJitterRateHz(0.5f);

    for (auto& wf : ctx.wowFlutter) {
        wf.setWowDepth(p.wowDepth);
        wf.setFlutterDepth(p.flutterDepth);
    }
}

void ensureChannelCapacity(PortaStubContext& ctx, int channels, int frames) {
    if (ctx.currentChannels == channels) {
        return;
    }
    ctx.currentChannels = channels;

    ctx.headBump.prepare(static_cast<float>(ctx.sampleRate), channels);
    ctx.saturation.prepare(static_cast<float>(ctx.sampleRate), channels);
    ctx.hfLoss.prepare(static_cast<float>(ctx.sampleRate), channels);
    ctx.hiss.prepare(static_cast<float>(ctx.sampleRate), channels);
    ctx.wowFlutter.resize(static_cast<size_t>(channels));
    for (auto& wf : ctx.wowFlutter) {
        wf.prepare(static_cast<float>(ctx.sampleRate), ctx.maxBlock);
    }
    ctx.channelScratch.resize(static_cast<size_t>(channels) * static_cast<size_t>(frames));
    ctx.rmsAcc.assign(static_cast<size_t>(channels), 0.0f);
    ctx.rmsCount.assign(static_cast<size_t>(channels), 0);
}

void ensureFrameCapacity(PortaStubContext& ctx, int frames, int channels) {
    if (ctx.channelScratch.size() < static_cast<size_t>(frames) * static_cast<size_t>(channels)) {
        ctx.channelScratch.resize(static_cast<size_t>(frames) * static_cast<size_t>(channels));
    }
    if (ctx.tempLeft.size() < static_cast<size_t>(frames)) {
        ctx.tempLeft.resize(static_cast<size_t>(frames));
    }
    if (ctx.tempRight.size() < static_cast<size_t>(frames)) {
        ctx.tempRight.resize(static_cast<size_t>(frames));
    }
}

} // namespace

extern "C" {

porta_dsp_handle porta_create(double sampleRate, int maxBlock, int tracks) {
    auto* ctx = new PortaStubContext();
    ctx->sampleRate = sampleRate > 1.0 ? sampleRate : 1.0;
    ctx->maxBlock = std::max(maxBlock, 1);
    ctx->maxTracks = std::max(tracks, 1);

    porta_params_t defaults = makeDefaultParams();
    ctx->params.store(defaults, std::memory_order_relaxed);
    ctx->currentParams = defaults;

    ctx->dsp.prepare(ctx->sampleRate, ctx->maxTracks);
    ctx->headBump.prepare(static_cast<float>(ctx->sampleRate), ctx->maxTracks);
    ctx->saturation.prepare(static_cast<float>(ctx->sampleRate), ctx->maxTracks);
    ctx->hfLoss.prepare(static_cast<float>(ctx->sampleRate), ctx->maxTracks);
    ctx->hiss.prepare(static_cast<float>(ctx->sampleRate), ctx->maxTracks);
    ctx->azimuth.prepare(static_cast<float>(ctx->sampleRate), ctx->maxBlock);
    ctx->crosstalk.prepare(static_cast<float>(ctx->sampleRate), ctx->maxBlock);

    ctx->wowFlutter.resize(static_cast<size_t>(ctx->maxTracks));
    for (auto& wf : ctx->wowFlutter) {
        wf.prepare(static_cast<float>(ctx->sampleRate), ctx->maxBlock);
    }

    ctx->currentChannels = ctx->maxTracks;
    ctx->channelScratch.resize(static_cast<size_t>(ctx->maxTracks) * static_cast<size_t>(ctx->maxBlock));
    ctx->tempLeft.resize(static_cast<size_t>(ctx->maxBlock));
    ctx->tempRight.resize(static_cast<size_t>(ctx->maxBlock));
    ctx->rmsAcc.assign(static_cast<size_t>(ctx->maxTracks), 0.0f);
    ctx->rmsCount.assign(static_cast<size_t>(ctx->maxTracks), 0);

    updateModuleParameters(*ctx, defaults);
    return reinterpret_cast<porta_dsp_handle>(ctx);
}

void porta_destroy(porta_dsp_handle h) {
    auto* ctx = reinterpret_cast<PortaStubContext*>(h);
    delete ctx;
}

void porta_update_params(porta_dsp_handle h, const porta_params_t* p) {
    if (!h || !p) {
        return;
    }
    auto* ctx = reinterpret_cast<PortaStubContext*>(h);
    ctx->params.store(*p, std::memory_order_release);
}

void porta_process_interleaved(porta_dsp_handle h, float* interleaved, int frames, int channels) {
    auto* ctx = reinterpret_cast<PortaStubContext*>(h);
    if (!ctx || !interleaved || frames <= 0 || channels <= 0) {
        return;
    }

    ensureChannelCapacity(*ctx, channels, frames);
    ensureFrameCapacity(*ctx, frames, channels);

    porta_params_t params = ctx->params.load(std::memory_order_acquire);
    updateModuleParameters(*ctx, params);
    ctx->currentParams = params;

    DSPContext::Parameters dspParams;
    dspParams.dropoutRatePerMin = params.dropoutRatePerMin;
    dspParams.nrTrack4Bypass = params.nrTrack4Bypass != 0;
    ctx->dsp.process(interleaved, frames, channels, dspParams);

    if (!ctx->wowFlutter.empty()) {
        for (int c = 0; c < channels; ++c) {
            float* scratch = ctx->channelScratch.data() + static_cast<size_t>(c) * static_cast<size_t>(frames);
            for (int i = 0; i < frames; ++i) {
                scratch[i] = interleaved[i * channels + c];
            }
            ctx->wowFlutter[static_cast<size_t>(c)].process(scratch, static_cast<std::size_t>(frames));
            for (int i = 0; i < frames; ++i) {
                interleaved[i * channels + c] = scratch[i];
            }
        }
    }

    for (int frame = 0; frame < frames; ++frame) {
        for (int c = 0; c < channels; ++c) {
            const int idx = frame * channels + c;
            interleaved[idx] = ctx->headBump.processSample(interleaved[idx], c);
        }
    }

    ctx->saturation.startBlock(frames);
    for (int frame = 0; frame < frames; ++frame) {
        for (int c = 0; c < channels; ++c) {
            const int idx = frame * channels + c;
            interleaved[idx] = ctx->saturation.processSample(interleaved[idx]);
        }
    }

    ctx->hfLoss.process(interleaved, frames, channels);
    ctx->hiss.process(interleaved, frames, channels);

    if (channels >= 2) {
        for (int i = 0; i < frames; ++i) {
            ctx->tempLeft[static_cast<size_t>(i)] = interleaved[i * channels + 0];
            ctx->tempRight[static_cast<size_t>(i)] = interleaved[i * channels + 1];
        }
        ctx->crosstalk.process(ctx->tempLeft.data(), ctx->tempRight.data(), frames);
        ctx->azimuth.process(ctx->tempLeft.data(), ctx->tempRight.data(), frames);
        for (int i = 0; i < frames; ++i) {
            interleaved[i * channels + 0] = ctx->tempLeft[static_cast<size_t>(i)];
            interleaved[i * channels + 1] = ctx->tempRight[static_cast<size_t>(i)];
        }
    }

    if (ctx->rmsAcc.size() < static_cast<size_t>(channels)) {
        ctx->rmsAcc.resize(static_cast<size_t>(channels), 0.0f);
        ctx->rmsCount.resize(static_cast<size_t>(channels), 0);
    }

    for (int frame = 0; frame < frames; ++frame) {
        for (int c = 0; c < channels; ++c) {
            const int idx = frame * channels + c;
            const float sample = interleaved[idx];
            ctx->rmsAcc[static_cast<size_t>(c)] += sample * sample;
            ctx->rmsCount[static_cast<size_t>(c)] += 1;
        }
    }
}

int porta_get_meters_dbfs(porta_dsp_handle h, float* outDbfs, int maxChannels) {
    auto* ctx = reinterpret_cast<PortaStubContext*>(h);
    if (!ctx || !outDbfs || maxChannels <= 0) {
        return 0;
    }

    const int available = std::min<int>(maxChannels, static_cast<int>(ctx->rmsAcc.size()));
    for (int i = 0; i < available; ++i) {
        float rms = 0.0f;
        if (ctx->rmsCount[static_cast<size_t>(i)] > 0) {
            rms = std::sqrt(ctx->rmsAcc[static_cast<size_t>(i)] /
                            static_cast<float>(ctx->rmsCount[static_cast<size_t>(i)]));
        }
        ctx->rmsAcc[static_cast<size_t>(i)] = 0.0f;
        ctx->rmsCount[static_cast<size_t>(i)] = 0;
        outDbfs[i] = rms > 1.0e-9f ? 20.0f * std::log10(rms) : -120.0f;
    }
    return available;
}

float porta_test_saturation(float sample, float driveDb) {
    SaturationStage stage;
    stage.prepare(48000.0f, 1);
    stage.setDriveDb(driveDb);
    stage.startBlock(1);
    return stage.processSample(sample);
}

void porta_test_head_bump(const float* input, float* output, int frames, float sampleRate, float gainDb, float freqHz) {
    if (!input || !output || frames <= 0) {
        return;
    }
    HeadBump headBump;
    headBump.prepare(sampleRate, 1);
    headBump.setParams(freqHz, gainDb);
    for (int i = 0; i < frames; ++i) {
        output[i] = headBump.processSample(input[i], 0);
    }
}

void porta_test_wow_flutter(const float* input, float* output, int frames, float sampleRate, float wowDepth, float flutterDepth,
                             float wowRate, float flutterRate) {
    if (!input || !output || frames <= 0) {
        return;
    }
    WowFlutter wf;
    wf.prepare(sampleRate, frames);
    wf.setWowDepth(wowDepth);
    wf.setFlutterDepth(flutterDepth);
    wf.setWowRate(wowRate);
    wf.setFlutterRate(flutterRate);
    for (int i = 0; i < frames; ++i) {
        output[i] = wf.processSample(input[i]);
    }
}

void porta_test_apply_dropouts(float* interleaved, int frames, int channels, float sampleRate, float dropoutRatePerMin,
                               int dropoutLengthSamples, uint32_t seed) {
    if (!interleaved || frames <= 0 || channels <= 0 || dropoutLengthSamples <= 0) {
        return;
    }

    Dropouts dropouts;
    dropouts.prepare(sampleRate, channels);
    dropouts.setRate(dropoutRatePerMin);
    dropouts.setSeed(seed);
    dropouts.setHoldRangeSamplesForTesting(dropoutLengthSamples, dropoutLengthSamples);
    dropouts.process(interleaved, frames, channels);
}

} // extern "C"
