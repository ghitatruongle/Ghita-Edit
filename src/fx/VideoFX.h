#pragma once

extern "C" {
#include <libavutil/frame.h>
}

namespace ghita::fx {

// VideoFX: CPU color-grading pass applied to decoded YUV420P frames during
// export (M3). Runs fast enough for offline rendering; a GPU compute pipeline
// (Vulkan/OpenGL) is a later optimization for real-time preview.
class VideoFX {
public:
    // Apply a brightness / contrast / saturation / temperature / tint grade
    // in-place to a YUV420P frame. `brightness` in [-1,1] (added to luma),
    // `contrast`/[0,2], `saturation`/[0,2], `temperature` & `tint` in
    // [-100,100] (shifts chroma). Defaults are 0 / 1 / 1 / 0 / 0 (identity).
    static void applyColorGrade(AVFrame* frame, double brightness, double contrast,
                                double saturation, double temperature = 0.0,
                                double tint = 0.0);
};

} // namespace ghita::fx
