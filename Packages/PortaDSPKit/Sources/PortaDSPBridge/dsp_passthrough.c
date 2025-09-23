#include "dsp_passthrough.h"
#include <stddef.h>
#include <string.h>

void porta_dsp_passthrough(const float* input,
                           float* output,
                           int frames,
                           int channels) {
    if (input == NULL || output == NULL || frames <= 0 || channels <= 0) {
        return;
    }

    size_t totalSamples = (size_t)frames * (size_t)channels;
    memmove(output, input, totalSamples * sizeof(float));
}
