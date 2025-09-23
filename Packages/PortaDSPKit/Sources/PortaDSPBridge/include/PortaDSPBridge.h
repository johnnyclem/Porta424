
#pragma once
#include <stdint.h>
#include "dsp_passthrough.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef void* porta_dsp_handle;

typedef struct {
    float wowDepth;
    float flutterDepth;
    float headBumpGainDb;
    float headBumpFreqHz;
    float satDriveDb;
    float hissLevelDbFS;
    float lpfCutoffHz;
    float azimuthJitterMs;
    float crosstalkDb;
    float dropoutRatePerMin;
    int   nrTrack4Bypass; // 0/1
} porta_params_t;

porta_dsp_handle porta_create(double sampleRate, int maxBlock, int tracks);
void porta_destroy(porta_dsp_handle h);

// Thread-safe atomic swap of parameters
void porta_update_params(porta_dsp_handle h, const porta_params_t* p);

// Process in-place (interleaved float32 stereo for simplicity in stub)
void porta_process_interleaved(porta_dsp_handle h, float* interleaved, int frames, int channels);

// Simple meter readback (RMS in dBFS for up to 8 channels)
int porta_get_meters_dbfs(porta_dsp_handle h, float* outDbfs, int maxChannels);

float porta_test_saturation(float sample, float driveDb);
void porta_test_head_bump(const float* input, float* output, int frames, float sampleRate, float gainDb, float freqHz);
void porta_test_wow_flutter(const float* input, float* output, int frames, float sampleRate, float wowDepth, float flutterDepth, float wowRate, float flutterRate);

#ifdef __cplusplus
} // extern "C"
#endif
