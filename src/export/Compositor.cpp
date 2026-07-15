#include "Compositor.h"

#include "timeline/TimelineModel.h"
#include "timeline/Clip.h"

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
        const int base = qRound(qMin(img.width(), img.height()) * 0.3);
        QImage sized = sticker.scaled(base, base, Qt::KeepAspectRatio, Qt::SmoothTransformation);
        p.drawImage(QPointF(-sized.width() / 2.0, -sized.height() / 2.0), sized);
    }
}

} // namespace ghita::export_
