
#include "PortaDSPBridge.h"
#include "dsp_context.h"
#include <algorithm>
#include <atomic>
#include <vector>
#include <cmath>
#include <cstring>

struct PortaStubContext {
    double fs = 48000.0;
    int maxBlock = 512;
    int tracks = 4;
    std::atomic<porta_params_t> params;
    std::vector<float> rmsAcc;
    std::vector<int> rmsCount;
    DSPContext dsp;
};

porta_dsp_handle porta_create(double sampleRate, int maxBlock, int tracks) {
    auto* ctx = new PortaStubContext();
    ctx->fs = sampleRate;
    ctx->maxBlock = maxBlock;
    ctx->tracks = tracks;
    porta_params_t p{};
    ctx->params.store(p, std::memory_order_relaxed);
    ctx->dsp.prepare(sampleRate, tracks);
    ctx->rmsAcc.assign(8, 0.0f);
    ctx->rmsCount.assign(8, 0);
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
    if (!ctx || !inter || frames <= 0 || ch <= 0) {
        return;
    }

    const porta_params_t params = ctx->params.load(std::memory_order_acquire);
    DSPContext::Parameters dspParams;
    dspParams.dropoutRatePerMin = params.dropoutRatePerMin;
    dspParams.nrTrack4Bypass = params.nrTrack4Bypass != 0;

    ctx->dsp.process(inter, frames, ch, dspParams);

    for (int i = 0; i < frames; ++i) {
        for (int c = 0; c < ch; ++c) {
            const float sample = inter[i * ch + c];
            if (c < (int)ctx->rmsAcc.size()) {
                ctx->rmsAcc[c] += sample * sample;
                ctx->rmsCount[c] += 1;
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
