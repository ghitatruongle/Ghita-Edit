#pragma once

#include <cstdint>

extern "C" {
#include <libavutil/rational.h>
}

namespace ghita::export_ {

// Result of probing the first video clip: output geometry + rate for the mux.
struct ExportProfile {
    int outW = 1280;
    int outH = 720;
    AVRational outSar{1, 1};
    AVRational outFps{30000, 1001};
};

} // namespace ghita::export_
