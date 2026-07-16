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
    // [-100,100] (shifts chroma). `highlight` in [-1,1] (lifts bright areas),
    // `shadow` in [-1,1] (lifts dark areas). `hueShift` in [-180,180] rotates
    // hue. `dryWet` in [0,1] mixes original vs graded (dry=0, wet=1).
    // Defaults are 0 / 1 / 1 / 0 / 0 (identity).
    static void applyColorGrade(AVFrame* frame, double brightness, double contrast,
                                double saturation, double temperature = 0.0,
                                double tint = 0.0, double highlight = 0.0,
                                double shadow = 0.0, double hueShift = 0.0,
                                double dryWet = 1.0);

    // Crop a rectangular region from `src` and write it into `dst` (both RGBA
    // images).  `left/top/right/bottom` are fractions of the source dimensions
    // (0..1).  Identity (all zeros) means the full frame is copied.
    static void applyCrop(const QImage& src, QImage& dst,
                          double left, double top, double right, double bottom);
};

} // namespace ghita::fx
