#pragma once

#include "include/modules/dropouts.h"
#include "include/modules/compander.h"

struct DSPContext {
    struct Parameters {
        float dropoutRatePerMin = 0.0f;
        bool nrTrack4Bypass = false;
    };

    void prepare(double sampleRate, int tracks) {
        sampleRate_ = sampleRate > 1.0 ? sampleRate : 1.0;
        tracks_ = tracks > 0 ? tracks : 1;
        dropouts_.prepare(static_cast<float>(sampleRate_), tracks_);
        compander_.prepare(static_cast<float>(sampleRate_), tracks_);
    }

    void process(float* interleaved, int frames, int channels, const Parameters& parameters) {
        if (!interleaved || frames <= 0 || channels <= 0) {
            return;
        }

        if (channels != tracks_) {
            tracks_ = channels;
            dropouts_.prepare(static_cast<float>(sampleRate_), tracks_);
            compander_.prepare(static_cast<float>(sampleRate_), tracks_);
        }

        dropouts_.setRate(parameters.dropoutRatePerMin);
        compander_.setTrackBypass(3, parameters.nrTrack4Bypass);

        dropouts_.process(interleaved, frames, channels);
        compander_.process(interleaved, frames, channels);
    }

    int dropoutCount() const { return dropouts_.dropoutCount(); }

private:
    double sampleRate_ = 48000.0;
    int tracks_ = 4;
    Dropouts dropouts_;
    Compander compander_;
};

