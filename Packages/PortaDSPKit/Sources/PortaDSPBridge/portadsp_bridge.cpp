#include "PortaDSPBridge.h"
#include "dsp_context.h"
#include <algorithm>
#include <atomic>
#include <array>
#include <cmath>
#include <cstdio>
#include <cstring>
#include "../../../../DSPCore/include/modules/azimuth.h"
#include "../../../../DSPCore/include/modules/crosstalk.h"
#include "../../../../DSPCore/include/modules/head_bump.h"
#include "../../../../DSPCore/include/modules/hf_loss.h"
#include "../../../../DSPCore/include/modules/hiss.h"
#include "../../../../DSPCore/include/modules/wow_flutter.h"
#include <mutex>
#include <vector>

namespace {

constexpr float kMinDriveDb = -60.0f;
constexpr float kMaxDriveDb = 40.0f;
constexpr float kDriveStepDb = 1.0f;
constexpr int kTrimTableSize = static_cast<int>((kMaxDriveDb - kMinDriveDb) / kDriveStepDb) + 1;

float dbToLinear(float db) {
    return std::pow(10.0f, db / 20.0f);
}

float computeTrimForDriveLinear(float driveLinear) {
    if (!std::isfinite(driveLinear)) {
        return 1.0f;
    }
    if (driveLinear <= 0.0f) {
        return 1.0f;
    }

    constexpr int kSineSamples = 2048;
    const double omega = 2.0 * std::acos(-1.0) / static_cast<double>(kSineSamples);
    double acc = 0.0;
    for (int i = 0; i < kSineSamples; ++i) {
        double phase = omega * (i + 0.5);
        double x = std::sin(phase);
        double y = std::tanh(static_cast<double>(driveLinear) * x);
        acc += y * y;
    }
    double rmsOut = std::sqrt(acc / static_cast<double>(kSineSamples));
    constexpr double rmsIn = 0.7071067811865476; // RMS of a full-scale sine wave
    if (rmsOut < 1e-12) {
        return 1.0f;
    }
    return static_cast<float>(rmsIn / rmsOut);
}

float lookupTrim(float driveDb) {
    static std::once_flag onceFlag;
    static std::array<float, kTrimTableSize> trimTable{};
    std::call_once(onceFlag, [] {
        for (int i = 0; i < kTrimTableSize; ++i) {
            float db = kMinDriveDb + static_cast<float>(i) * kDriveStepDb;
            float linear = dbToLinear(db);
            trimTable[i] = computeTrimForDriveLinear(linear);
        }
    });

    if (driveDb <= kMinDriveDb) {
        return trimTable.front();
    }
    if (driveDb >= kMaxDriveDb) {
        return trimTable.back();
    }

    float position = (driveDb - kMinDriveDb) / kDriveStepDb;
    int index = static_cast<int>(std::floor(position));
    float frac = position - static_cast<float>(index);
    float a = trimTable[index];
    float b = trimTable[index + 1];
    return a + (b - a) * frac;
}

} // namespace

class SaturationStage {
public:
    void prepare(float /*sampleRate*/, int /*channels*/) {
        driveLinearState_ = 1.0f;
        trimState_ = 1.0f;
        targetDriveLinear_ = driveLinearState_;
        targetTrim_ = trimState_;
        blockSamples_ = 1;
        processedSamples_ = 0;
        bypass_ = true;
    }

