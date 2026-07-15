#pragma once

#include <QImage>

namespace ghita::timeline { class TimelineModel; class Clip; }

namespace ghita::export_ {

// Compositor: bakes Text/Sticker overlay clips onto a single RGBA video frame
// during export. It reads the same OverlayData + Keyframes that the QML preview
// uses, so what you see in the preview matches the exported file.
//
// The Exporter is responsible for decoding the base (V1) frame into an RGBA
// QImage at the output resolution; Compositor then draws every overlay clip
// active at the given timeline time `t` on top of it.
class Compositor {
public:
    // Composite all Text/Sticker overlay clips active at timeline time `t`
    // onto `img` (RGBA, already scaled to the output resolution). Modifies img.
    static void composite(QImage& img, const timeline::TimelineModel* timeline, qint64 t);

private:
    static void drawOverlay(QImage& img, const timeline::Clip& clip, qint64 t,
                            const timeline::TimelineModel* timeline);
};

} // namespace ghita::export_
