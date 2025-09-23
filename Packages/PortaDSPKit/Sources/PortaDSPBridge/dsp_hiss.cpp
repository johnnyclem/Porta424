#include "PortaDSPBridge.h"

#include <algorithm>
#include <cstring>
#include <vector>

#include "../../../../DSPCore/include/modules/hf_loss.h"
#include "../../../../DSPCore/include/modules/hiss.h"

extern "C" {

void porta_test_render_hiss(float* out, int frames, int channels, float sampleRate, float hissLevelDbFS, uint64_t seed) {
    if (!out || frames <= 0 || channels <= 0) {
        return;
    }

    Hiss hiss;
    hiss.prepare(sampleRate, channels);
    hiss.setSeed(seed);
    hiss.setLevelDbFS(hissLevelDbFS);

    std::vector<float> buffer(static_cast<size_t>(frames) * static_cast<size_t>(channels), 0.0f);
    hiss.process(buffer.data(), frames, channels);
    std::memcpy(out, buffer.data(), buffer.size() * sizeof(float));
}

void porta_test_apply_hf_loss(const float* input, float* output, int frames, int channels, float sampleRate, float cutoffHz) {
    if (!output || frames <= 0 || channels <= 0) {
        return;
    }

    HFLoss loss;
    loss.prepare(sampleRate, channels);
    loss.setCutoff(cutoffHz);

    std::vector<float> buffer(static_cast<size_t>(frames) * static_cast<size_t>(channels));
    if (input) {
        std::memcpy(buffer.data(), input, buffer.size() * sizeof(float));
    } else {
        std::fill(buffer.begin(), buffer.end(), 0.0f);
    }

    loss.process(buffer.data(), frames, channels);
    std::memcpy(output, buffer.data(), buffer.size() * sizeof(float));
}

}