    void setDriveDb(float driveDb) {
        if (!std::isfinite(driveDb)) {
            driveDb = 0.0f;
        }
        bool newBypass = std::fabs(driveDb) < 1.0e-3f;
        if (newBypass) {
            targetDriveLinear_ = 1.0f;
            targetTrim_ = 1.0f;
        } else {
            targetDriveLinear_ = std::max(dbToLinear(driveDb), 1.0e-6f);
            targetTrim_ = lookupTrim(driveDb);
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
        float shaped = std::tanh(driveLinearState_ * input);
        return shaped * trimState_;
    }

private:
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
    double fs = 48000.0;
    int maxBlock = 512;
    int tracks = 4;
    std::atomic<porta_params_t> params;
    porta_params_t currentParams{};
    HeadBump headBump;
    std::vector<WowFlutter> wowFlutter;
    HFLoss hfLoss;
    Hiss hiss;
    Azimuth azimuth;
    Crosstalk crosstalk;
    std::vector<float> rmsAcc;
    std::vector<int> rmsCount;
    DSPContext dsp;
    SaturationStage saturation;
    std::vector<float> channelScratch;
    std::vector<float> tempLeft;
    std::vector<float> tempRight;
    int currentChannels = 0;
};

porta_dsp_handle porta_create(double sampleRate, int maxBlock, int tracks) {
    auto* ctx = new PortaStubContext();
    ctx->fs = sampleRate;
    ctx->maxBlock = maxBlock;
    ctx->tracks = tracks;
    porta_params_t p{};
    ctx->params.store(p, std::memory_order_relaxed);
    ctx->dsp.prepare(sampleRate, tracks);
    ctx->currentParams = p;
    ctx->rmsAcc.assign(8, 0.0f);
    ctx->rmsCount.assign(8, 0);
    int channels = tracks > 0 ? tracks : 1;
    ctx->currentChannels = channels;
    ctx->headBump.prepare(static_cast<float>(ctx->fs), channels);
    ctx->headBump.setParams(p.headBumpFreqHz, p.headBumpGainDb);
    ctx->hfLoss.prepare(static_cast<float>(ctx->fs), channels);
    ctx->hiss.prepare(static_cast<float>(ctx->fs), channels);
    ctx->azimuth.prepare(static_cast<float>(ctx->fs), ctx->maxBlock);
    ctx->crosstalk.prepare(static_cast<float>(ctx->fs), ctx->maxBlock);
    ctx->wowFlutter.resize(static_cast<size_t>(channels));
    for (auto& wf : ctx->wowFlutter) {
        wf.prepare(static_cast<float>(ctx->fs), ctx->maxBlock);
        wf.setWowDepth(p.wowDepth);
        wf.setFlutterDepth(p.flutterDepth);
    }
    ctx->saturation.prepare(static_cast<float>(ctx->fs), channels);
    ctx->saturation.setDriveDb(p.satDriveDb);
    ctx->channelScratch.resize(static_cast<size_t>(channels) * static_cast<size_t>(ctx->maxBlock));
    ctx->tempLeft.resize(static_cast<size_t>(ctx->maxBlock));
    ctx->tempRight.resize(static_cast<size_t>(ctx->maxBlock));
    float initialCutoff = p.lpfCutoffHz;
    if (!std::isfinite(initialCutoff) || initialCutoff <= 0.0f) {
        initialCutoff = static_cast<float>(ctx->fs) * 0.45f;
    }
    ctx->hfLoss.setCutoff(initialCutoff);
    ctx->hiss.setLevelDbFS(p.hissLevelDbFS);
    ctx->crosstalk.setAmountDb(p.crosstalkDb);
    return (porta_dsp_handle)ctx;
}

void porta_destroy(porta_dsp_handle h) {
    auto* ctx = (PortaStubContext*)h;
    delete ctx;
}

void porta_update_params(porta_dsp_handle h, const porta_params_t* p) {
    auto* ctx = (PortaStubContext*)h;
    ctx->params.store(*p, std::memory_order_release);
}

void porta_process_interleaved(porta_dsp_handle h, float* inter, int frames, int ch) {
    auto* ctx = (PortaStubContext*)h;
    if (ctx == nullptr || inter == nullptr || frames <= 0 || ch <= 0) {
        return;
    }

    auto logStage = [](const char* stage, const char* suffix = "") {
        std::fprintf(stderr, "[PortaDSP] Stage: %s%s\n", stage, suffix);
    };

    // Load latest params and (re)configure modules if needed.
    porta_params_t p = ctx->params.load(std::memory_order_acquire);

    if (ctx->currentChannels != ch) {
        ctx->currentChannels = ch;
        ctx->headBump.prepare(static_cast<float>(ctx->fs), ch);
        ctx->hfLoss.prepare(static_cast<float>(ctx->fs), ch);
        ctx->hiss.prepare(static_cast<float>(ctx->fs), ch);
        ctx->saturation.prepare(static_cast<float>(ctx->fs), ch);
        ctx->dsp.prepare(ctx->fs, ch);
        ctx->wowFlutter.resize(static_cast<size_t>(ch));
        for (auto& wf : ctx->wowFlutter) {
            wf.prepare(static_cast<float>(ctx->fs), ctx->maxBlock);
        }
        ctx->channelScratch.resize(static_cast<size_t>(ch) * static_cast<size_t>(ctx->maxBlock));
    }

    if (ctx->tempLeft.size() < static_cast<size_t>(frames)) {
        ctx->tempLeft.resize(static_cast<size_t>(frames));
    }
    if (ctx->tempRight.size() < static_cast<size_t>(frames)) {
        ctx->tempRight.resize(static_cast<size_t>(frames));
    }
    if (ctx->channelScratch.size() < static_cast<size_t>(ch) * static_cast<size_t>(frames)) {
        ctx->channelScratch.resize(static_cast<size_t>(ch) * static_cast<size_t>(frames));
    }
    if (ctx->rmsAcc.size() < static_cast<size_t>(ch)) {
        ctx->rmsAcc.resize(static_cast<size_t>(ch), 0.0f);
        ctx->rmsCount.resize(static_cast<size_t>(ch), 0);
    }

    ctx->headBump.setParams(p.headBumpFreqHz, p.headBumpGainDb);
    ctx->saturation.setDriveDb(p.satDriveDb);
    float cutoffHz = p.lpfCutoffHz;
    if (!std::isfinite(cutoffHz) || cutoffHz <= 0.0f) {
        cutoffHz = static_cast<float>(ctx->fs) * 0.45f;
    }
    ctx->hfLoss.setCutoff(cutoffHz);
    ctx->hiss.setLevelDbFS(p.hissLevelDbFS);
    ctx->crosstalk.setAmountDb(p.crosstalkDb);

    float jitterDepthSamples = 0.0f;
    if (std::isfinite(p.azimuthJitterMs) && p.azimuthJitterMs > 0.0f) {
        jitterDepthSamples = static_cast<float>(ctx->fs) * (p.azimuthJitterMs * 0.001f);
    }
    ctx->azimuth.setBaseOffsetSamples(0.0f);
    ctx->azimuth.setJitterDepthSamples(jitterDepthSamples);
    ctx->azimuth.setJitterRateHz(0.5f);

    for (auto& wf : ctx->wowFlutter) {
        wf.setWowDepth(p.wowDepth);
        wf.setFlutterDepth(p.flutterDepth);
    }

    ctx->currentParams = p;

    DSPContext::Parameters dspParams;
    dspParams.dropoutRatePerMin = p.dropoutRatePerMin;
    dspParams.nrTrack4Bypass = p.nrTrack4Bypass != 0;

    logStage("dropouts/compander");
    ctx->dsp.process(inter, frames, ch, dspParams);

    logStage("wow_flutter");
    if (!ctx->wowFlutter.empty()) {
        size_t stride = static_cast<size_t>(frames);
        for (int c = 0; c < ch; ++c) {
            float* scratch = ctx->channelScratch.data() + static_cast<size_t>(c) * stride;
            for (int i = 0; i < frames; ++i) {
                scratch[i] = inter[i * ch + c];
            }
            ctx->wowFlutter[static_cast<size_t>(c)].process(scratch, stride);
            for (int i = 0; i < frames; ++i) {
                inter[i * ch + c] = scratch[i];
            }
        }
    }

    logStage("head_bump");
    for (int frame = 0; frame < frames; ++frame) {
        for (int c = 0; c < ch; ++c) {
            int idx = frame * ch + c;
            inter[idx] = ctx->headBump.processSample(inter[idx], c);
        }
    }

    logStage("saturation");
    ctx->saturation.startBlock(frames);
    for (int frame = 0; frame < frames; ++frame) {
        for (int c = 0; c < ch; ++c) {
            int idx = frame * ch + c;
            inter[idx] = ctx->saturation.processSample(inter[idx]);
        }
    }

    logStage("eq");
    ctx->hfLoss.process(inter, frames, ch);

    logStage("hiss");
    ctx->hiss.process(inter, frames, ch);

    bool hasStereo = ch >= 2;
    logStage("crosstalk", hasStereo ? "" : " (skipped)");
    if (hasStereo) {
        for (int i = 0; i < frames; ++i) {
            ctx->tempLeft[static_cast<size_t>(i)] = inter[i * ch + 0];
            ctx->tempRight[static_cast<size_t>(i)] = inter[i * ch + 1];
        }
        ctx->crosstalk.process(ctx->tempLeft.data(), ctx->tempRight.data(), frames);

        logStage("azimuth");
        ctx->azimuth.process(ctx->tempLeft.data(), ctx->tempRight.data(), frames);

        for (int i = 0; i < frames; ++i) {
            inter[i * ch + 0] = ctx->tempLeft[static_cast<size_t>(i)];
            inter[i * ch + 1] = ctx->tempRight[static_cast<size_t>(i)];
        }
    } else {
        logStage("azimuth", " (skipped)");
    }

    for (int frame = 0; frame < frames; ++frame) {
        for (int c = 0; c < ch; ++c) {
            int idx = frame * ch + c;
            float sample = inter[idx];
            ctx->rmsAcc[static_cast<size_t>(c)] += sample * sample;
            ctx->rmsCount[static_cast<size_t>(c)] += 1;
        }
    }
}

int porta_get_meters_dbfs(porta_dsp_handle h, float* outDbfs, int maxCh) {
    auto* ctx = (PortaStubContext*)h;
    int n = std::min(maxCh, (int)ctx->rmsAcc.size());
    for (int i = 0; i < n; i++) {
        float rms = 0.0f;
        if (ctx->rmsCount[i] > 0) {
            rms = std::sqrt(ctx->rmsAcc[i] / (float)ctx->rmsCount[i]);
        }
        // reset accumulators
        ctx->rmsAcc[i] = 0.0f;
        ctx->rmsCount[i] = 0;
        float db = (rms > 1e-9f) ? 20.0f * std::log10(rms) : -120.0f;
        outDbfs[i] = db;
    }
    return n;
}
