#include "PortaDSPBridge.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstring>
#include <vector>

#include "../../../../DSPCore/include/modules/azimuth.h"
#include "../../../../DSPCore/include/modules/compander.h"
#include "../../../../DSPCore/include/modules/crosstalk.h"
#include "../../../../DSPCore/include/modules/dropouts.h"
#include "../../../../DSPCore/include/modules/eq.h"
#include "../../../../DSPCore/include/modules/head_bump.h"
#include "../../../../DSPCore/include/modules/hf_loss.h"
#include "../../../../DSPCore/include/modules/hiss.h"
#include "../../../../DSPCore/include/modules/meters.h"
#include "../../../../DSPCore/include/modules/saturation.h"
#include "../../../../DSPCore/include/modules/wow_flutter.h"

struct PortaStubContext {
    double fs = 48000.0;
    int maxBlock = 512;
    int tracks = 4;
    std::atomic<porta_params_t> params;
    Saturation saturation;
    HeadBump headBump;
    WowFlutter wowFlutter;
    Hiss hiss;
    HFLoss hfLoss;
    Azimuth azimuth;
    Crosstalk crosstalk;
    Dropouts dropouts;
    Compander compander;
    EQ eq;
    Meters meters;
};

static void updateModuleParameters(PortaStubContext* ctx, const porta_params_t& p) {
    ctx->saturation.setDriveDb(p.satDriveDb);
    ctx->headBump.setGainDb(p.headBumpGainDb);
    ctx->headBump.setFrequency(p.headBumpFreqHz);
    ctx->wowFlutter.setWowDepth(p.wowDepth);
    ctx->wowFlutter.setFlutterDepth(p.flutterDepth);
    ctx->hfLoss.setCutoffHz(p.lpfCutoffHz);
    ctx->hiss.setLevelDbFS(p.hissLevelDbFS);
    ctx->crosstalk.setAmountDb(p.crosstalkDb);
    ctx->dropouts.setRatePerMinute(p.dropoutRatePerMin);
}

porta_dsp_handle porta_create(double sampleRate, int maxBlock, int tracks) {
    auto* ctx = new PortaStubContext();
    ctx->fs = sampleRate;
    ctx->maxBlock = maxBlock;
    ctx->tracks = tracks;
    porta_params_t p{};
    ctx->params.store(p, std::memory_order_relaxed);

    ctx->saturation.prepare(static_cast<float>(sampleRate), maxBlock);
    ctx->headBump.prepare(static_cast<float>(sampleRate), maxBlock);
    ctx->wowFlutter.prepare(static_cast<float>(sampleRate), maxBlock);
    ctx->hiss.prepare(static_cast<float>(sampleRate), maxBlock);
    ctx->hfLoss.prepare(static_cast<float>(sampleRate), maxBlock);
    ctx->azimuth.prepare(static_cast<float>(sampleRate), maxBlock);
    ctx->crosstalk.prepare(static_cast<float>(sampleRate), maxBlock);
    ctx->dropouts.prepare(static_cast<float>(sampleRate), maxBlock);
    ctx->compander.prepare(static_cast<float>(sampleRate), maxBlock);
    ctx->eq.prepare(static_cast<float>(sampleRate), maxBlock);
    ctx->meters.prepare(static_cast<float>(sampleRate), maxBlock);
    ctx->meters.clear();

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

void porta_process_interleaved(porta_dsp_handle h, float* interleaved, int frames, int channels) {
    auto* ctx = (PortaStubContext*)h;
    if (!ctx || !interleaved || frames <= 0 || channels <= 0) {
        return;
    }

    porta_params_t params = ctx->params.load(std::memory_order_acquire);
    updateModuleParameters(ctx, params);

    ctx->wowFlutter.processBlock(interleaved, frames, channels);
    ctx->headBump.processBlock(interleaved, frames, channels);
    ctx->eq.processBlock(interleaved, frames, channels);
    ctx->saturation.processBlock(interleaved, frames, channels);
    ctx->hfLoss.processBlock(interleaved, frames, channels);
    ctx->crosstalk.processBlock(interleaved, frames, channels);
    ctx->dropouts.processBlock(interleaved, frames, channels);
    ctx->hiss.processBlock(interleaved, frames, channels);
    ctx->meters.processBlock(interleaved, frames, channels);
}

int porta_get_meters_dbfs(porta_dsp_handle h, float* outDbfs, int maxChannels) {
    auto* ctx = (PortaStubContext*)h;
    if (!ctx || !outDbfs || maxChannels <= 0) {
        return 0;
    }

    int available = std::min(maxChannels, ctx->meters.channels());
    for (int i = 0; i < available; ++i) {
        outDbfs[i] = ctx->meters.rmsDb(i);
    }
    ctx->meters.clear();
    return available;
}

float porta_test_saturation(float sample, float driveDb) {
    Saturation s;
    s.prepare(48000.0f, 1);
    s.setDriveDb(driveDb);
    float value = sample;
    s.processBlock(&value, 1, 1);
    return value;
}

void porta_test_head_bump(const float* input, float* output, int frames, float sampleRate, float gainDb, float freqHz) {
    if (!input || !output || frames <= 0) {
        return;
    }
    HeadBump hb;
    hb.prepare(sampleRate, frames);
    hb.setGainDb(gainDb);
    hb.setFrequency(freqHz);
    std::memcpy(output, input, sizeof(float) * frames);
    hb.processBlock(output, frames, 1);
}

void porta_test_wow_flutter(const float* input, float* output, int frames, float sampleRate, float wowDepth, float flutterDepth, float wowRate, float flutterRate) {
    if (!input || !output || frames <= 0) {
        return;
    }
    WowFlutter wf;
    wf.prepare(sampleRate, frames);
    wf.setWowDepth(wowDepth);
    wf.setFlutterDepth(flutterDepth);
    wf.setWowRate(wowRate);
    wf.setFlutterRate(flutterRate);
    std::memcpy(output, input, sizeof(float) * frames);
    wf.processBlock(output, frames, 1);
}

