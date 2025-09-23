
#include "PortaDSPBridge.h"
#include <atomic>
#include <vector>
#include <cmath>
#include <cstring>
#include "../../../../DSPCore/include/modules/head_bump.h"

struct PortaStubContext {
    double fs = 48000.0;
    int maxBlock = 512;
    int tracks = 4;
    std::atomic<porta_params_t> params;
    porta_params_t currentParams{};
    HeadBump headBump;
    std::vector<float> rmsAcc;
    std::vector<int> rmsCount;
};

porta_dsp_handle porta_create(double sampleRate, int maxBlock, int tracks) {
    auto* ctx = new PortaStubContext();
    ctx->fs = sampleRate;
    ctx->maxBlock = maxBlock;
    ctx->tracks = tracks;
    porta_params_t p{};
    ctx->params.store(p, std::memory_order_relaxed);
    ctx->currentParams = p;
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

    porta_params_t params = ctx->params.load(std::memory_order_acquire);
    if (ctx->headBump.channelCount() != ch) {
        ctx->headBump.prepare(static_cast<float>(ctx->fs), ch);
    }
    ctx->headBump.setParams(params.headBumpFreqHz, params.headBumpGainDb);
    ctx->currentParams = params;

    for (int i = 0; i < frames; ++i) {
        for (int c = 0; c < ch; ++c) {
            float* s = &inter[i * ch + c];
            float x = *s;
            float filtered = ctx->headBump.processSample(x, c);
            float y = std::tanh(filtered);
            *s = y;
            int idx = c;
            if (idx < (int)ctx->rmsAcc.size()) {
                ctx->rmsAcc[idx] += y * y;
                ctx->rmsCount[idx] += 1;
            }
        }
    }
}

int porta_get_meters_dbfs(porta_dsp_handle h, float* outDbfs, int maxCh) {
    auto* ctx = (PortaStubContext*)h;
    int n = std::min(maxCh, (int)ctx->rmsAcc.size());
    for (int i=0;i<n;i++) {
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
