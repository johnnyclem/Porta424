#pragma once

#ifdef __cplusplus
extern "C" {
#endif

void porta_dsp_passthrough(const float* input,
                           float* output,
                           int frames,
                           int channels);

#ifdef __cplusplus
}
#endif

