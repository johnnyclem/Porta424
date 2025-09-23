#include "PortaDSPBridge.h"
#include <atomic>
#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include "../../../../DSPCore/include/modules/head_bump.h"
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

struct PortaStubContext {
    double fs = 48000.0;
    int maxBlock = 512;
    int tracks = 4;
    std::atomic<porta_params_t> params;
    porta_params_t currentParams{};
    HeadBump headBump;
    std::vector<float> rmsAcc;
    std::vector<int> rmsCount;
    float driveLinState = 1.0f;
    float trimState = 1.0f;
};

porta_dsp_handle porta_create(double sampleRate, int maxBlock, int tracks) {
    auto* ctx = new PortaStubContext();
    ctx->fs = sampleRate;
    ctx->maxBlock = maxBlock;
    ctx->tracks = tracks;
    porta_params_t p{};
    ctx->params.store(p, std::memory_order_relaxed);
    ctx->currentParams = p;
    ctx->driveLinState = 1.0f;
    ctx->trimState = lookupTrim(0.0f);
    ctx->rmsAcc.assign(8, 0.0f);
    ctx->rmsCount.assign(8, 0);
    int channels = tracks > 0 ? tracks : 1;
    ctx->headBump.prepare(static_cast<float>(ctx->fs), channels);
    ctx->headBump.setParams(p.headBumpFreqHz, p.headBumpGainDb);
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

    // Load latest params and (re)configure modules if needed.
    porta_params_t p = ctx->params.load(std::memory_order_acquire);
    if (ctx->headBump.channelCount() != ch) {
        ctx->headBump.prepare(static_cast<float>(ctx->fs), ch);
    }
    ctx->headBump.setParams(p.headBumpFreqHz, p.headBumpGainDb);
    ctx->currentParams = p;

    // Saturation drive/trim smoothing across the block.
    float targetDriveDb  = p.satDriveDb;
    float targetDriveLin = std::max(dbToLinear(targetDriveDb), 1e-6f);
    float targetTrim     = lookupTrim(targetDriveDb);

    int totalFrames   = frames;
    int totalChannels = ch;

    float drive = ctx->driveLinState;
    float trim  = ctx->trimState;

    float driveStep = (targetDriveLin - drive) / static_cast<float>(std::max(1, totalFrames));
    float trimStep  = (targetTrim     - trim ) / static_cast<float>(std::max(1, totalFrames));

    for (int i = 0; i < totalFrames; ++i) {
        drive += driveStep;
        trim  += trimStep;
        for (int c = 0; c < totalChannels; ++c) {
            float* s = &inter[i * totalChannels + c];
            float x = *s;

            // Head bump EQ first, then saturation with drive + trim.
            float hb = ctx->headBump.processSample(x, c);
            float shaped = std::tanh(drive * hb);
            float y = shaped * trim;

            *s = y;

            // Rough per-channel RMS metering.
            if (c < static_cast<int>(ctx->rmsAcc.size())) {
                ctx->rmsAcc[c]   += y * y;
                ctx->rmsCount[c] += 1;
            }
        }
    }

    ctx->driveLinState = drive;
    ctx->trimState     = trim;
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
