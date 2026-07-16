#include "Compositor.h"

#include "timeline/TimelineModel.h"
#include "timeline/Clip.h"
#include "fx/VideoFX.h"

#include <QPainter>
#include <QFont>
#include <QFontMetrics>
#include <QFontMetricsF>
#include <QColor>
#include <QFile>
#include <QHash>
#include <QtMath>

namespace ghita::export_ {

namespace {
// Cache decoded sticker images by path (export runs many frames; re-decoding
// the same SVG/PNG every frame would be wasteful).
QHash<QString, QImage>& stickerCache() {
    static QHash<QString, QImage> cache;
    return cache;
}

QImage loadSticker(const QString& path) {
    auto& cache = stickerCache();
    auto it = cache.find(path);
    if (it != cache.end()) return *it;
    QImage img(path);
    if (img.isNull()) img = QImage(64, 64, QImage::Format_RGBA8888);
    cache.insert(path, img);
    return img;
}
} // namespace

void Compositor::composite(QImage& img, const timeline::TimelineModel* timeline, qint64 t) {
    if (!timeline) return;
    const int rows = timeline->rowCount();
    for (int i = 0; i < rows; ++i) {
        const int kind = timeline->clipKind(i);
        if (kind != 2 && kind != 3) continue; // only Text/Sticker
        const qint64 start = timeline->clipStartMs(i);
        const qint64 end = timeline->clipEndMs(i);
        if (t < start || t >= end) continue;
        const qint64 id = timeline->clipId(i);
        const auto* clip = timeline->findClip(id);
        if (!clip) continue;
        drawOverlay(img, *clip, t, timeline);
    }
}

void Compositor::drawOverlay(QImage& img, const timeline::Clip& clip, qint64 t,
                             const timeline::TimelineModel* timeline) {
    const auto& o = clip.overlay;

    // Resolve transform values (keyframed if present, else base).
    const double posX = timeline->overlayValueAt(clip.id, "posX", t);
    const double posY = timeline->overlayValueAt(clip.id, "posY", t);
    const double scale = timeline->overlayValueAt(clip.id, "scale", t);
    const double rotation = timeline->overlayValueAt(clip.id, "rotation", t);
    const double opacity = timeline->overlayValueAt(clip.id, "opacity", t);

    // Crop values (non-keyframed for now; base overlay data).
    const double cropLeft = o.cropLeft;
    const double cropTop = o.cropTop;
    const double cropRight = o.cropRight;
    const double cropBottom = o.cropBottom;

    const qreal cx = posX * img.width();
    const qreal cy = posY * img.height();

    QPainter p(&img);
    p.setRenderHint(QPainter::Antialiasing);
    p.setRenderHint(QPainter::SmoothPixmapTransform);
    p.translate(cx, cy);
    p.rotate(rotation);
    p.scale(scale, scale);
    p.setOpacity(qBound(0.0, opacity, 1.0));

    if (clip.kind == timeline::ClipKind::Text) {
        // Apply crop by adjusting the text box to simulate a cropped canvas.
        // The crop offsets define how much of the surrounding area is hidden.
        // We map the visible region into a smaller drawing area.
        if (cropLeft > 0 || cropTop > 0 || cropRight > 0 || cropBottom > 0) {
            const int cw = qRound(img.width() * (1.0 - cropLeft - cropRight));
            const int ch = qRound(img.height() * (1.0 - cropTop - cropBottom));
            if (cw > 0 && ch > 0) {
                p.save();
                p.setClipping(true);
                p.fillRect(QRect(0, 0, img.width(), img.height()), Qt::black);
                p.translate(-cx + (cx * (cropLeft - cropRight) / 2.0),
                            -cy + (cy * (cropTop - cropBottom) / 2.0));
                p.scale(double(cw) / img.width(), double(ch) / img.height());
            }
        }

        const int fontPx = qMax(8, qRound(o.fontSize * img.height() / 720.0));
        QFont font(o.fontFamily.isEmpty() ? "Segoe UI" : o.fontFamily, fontPx);
        font.setBold(o.bold);
        p.setFont(font);

        const int th = QFontMetrics(font).height();
        QRectF box(-img.width() / 2.0, -th / 2.0, img.width(), th);
        int flags = Qt::AlignVCenter;
        if (o.align == 0) flags |= Qt::AlignLeft;
        else if (o.align == 2) flags |= Qt::AlignRight;
        else flags |= Qt::AlignHCenter;

        if (o.bgColor.alpha() > 0) {
            QRectF bg = QFontMetricsF(font).boundingRect(box, flags, o.text);
            bg.adjust(-8, -4, 8, 4);
            p.setPen(Qt::NoPen);
            p.setBrush(o.bgColor);
            p.drawRoundedRect(bg, 6, 6);
        }

        p.setPen(o.color);
        p.setBrush(Qt::NoBrush);
        p.drawText(box, flags, o.text);
    } else { // Sticker
        QImage sticker = loadSticker(o.stickerPath);
        if (sticker.isNull()) return;

        // Apply crop to the sticker image.
        QImage cropped;
        if (cropLeft > 0 || cropTop > 0 || cropRight > 0 || cropBottom > 0) {
            VideoFX::applyCrop(sticker, cropped, cropLeft, cropTop, cropRight, cropBottom);
            if (cropped.isNull()) return;
        } else {
            cropped = sticker;
        }

        const int base = qRound(qMin(img.width(), img.height()) * 0.3);
        QImage sized = cropped.scaled(base, base, Qt::KeepAspectRatio, Qt::SmoothTransformation);
        p.drawImage(QPointF(-sized.width() / 2.0, -sized.height() / 2.0), sized);
    }
}

} // namespace ghita::export_
