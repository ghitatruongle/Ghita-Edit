#include "TimelineModel.h"
#include "TimelineCommands.h"
#include "WaveformRenderer.h"

#include <QColor>
#include <QDebug>
#include <QFileInfo>
#include <QTimer>
#include <algorithm>
#include <cmath>
#include <functional>

namespace ghita::timeline {

TimelineModel::TimelineModel(QObject* parent)
    : QAbstractListModel(parent) {
    connect(&undoStack_, &QUndoStack::indexChanged,
            this, &TimelineModel::undoRedoChanged);
    connect(&undoStack_, &QUndoStack::cleanChanged,
            this, [this]() {
                // Update cached action text for undo/redo.
                if (undoStack_.canUndo()) {
                    lastUndoActionText_ = undoStack_.text(undoStack_.index() - 1);
                    emit lastUndoActionChanged();
                }
                if (undoStack_.canRedo()) {
                    lastRedoActionText_ = undoStack_.text(undoStack_.index());
                    emit lastRedoActionChanged();
                }
                emit undoStackSizeChanged();
            });
    initDefaultTracks();
}

int TimelineModel::rowCount(const QModelIndex&) const {
    return clips_.size();
}

QVariant TimelineModel::data(const QModelIndex& index, int role) const {
    if (!index.isValid() || index.row() >= clips_.size())
        return {};
    const auto& c = clips_[index.row()];
    switch (role) {
        case IdRole:           return QVariant::fromValue(static_cast<qlonglong>(c.id));
        case SourcePathRole:   return c.sourcePath;
        case TimelineStartRole: return QVariant::fromValue(static_cast<qlonglong>(c.timelineStartMs));
        case TimelineEndRole:  return QVariant::fromValue(static_cast<qlonglong>(c.timelineEndMs));
        case SrcInRole:        return QVariant::fromValue(static_cast<qlonglong>(c.srcInMs));
        case SrcOutRole:       return QVariant::fromValue(static_cast<qlonglong>(c.srcOutMs));
        case TrackIndexRole:   return c.trackIndex;
        case ColorRole:        return c.color;
        case DurationRole:     return QVariant::fromValue(static_cast<qlonglong>(c.durationMs()));
        case KindRole:         return static_cast<int>(c.kind);
        case OverlayLabelRole:
            if (c.kind == ClipKind::Text) return c.overlay.text;
            if (c.kind == ClipKind::Sticker) return QStringLiteral("Sticker");
            if (c.kind == ClipKind::PipVideo) return QStringLiteral("PIP Video");
            if (c.kind == ClipKind::PipImage) return QStringLiteral("PIP Image");
            return QFileInfo(c.sourcePath).fileName();
        case WaveformRole:
            if (c.kind == ClipKind::Audio) {
                return waveformCache_.value(c.sourcePath, QVariant());
            }
            return {};
        case PlaybackSpeedRole:
            return c.playbackSpeed;
        case PitchCorrectionRole:
            return c.pitchCorrection;
    }
    return {};
}

QHash<int, QByteArray> TimelineModel::roleNames() const {
    return {
        { IdRole, "clipId" },
        { SourcePathRole, "sourcePath" },
        { TimelineStartRole, "timelineStart" },
        { TimelineEndRole, "timelineEnd" },
        { SrcInRole, "srcIn" },
        { SrcOutRole, "srcOut" },
        { TrackIndexRole, "trackIndex" },
        { ColorRole, "clipColor" },
        { DurationRole, "clipDuration" },
        { KindRole, "clipKind" },
        { OverlayLabelRole, "overlayLabel" },
        { WaveformRole, "waveform" },
        { PlaybackSpeedRole, "playbackSpeed" },
        { PitchCorrectionRole, "pitchCorrection" },
    };
}

qint64 TimelineModel::durationMs() const {
    return durationMs_;
}

void TimelineModel::setPlayheadMs(qint64 ms) {
    if (playheadMs_ == ms) return;
    playheadMs_ = ms;
    emit playheadChanged(ms);
}

bool TimelineModel::canUndo() const {
    return undoStack_.canUndo();
}

bool TimelineModel::canRedo() const {
    return undoStack_.canRedo();
}

QString TimelineModel::lastUndoAction() const {
    if (undoStack_.canUndo()) {
        QString t = undoStack_.text(undoStack_.index() - 1);
        if (!t.isEmpty()) return t;
    }
    return lastUndoActionText_;
}

QString TimelineModel::lastRedoAction() const {
    if (undoStack_.canRedo()) {
        QString t = undoStack_.text(undoStack_.index());
        if (!t.isEmpty()) return t;
    }
    return lastRedoActionText_;
}

int TimelineModel::undoStackSize() const {
    return undoStack_.count();
}

// ---- Editing operations ----

void TimelineModel::addClip(const QString& sourcePath, qint64 srcInMs,
                             qint64 srcOutMs, qint64 timelineStartMs,
                             int trackIndex) {
    Clip clip;
    clip.id = nextId_++;
    clip.sourcePath = sourcePath;
    clip.srcInMs = srcInMs;
    clip.srcOutMs = srcOutMs;
    clip.timelineStartMs = timelineStartMs;
    clip.timelineEndMs = timelineStartMs + (srcOutMs - srcInMs);
    clip.trackIndex = trackIndex;
    clip.color = (trackIndex == 0) ? "#3a5f8a" : "#8a3a5f";
    clip.playbackSpeed = 1.0;
    clip.pitchCorrection = true;

    undoStack_.push(new AddClipCommand(this, clip));
}

void TimelineModel::splitClipAtPlayhead(qint64 clipId) {
    auto* clip = findClip(clipId);
    if (!clip || playheadMs_ <= clip->timelineStartMs ||
        playheadMs_ >= clip->timelineEndMs) {
        qWarning() << "[Timeline] Cannot split: playhead not inside clip";
        return;
    }
    undoStack_.push(new CutCommand(this, clipId, playheadMs_));
}

void TimelineModel::trimClipLeft(qint64 clipId, qint64 newTimelineStartMs) {
    auto* clip = findClip(clipId);
    if (!clip) return;
    if (newTimelineStartMs >= clip->timelineEndMs) return;

    qint64 delta = newTimelineStartMs - clip->timelineStartMs;
    undoStack_.push(new TrimCommand(this, clipId, delta, TrimCommand::Left));
}

void TimelineModel::trimClipRight(qint64 clipId, qint64 newTimelineEndMs) {
    auto* clip = findClip(clipId);
    if (!clip) return;
    if (newTimelineEndMs <= clip->timelineStartMs) return;

    qint64 delta = newTimelineEndMs - clip->timelineEndMs;
    undoStack_.push(new TrimCommand(this, clipId, delta, TrimCommand::Right));
}

void TimelineModel::moveClip(qint64 clipId, qint64 newTimelineStartMs,
                              int newTrackIndex) {
    auto* clip = findClip(clipId);
    if (!clip) return;

    qint64 timeDelta = newTimelineStartMs - clip->timelineStartMs;
    int trackDelta = newTrackIndex - clip->trackIndex;
    undoStack_.push(new MoveCommand(this, clipId, timeDelta, trackDelta));
}

void TimelineModel::deleteClip(qint64 clipId) {
    auto* clip = findClip(clipId);
    if (!clip) return;
    undoStack_.push(new DeleteClipCommand(this, *clip));
}

void TimelineModel::undo() {
    if (undoStack_.canUndo()) {
        undoStack_.undo();
        recalcDuration();
        emit durationChanged(durationMs_);
    }
}

void TimelineModel::redo() {
    if (undoStack_.canRedo()) {
        undoStack_.redo();
        recalcDuration();
        emit durationChanged(durationMs_);
    }
}

QVariantList TimelineModel::snapTargets() const {
    QVariantList targets;
    targets.append(QVariant::fromValue(static_cast<qlonglong>(playheadMs_)));
    for (const auto& c : clips_) {
        targets.append(QVariant::fromValue(static_cast<qlonglong>(c.timelineStartMs)));
        targets.append(QVariant::fromValue(static_cast<qlonglong>(c.timelineEndMs)));
    }
    return targets;
}

qint64 TimelineModel::clipId(int row) const {
    if (row < 0 || row >= clips_.size()) return -1;
    return clips_[row].id;
}

qint64 TimelineModel::clipStartMs(int row) const {
    if (row < 0 || row >= clips_.size()) return 0;
    return clips_[row].timelineStartMs;
}

qint64 TimelineModel::clipEndMs(int row) const {
    if (row < 0 || row >= clips_.size()) return 0;
    return clips_[row].timelineEndMs;
}

// ---- Overlay clips ----

void TimelineModel::addTextClip(qint64 timelineStartMs, qint64 durationMs) {
    if (durationMs <= 0) return;
    Clip clip;
    clip.id = nextId_++;
    clip.kind = ClipKind::Text;
    clip.trackIndex = 2;
    clip.timelineStartMs = timelineStartMs;
    clip.timelineEndMs = timelineStartMs + durationMs;
    clip.color = "#ffd93d";
    clip.overlay.text = "Text";
    clip.overlay.fontSize = 48;
    clip.overlay.bold = false;
    clip.overlay.color = Qt::white;
    clip.overlay.align = 1;
    clip.overlay.bgColor = Qt::transparent;
    clip.overlay.posX = 0.5;
    clip.overlay.posY = 0.5;
    clip.overlay.scale = 1.0;
    clip.overlay.rotation = 0.0;
    clip.overlay.opacity = 1.0;
    clip.playbackSpeed = 1.0;
    clip.pitchCorrection = true;

    undoStack_.push(new AddClipCommand(this, clip));
}

void TimelineModel::addTextClip(const QString& text, qint64 timelineStartMs,
                                 qint64 durationMs) {
    if (durationMs <= 0) return;
    Clip clip;
    clip.id = nextId_++;
    clip.kind = ClipKind::Text;
    clip.trackIndex = 2;
    clip.timelineStartMs = timelineStartMs;
    clip.timelineEndMs = timelineStartMs + durationMs;
    clip.color = "#ffd93d";
    clip.overlay.text = text.isEmpty() ? QStringLiteral("Text") : text;
    clip.overlay.fontSize = 48;
    clip.overlay.bold = false;
    clip.overlay.color = Qt::white;
    clip.overlay.align = 1;
    clip.overlay.bgColor = Qt::transparent;
    clip.overlay.posX = 0.5;
    clip.overlay.posY = 0.5;
    clip.overlay.scale = 1.0;
    clip.overlay.rotation = 0.0;
    clip.overlay.opacity = 1.0;
    clip.playbackSpeed = 1.0;
    clip.pitchCorrection = true;

    undoStack_.push(new AddClipCommand(this, clip));
}

void TimelineModel::addStickerClip(const QString& stickerPath, qint64 timelineStartMs,
                                    qint64 durationMs) {
    if (durationMs <= 0 || stickerPath.isEmpty()) return;
    Clip clip;
    clip.id = nextId_++;
    clip.kind = ClipKind::Sticker;
    clip.trackIndex = 2;
    clip.timelineStartMs = timelineStartMs;
    clip.timelineEndMs = timelineStartMs + durationMs;
    clip.color = "#ffd93d";
    clip.overlay.stickerPath = stickerPath;
    clip.overlay.posX = 0.5;
    clip.overlay.posY = 0.5;
    clip.overlay.scale = 1.0;
    clip.overlay.rotation = 0.0;
    clip.overlay.opacity = 1.0;
    clip.playbackSpeed = 1.0;
    clip.pitchCorrection = true;

    undoStack_.push(new AddClipCommand(this, clip));
}

int TimelineModel::clipKind(int row) const {
    if (row < 0 || row >= clips_.size()) return 0;
    return static_cast<int>(clips_[row].kind);
}

int TimelineModel::kindOfClip(qint64 id) const {
    const Clip* c = findClip(id);
    if (!c) return -1;
    return static_cast<int>(c->kind);
}

// ---- PIP clip creation ----

void TimelineModel::addPipClip(const QString& sourcePath, qint64 timelineStartMs,
                                qint64 durationMs, ClipKind kind) {
    if (durationMs <= 0 || sourcePath.isEmpty()) return;
    Clip clip;
    clip.id = nextId_++;
    clip.kind = kind;
    clip.sourcePath = sourcePath;
    clip.trackIndex = 2; // overlay track
    clip.timelineStartMs = timelineStartMs;
    clip.timelineEndMs = timelineStartMs + durationMs;
    clip.color = "#e06cff"; // magenta for PIP
    clip.overlay.posX = 0.75;
    clip.overlay.posY = 0.75;
    clip.overlay.scale = 0.3;
    clip.overlay.opacity = 1.0;
    clip.overlay.pipShadowEnabled = true;
    clip.overlay.pipBorderColor = Qt::white;
    clip.overlay.pipBorderWidth = 2.0;
    clip.overlay.pipCornerRadius = 8.0;
    clip.playbackSpeed = 1.0;
    clip.pitchCorrection = true;

    undoStack_.push(new AddClipCommand(this, clip));
}

void TimelineModel::addPipVideoClip(const QString& sourcePath, qint64 timelineStartMs,
                                     qint64 durationMs) {
    addPipClip(sourcePath, timelineStartMs, durationMs, ClipKind::PipVideo);
}

void TimelineModel::addPipImageClip(const QString& sourcePath, qint64 timelineStartMs,
                                     qint64 durationMs) {
    addPipClip(sourcePath, timelineStartMs, durationMs, ClipKind::PipImage);
}

// ---- Overlay property accessors ----

namespace {
// Apply a mutation to a clip's overlay and push the change through the model.
void editOverlay(TimelineModel* model, qint64 id,
                 const std::function<void(OverlayData&)>& fn) {
    Clip* c = model->findClip(id);
    if (!c) return;
    fn(c->overlay);
    model->modifyClipDirect(*c);
}
} // namespace

QString TimelineModel::overlayText(qint64 id) const {
    const Clip* c = findClip(id);
    return c ? c->overlay.text : QString();
}
void TimelineModel::setOverlayText(qint64 id, const QString& v) {
    editOverlay(this, id, [&](OverlayData& o) { o.text = v; });
}
double TimelineModel::overlayFontSize(qint64 id) const {
    const Clip* c = findClip(id);
    return c ? c->overlay.fontSize : 0.0;
}
void TimelineModel::setOverlayFontSize(qint64 id, double v) {
    editOverlay(this, id, [&](OverlayData& o) { o.fontSize = v; });
}
bool TimelineModel::overlayBold(qint64 id) const {
    const Clip* c = findClip(id);
    return c ? c->overlay.bold : false;
}
void TimelineModel::setOverlayBold(qint64 id, bool v) {
    editOverlay(this, id, [&](OverlayData& o) { o.bold = v; });
}
QString TimelineModel::overlayColor(qint64 id) const {
    const Clip* c = findClip(id);
    return c ? c->overlay.color.name(QColor::HexArgb) : QString();
}
void TimelineModel::setOverlayColor(qint64 id, const QString& v) {
    editOverlay(this, id, [&](OverlayData& o) { o.color = QColor(v); });
}
int TimelineModel::overlayAlign(qint64 id) const {
    const Clip* c = findClip(id);
    return c ? c->overlay.align : 1;
}
void TimelineModel::setOverlayAlign(qint64 id, int v) {
    editOverlay(this, id, [&](OverlayData& o) { o.align = v; });
}
QString TimelineModel::overlayBg(qint64 id) const {
    const Clip* c = findClip(id);
    return c ? c->overlay.bgColor.name(QColor::HexArgb) : QString();
}
void TimelineModel::setOverlayBg(qint64 id, const QString& v) {
    editOverlay(this, id, [&](OverlayData& o) { o.bgColor = QColor(v); });
}
QString TimelineModel::overlaySticker(qint64 id) const {
    const Clip* c = findClip(id);
    return c ? c->overlay.stickerPath : QString();
}
void TimelineModel::setOverlaySticker(qint64 id, const QString& v) {
    editOverlay(this, id, [&](OverlayData& o) { o.stickerPath = v; });
}

void TimelineModel::setOverlayPos(qint64 id, double x, double y) {
    editOverlay(this, id, [&](OverlayData& o) { o.posX = x; o.posY = y; });
}
QPointF TimelineModel::overlayPos(qint64 id) const {
    const Clip* c = findClip(id);
    return c ? QPointF(c->overlay.posX, c->overlay.posY) : QPointF(0.5, 0.5);
}
void TimelineModel::setOverlayScale(qint64 id, double v) {
    editOverlay(this, id, [&](OverlayData& o) { o.scale = v; });
}
double TimelineModel::overlayScale(qint64 id) const {
    const Clip* c = findClip(id);
    return c ? c->overlay.scale : 1.0;
}
void TimelineModel::setOverlayRotation(qint64 id, double v) {
    editOverlay(this, id, [&](OverlayData& o) { o.rotation = v; });
}
double TimelineModel::overlayRotation(qint64 id) const {
    const Clip* c = findClip(id);
    return c ? c->overlay.rotation : 0.0;
}
void TimelineModel::setOverlayOpacity(qint64 id, double v) {
    editOverlay(this, id, [&](OverlayData& o) { o.opacity = v; });
}
double TimelineModel::overlayOpacity(qint64 id) const {
    const Clip* c = findClip(id);
    return c ? c->overlay.opacity : 1.0;
}

// ---- Crop accessors ----

double TimelineModel::overlayCropLeft(qint64 id) const {
    const Clip* c = findClip(id);
    return c ? c->overlay.cropLeft : 0.0;
}
void TimelineModel::setOverlayCropLeft(qint64 id, double v) {
    editOverlay(this, id, [&](OverlayData& o) { o.cropLeft = qBound(0.0, v, 1.0); });
}
double TimelineModel::overlayCropTop(qint64 id) const {
    const Clip* c = findClip(id);
    return c ? c->overlay.cropTop : 0.0;
}
void TimelineModel::setOverlayCropTop(qint64 id, double v) {
    editOverlay(this, id, [&](OverlayData& o) { o.cropTop = qBound(0.0, v, 1.0); });
}
double TimelineModel::overlayCropRight(qint64 id) const {
    const Clip* c = findClip(id);
    return c ? c->overlay.cropRight : 0.0;
}
void TimelineModel::setOverlayCropRight(qint64 id, double v) {
    editOverlay(this, id, [&](OverlayData& o) { o.cropRight = qBound(0.0, v, 1.0); });
}
double TimelineModel::overlayCropBottom(qint64 id) const {
    const Clip* c = findClip(id);
    return c ? c->overlay.cropBottom : 0.0;
}
void TimelineModel::setOverlayCropBottom(qint64 id, double v) {
    editOverlay(this, id, [&](OverlayData& o) { o.cropBottom = qBound(0.0, v, 1.0); });
}
bool TimelineModel::overlayCropLockAspect(qint64 id) const {
    const Clip* c = findClip(id);
    return c ? c->overlay.cropLockAspect : false;
}
void TimelineModel::setOverlayCropLockAspect(qint64 id, bool v) {
    editOverlay(this, id, [&](OverlayData& o) { o.cropLockAspect = v; });
}
bool TimelineModel::overlayCropSnapCenter(qint64 id) const {
    const Clip* c = findClip(id);
    return c ? c->overlay.cropSnapCenter : false;
}
void TimelineModel::setOverlayCropSnapCenter(qint64 id, bool v) {
    editOverlay(this, id, [&](OverlayData& o) { o.cropSnapCenter = v; });
}

// ---- PIP (Picture-in-Picture) ----

namespace {
// Preset positions: top-left, top-right, bottom-left, bottom-right.
struct PipPreset {
    double x, y, scale;
};
static const PipPreset kPipPresets[] = {
    {0.5, 0.5, 1.0},   // 0 = custom
    {0.25, 0.25, 0.3}, // 1 = top-left
    {0.75, 0.25, 0.3}, // 2 = top-right
    {0.25, 0.75, 0.3}, // 3 = bottom-left
    {0.75, 0.75, 0.3}, // 4 = bottom-right
};
} // namespace

void TimelineModel::setPipPreset(qint64 id, int preset) {
    Clip* c = findClip(id);
    if (!c) return;
    if (preset < 0 || preset > 4) return;
    c->overlay.posX = kPipPresets[preset].x;
    c->overlay.posY = kPipPresets[preset].y;
    c->overlay.scale = kPipPresets[preset].scale;
    modifyClipDirect(*c);
}

int TimelineModel::pipPreset(qint64 id) const {
    const Clip* c = findClip(id);
    if (!c) return 0;
    // Check which preset matches best.
    for (int i = 1; i <= 4; ++i) {
        if (qFuzzyCompare(c->overlay.posX, kPipPresets[i].x) &&
            qFuzzyCompare(c->overlay.posY, kPipPresets[i].y) &&
            qFuzzyCompare(c->overlay.scale, kPipPresets[i].scale)) {
            return i;
        }
    }
    return 0; // custom
}

double TimelineModel::pipBorderWidth(qint64 id) const {
    const Clip* c = findClip(id);
    return c ? c->overlay.pipBorderWidth : 0.0;
}
void TimelineModel::setPipBorderWidth(qint64 id, double w) {
    editOverlay(this, id, [&](OverlayData& o) { o.pipBorderWidth = w; });
}
QString TimelineModel::pipBorderColor(qint64 id) const {
    const Clip* c = findClip(id);
    return c ? c->overlay.pipBorderColor.name(QColor::HexArgb) : QString();
}
void TimelineModel::setPipBorderColor(qint64 id, const QString& c) {
    editOverlay(this, id, [&](OverlayData& o) { o.pipBorderColor = QColor(c); });
}
double TimelineModel::pipCornerRadius(qint64 id) const {
    const Clip* c = findClip(id);
    return c ? c->overlay.pipCornerRadius : 0.0;
}
void TimelineModel::setPipCornerRadius(qint64 id, double r) {
    editOverlay(this, id, [&](OverlayData& o) { o.pipCornerRadius = r; });
}
bool TimelineModel::pipShadowEnabled(qint64 id) const {
    const Clip* c = findClip(id);
    return c ? c->overlay.pipShadowEnabled : false;
}
void TimelineModel::setPipShadowEnabled(qint64 id, bool e) {
    editOverlay(this, id, [&](OverlayData& o) { o.pipShadowEnabled = e; });
}
int TimelineModel::pipShadowBlur(qint64 id) const {
    const Clip* c = findClip(id);
    return c ? c->overlay.pipShadowBlur : 16;
}
void TimelineModel::setPipShadowBlur(qint64 id, int b) {
    editOverlay(this, id, [&](OverlayData& o) { o.pipShadowBlur = b; });
}
int TimelineModel::pipShadowOffsetX(qint64 id) const {
    const Clip* c = findClip(id);
    return c ? c->overlay.pipShadowOffsetX : 4;
}
void TimelineModel::setPipShadowOffsetX(qint64 id, int ox) {
    editOverlay(this, id, [&](OverlayData& o) { o.pipShadowOffsetX = ox; });
}
int TimelineModel::pipShadowOffsetY(qint64 id) const {
    const Clip* c = findClip(id);
    return c ? c->overlay.pipShadowOffsetY : 4;
}
void TimelineModel::setPipShadowOffsetY(qint64 id, int oy) {
    editOverlay(this, id, [&](OverlayData& o) { o.pipShadowOffsetY = oy; });
}
QString TimelineModel::pipShadowColor(qint64 id) const {
    const Clip* c = findClip(id);
    return c ? c->overlay.pipShadowColor.name(QColor::HexArgb) : QString();
}
void TimelineModel::setPipShadowColor(qint64 id, const QString& c) {
    editOverlay(this, id, [&](OverlayData& o) { o.pipShadowColor = QColor(c); });
}

// ---- Playback speed ----

double TimelineModel::playbackSpeed(qint64 id) const {
    const Clip* c = findClip(id);
    return c ? c->playbackSpeed : 1.0;
}

void TimelineModel::setPlaybackSpeed(qint64 id, double speed) {
    speed = qBound(0.25, speed, 4.0);
    Clip* c = findClip(id);
    if (!c) return;
    c->playbackSpeed = speed;
    modifyClipDirect(*c);
}

bool TimelineModel::pitchCorrection(qint64 id) const {
    const Clip* c = findClip(id);
    return c ? c->pitchCorrection : true;
}

void TimelineModel::setPitchCorrection(qint64 id, bool enabled) {
    Clip* c = findClip(id);
    if (!c) return;
    c->pitchCorrection = enabled;
    modifyClipDirect(*c);
}

// ---- Keyframes ----

double TimelineModel::overlayValueAt(qint64 id, const QString& prop, qint64 t) const {
    const Clip* c = findClip(id);
    if (!c) return 0.0;
    const auto* tr = c->overlay.kf.find(prop);
    if (tr && !tr->points.isEmpty()) return tr->valueAt(t);
    if (prop == "posX") return c->overlay.posX;
    if (prop == "posY") return c->overlay.posY;
    if (prop == "scale") return c->overlay.scale;
    if (prop == "rotation") return c->overlay.rotation;
    if (prop == "opacity") return c->overlay.opacity;
    if (prop == "cropLeft") return c->overlay.cropLeft;
    if (prop == "cropTop") return c->overlay.cropTop;
    if (prop == "cropRight") return c->overlay.cropRight;
    if (prop == "cropBottom") return c->overlay.cropBottom;
    if (prop == "pipBorderWidth") return c->overlay.pipBorderWidth;
    if (prop == "pipCornerRadius") return c->overlay.pipCornerRadius;
    return 0.0;
}

void TimelineModel::setKeyframe(qint64 id, const QString& prop, qint64 t, double value) {
    Clip* c = findClip(id);
    if (!c) return;
    c->overlay.kf.set(prop, t, value);
    modifyClipDirect(*c);
}

void TimelineModel::moveKeyframe(qint64 id, const QString& prop, qint64 oldT,
                                 qint64 newT, double value) {
    Clip* c = findClip(id);
    if (!c) return;
    c->overlay.kf.move(prop, oldT, newT, value);
    modifyClipDirect(*c);
}

void TimelineModel::removeKeyframeAt(qint64 id, const QString& prop, qint64 t) {
    Clip* c = findClip(id);
    if (!c) return;
    c->overlay.kf.removeNear(prop, t, 1);
    modifyClipDirect(*c);
}

void TimelineModel::clearKeyframes(qint64 id, const QString& prop) {
    Clip* c = findClip(id);
    if (!c) return;
    c->overlay.kf.clear(prop);
    modifyClipDirect(*c);
}

QVariantList TimelineModel::keyframes(qint64 id, const QString& prop) const {
    QVariantList out;
    const Clip* c = findClip(id);
    if (!c) return out;
    const auto* tr = c->overlay.kf.find(prop);
    if (!tr) return out;
    for (const auto& pt : tr->points) {
        QVariantList pair;
        pair.append(QVariant::fromValue(static_cast<qlonglong>(pt.first)));
        pair.append(pt.second);
        out.append(QVariant::fromValue(pair));
    }
    return out;
}

// ---- Transitions ----

void TimelineModel::addTransition(qint64 clipAId, qint64 clipBId, const QString& type,
                                   qint64 durationMs, const QVariantMap& params) {
    Clip* a = findClip(clipAId);
    Clip* b = findClip(clipBId);
    if (!a || !b) return;
    if (a->kind != ClipKind::Video || b->kind != ClipKind::Video) {
        qWarning() << "[Timeline] Transitions only between video clips";
        return;
    }
    if (b->timelineStartMs != a->timelineEndMs) {
        qWarning() << "[Timeline] Transition requires adjacent clips (B starts at A end)";
        return;
    }
    const qint64 dur = qBound(qint64(300), durationMs, qint64(1000));

    // Replace any existing transition touching either clip.
    for (int i = 0; i < transitions_.size(); ++i) {
        if (transitions_[i].clipAId == clipAId || transitions_[i].clipBId == clipBId) {
            transitions_.removeAt(i);
            break;
        }
    }
    Transition tr;
    tr.clipAId = clipAId;
    tr.clipBId = clipBId;
    tr.type = type;
    tr.durationMs = dur;
    tr.params = params;
    transitions_.append(tr);
    emit clipModified(clipAId);
    emit clipModified(clipBId);
}

void TimelineModel::removeTransition(qint64 clipAId, qint64 clipBId) {
    for (int i = 0; i < transitions_.size(); ++i) {
        if (transitions_[i].clipAId == clipAId && transitions_[i].clipBId == clipBId) {
            transitions_.removeAt(i);
            emit clipModified(clipAId);
            emit clipModified(clipBId);
            return;
        }
    }
}

QVariantMap TimelineModel::transitionBetween(qint64 clipAId, qint64 clipBId) const {
    QVariantMap m;
    for (const auto& tr : transitions_) {
        if (tr.clipAId == clipAId && tr.clipBId == clipBId) {
            m["type"] = tr.type;
            m["durationMs"] = QVariant::fromValue(static_cast<qlonglong>(tr.durationMs));
            m["params"] = tr.params;
            return m;
        }
    }
    return m;
}

QVariantList TimelineModel::transitions() const {
    QVariantList out;
    for (const auto& tr : transitions_) {
        QVariantMap m;
        m["clipAId"] = QVariant::fromValue(static_cast<qlonglong>(tr.clipAId));
        m["clipBId"] = QVariant::fromValue(static_cast<qlonglong>(tr.clipBId));
        m["type"] = tr.type;
        m["durationMs"] = QVariant::fromValue(static_cast<qlonglong>(tr.durationMs));
        m["params"] = tr.params;
        out.append(m);
    }
    return out;
}

const Transition* TimelineModel::transitionAt(qint64 t) const {
    for (const auto& tr : transitions_) {
        const Clip* a = findClip(tr.clipAId);
        if (!a) continue;
        const qint64 start = a->timelineEndMs - tr.durationMs;
        if (t >= start && t < a->timelineEndMs) return &tr;
    }
    return nullptr;
}

// ---- Internal access for commands ----

Clip* TimelineModel::findClip(int64_t id) {
    for (auto& c : clips_) {
        if (c.id == id) return &c;
    }
    return nullptr;
}

const Clip* TimelineModel::findClip(int64_t id) const {
    for (const auto& c : clips_) {
        if (c.id == id) return &c;
    }
    return nullptr;
}

void TimelineModel::insertClipDirect(const Clip& clip) {
    beginInsertRows(QModelIndex(), clips_.size(), clips_.size());
    clips_.append(clip);
    endInsertRows();
    recalcDuration();
    emit durationChanged(durationMs_);
    emit clipAdded(clip.id);
}

void TimelineModel::removeClipDirect(int64_t id) {
    for (int i = 0; i < clips_.size(); ++i) {
        if (clips_[i].id == id) {
            beginRemoveRows(QModelIndex(), i, i);
            clips_.removeAt(i);
            endRemoveRows();
            recalcDuration();
            emit durationChanged(durationMs_);
            emit clipRemoved(id);
            return;
        }
    }
}

void TimelineModel::modifyClipDirect(const Clip& clip) {
    for (int i = 0; i < clips_.size(); ++i) {
        if (clips_[i].id == clip.id) {
            clips_[i] = clip;
            QModelIndex idx = index(i);
            emit dataChanged(idx, idx);
            recalcDuration();
            emit durationChanged(durationMs_);
            emit clipModified(clip.id);
            return;
        }
    }
}

void TimelineModel::recalcDuration() {
    int64_t maxEnd = 0;
    for (const auto& c : clips_) {
        if (c.timelineEndMs > maxEnd)
            maxEnd = c.timelineEndMs;
    }
    durationMs_ = maxEnd;
}

void TimelineModel::notifyPastedClips(const QVector<Clip>& pasted) {
    QVariantList ids;
    for (const auto& c : pasted) {
        ids.append(QVariant::fromValue(static_cast<qlonglong>(c.id)));
    }
    emit clipsPasted(ids);
}

// ---- Track state ----

bool TimelineModel::isTrackVisible(int trackIndex) const {
    if (trackIndex < 0 || trackIndex >= tracks_.size()) return true;
    return tracks_[trackIndex].visible;
}

void TimelineModel::setTrackVisible(int trackIndex, bool visible) {
    if (trackIndex < 0 || trackIndex >= tracks_.size()) return;
    if (tracks_[trackIndex].visible == visible) return;
    tracks_[trackIndex].visible = visible;
    emit trackVisibilityChanged(trackIndex);
}

bool TimelineModel::isTrackLocked(int trackIndex) const {
    if (trackIndex < 0 || trackIndex >= tracks_.size()) return false;
    return tracks_[trackIndex].locked;
}

void TimelineModel::setTrackLocked(int trackIndex, bool locked) {
    if (trackIndex < 0 || trackIndex >= tracks_.size()) return;
    if (tracks_[trackIndex].locked == locked) return;
    tracks_[trackIndex].locked = locked;
    emit trackLockChanged(trackIndex);
}

bool TimelineModel::isTrackMuted(int trackIndex) const {
    if (trackIndex < 0 || trackIndex >= tracks_.size()) return false;
    return tracks_[trackIndex].muted;
}

void TimelineModel::setTrackMuted(int trackIndex, bool muted) {
    if (trackIndex < 0 || trackIndex >= tracks_.size()) return;
    if (tracks_[trackIndex].muted == muted) return;
    tracks_[trackIndex].muted = muted;
    emit trackMuteChanged(trackIndex);
}

QString TimelineModel::trackName(int trackIndex) const {
    if (trackIndex < 0 || trackIndex >= tracks_.size()) return "T" + QString::number(trackIndex);
    return tracks_[trackIndex].name;
}

// ---- Drag-and-drop from media bin ----

void TimelineModel::dropMediaFiles(const QStringList &paths, qint64 timelineStartMs, int trackIndex) {
    if (paths.isEmpty()) return;

    // Determine which track to use based on media type.
    // If trackIndex is -1, auto-select: first video track for video, first audio track for audio.
    int effectiveTrack = trackIndex;
    if (effectiveTrack < 0) {
        // Find first video track (type TrackVideo)
        for (int i = 0; i < tracks_.size(); ++i) {
            if (tracks_[i].type == TrackVideo) {
                effectiveTrack = i;
                break;
            }
        }
        if (effectiveTrack < 0) effectiveTrack = 0; // fallback
    }

    for (const QString &filePath : paths) {
        Clip clip;
        clip.id = nextId_++;
        clip.sourcePath = filePath;
        clip.trackIndex = effectiveTrack;
        clip.playbackSpeed = 1.0;
        clip.pitchCorrection = true;

        // Open decoder to get duration and stream info.
        engine::Decoder decoder;
        if (decoder.open(filePath.toStdString())) {
            qint64 dur = decoder.durationMs();
            if (dur <= 0) dur = 5000; // fallback

            bool hasVideo = decoder.hasVideo();
            bool hasAudio = decoder.hasAudio();

            if (hasVideo && hasAudio) {
                // Both: create a video clip (audio handled separately or ignored for now).
                clip.kind = ClipKind::Video;
                clip.srcInMs = 0;
                clip.srcOutMs = dur;
                clip.timelineStartMs = timelineStartMs;
                clip.timelineEndMs = timelineStartMs + dur;
                clip.color = "#3a5f8a";
                undoStack_.push(new AddClipCommand(this, clip));
                // Also create an audio clip on the first audio track, offset by playhead position.
                int audioTrack = -1;
                for (int i = 0; i < tracks_.size(); ++i) {
                    if (tracks_[i].type == TrackAudio) { audioTrack = i; break; }
                }
                if (audioTrack >= 0) {
                    Clip audioClip = clip;
                    audioClip.id = nextId_++;
                    audioClip.kind = ClipKind::Audio;
                    audioClip.trackIndex = audioTrack;
                    audioClip.color = "#8a3a5f";
                    undoStack_.push(new AddClipCommand(this, audioClip));
                }
            } else if (hasVideo) {
                clip.kind = ClipKind::Video;
                clip.srcInMs = 0;
                clip.srcOutMs = dur;
                clip.timelineStartMs = timelineStartMs;
                clip.timelineEndMs = timelineStartMs + dur;
                clip.color = "#3a5f8a";
                undoStack_.push(new AddClipCommand(this, clip));
            } else if (hasAudio) {
                clip.kind = ClipKind::Audio;
                clip.srcInMs = 0;
                clip.srcOutMs = dur;
                clip.timelineStartMs = timelineStartMs;
                clip.timelineEndMs = timelineStartMs + dur;
                clip.color = "#8a3a5f";
                undoStack_.push(new AddClipCommand(this, clip));
            } else {
                // Unknown type: treat as video.
                clip.kind = ClipKind::Video;
                clip.srcInMs = 0;
                clip.srcOutMs = dur;
                clip.timelineStartMs = timelineStartMs;
                clip.timelineEndMs = timelineStartMs + dur;
                clip.color = "#3a5f8a";
                undoStack_.push(new AddClipCommand(this, clip));
            }
        } else {
            // Could not open decoder, use default duration.
            clip.kind = ClipKind::Video;
            clip.sourcePath = filePath;
            clip.srcInMs = 0;
            clip.srcOutMs = 5000;
            clip.timelineStartMs = timelineStartMs;
            clip.timelineEndMs = timelineStartMs + 5000;
            clip.color = "#3a5f8a";
            undoStack_.push(new AddClipCommand(this, clip));
        }
    }
}

TrackType TimelineModel::trackType(int trackIndex) const {
    if (trackIndex < 0 || trackIndex >= tracks_.size()) return TrackVideo;
    return tracks_[trackIndex].type;
}

bool TimelineModel::trackHasClips(int trackIndex) const {
    for (const auto& c : clips_) {
        if (c.trackIndex == trackIndex) return true;
    }
    return false;
}

// ---- Track management ----

void TimelineModel::initDefaultTracks() {
    tracks_.clear();

    TrackInfo v1;
    v1.name = "V1";
    v1.type = TrackVideo;
    v1.visible = true;
    tracks_.append(v1);

    TrackInfo a1;
    a1.name = "A1";
    a1.type = TrackAudio;
    a1.visible = true;
    tracks_.append(a1);

    TrackInfo v2;
    v2.name = "V2";
    v2.type = TrackOverlay;
    v2.visible = true;
    tracks_.append(v2);

    emit trackCountChanged();
}

void TimelineModel::syncTrackStates(int minSize) {
    // Ensure per-track state vectors are large enough for the new track count.
    // This is called after addTrack/removeTrack to keep legacy vectors in sync
    // with the new tracks_ list (for any code that still accesses them directly).
    (void)minSize;
}

void TimelineModel::addTrack(TrackType type) {
    undoStack_.push(new AddTrackCommand(this, type));
}

void TimelineModel::addTrackDirect(TrackType type) {
    TrackInfo info;
    info.type = type;
    info.visible = true;
    info.locked = false;
    info.muted = false;

    // Auto-generate name based on type and existing count.
    int count = 0;
    QString prefix;
    switch (type) {
        case TrackVideo:
            prefix = "V";
            for (int i = 0; i < tracks_.size(); ++i) {
                if (tracks_[i].type == TrackVideo) count++;
            }
            break;
        case TrackAudio:
            prefix = "A";
            for (int i = 0; i < tracks_.size(); ++i) {
                if (tracks_[i].type == TrackAudio) count++;
            }
            break;
        case TrackOverlay:
            prefix = "O";
            for (int i = 0; i < tracks_.size(); ++i) {
                if (tracks_[i].type == TrackOverlay) count++;
            }
            break;
    }
    info.name = prefix + QString::number(count + 1);

    int insertIndex = tracks_.size(); // append at end
    beginInsertRows(QModelIndex(), insertIndex, insertIndex);
    tracks_.insert(insertIndex, info);
    endInsertRows();

    emit trackCountChanged();
    emit trackAdded(insertIndex);
}

void TimelineModel::removeTrack(int trackIndex) {
    undoStack_.push(new RemoveTrackCommand(this, trackIndex));
}

void TimelineModel::removeTrackDirect(int trackIndex) {
    if (trackIndex < 0 || trackIndex >= tracks_.size()) return;
    if (tracks_.size() <= 1) {
        qWarning() << "[Timeline] Cannot remove the last track";
        return;
    }

    // Check if track has clips that would be orphaned.
    int clipCount = 0;
    for (const auto& c : clips_) {
        if (c.trackIndex == trackIndex) clipCount++;
    }
    if (clipCount > 0) {
        qWarning() << "[Timeline] Cannot remove track" << trackIndex
                   << "which has" << clipCount << "clips. Delete clips first.";
        return;
    }

    beginRemoveRows(QModelIndex(), trackIndex, trackIndex);
    tracks_.removeAt(trackIndex);
    endRemoveRows();

    // Renumber track indices on remaining clips.
    for (auto& c : clips_) {
        if (c.trackIndex > trackIndex) {
            c.trackIndex--;
            emit clipModified(c.id);
        }
    }

    emit trackCountChanged();
    emit trackRemoved(trackIndex);
}

TimelineModel::TrackInfo TimelineModel::trackInfo(int trackIndex) const {
    if (trackIndex < 0 || trackIndex >= tracks_.size()) return TrackInfo{};
    return tracks_[trackIndex];
}

void TimelineModel::insertTrack(int index, const TrackInfo& info) {
    beginInsertRows(QModelIndex(), index, index);
    tracks_.insert(index, info);
    endInsertRows();

    // Shift clips on tracks at/after this index up by one.
    for (auto& c : clips_) {
        if (c.trackIndex >= index) {
            c.trackIndex++;
            emit clipModified(c.id);
        }
    }

    emit trackCountChanged();
    emit trackAdded(index);
}

// ---- Clip clipboard operations ----

void TimelineModel::copyClipIds(const QVariantList& clipIds) {
    copiedClips_.clear();
    for (const auto& idVar : clipIds) {
        int64_t id = idVar.toLongLong();
        const Clip* c = findClip(id);
        if (c) copiedClips_.append(*c);
    }
    qDebug() << "[Timeline] Copied" << copiedClips_.size() << "clip(s) to internal clipboard";
}

void TimelineModel::copyClips(const QVector<Clip>& clips) {
    copiedClips_ = clips;
    qDebug() << "[Timeline] Copied" << clips.size() << "clip(s) to internal clipboard";
}

void TimelineModel::pasteClipsAt(qint64 startTime) {
    if (copiedClips_.isEmpty()) {
        qWarning() << "[Timeline] Nothing in clipboard to paste";
        return;
    }

    // Calculate the minimum gap needed so pasted clips don't overlap with
    // each other or with existing clips at the target position.
    QVector<qint64> startTimes;
    for (int i = 0; i < copiedClips_.size(); ++i) {
        startTimes.append(startTime);
        startTime += copiedClips_[i].durationMs();
    }

    // Snap to avoid overlapping existing clips.
    for (int i = 0; i < startTimes.size(); ++i) {
        for (const auto& existing : clips_) {
            const qint64 exStart = existing.timelineStartMs;
            const qint64 exEnd = existing.timelineEndMs;
            const qint64 pasteStart = startTimes[i];
            const qint64 pasteEnd = pasteStart + copiedClips_[i].durationMs();

            // If the pasted clip would overlap with an existing clip,
            // push it forward.
            if (pasteStart < exEnd && pasteEnd > exStart) {
                // Push pasted clip to start right after the existing clip.
                startTimes[i] = exEnd;
                // Also shift subsequent clips.
                for (int j = i + 1; j < startTimes.size(); ++j) {
                    startTimes[j] = startTimes[j - 1] + copiedClips_[j - 1].durationMs();
                }
            }
        }
    }

    // Push pasted clips forward if they would start before 0.
    for (int i = 0; i < startTimes.size(); ++i) {
        if (startTimes[i] < 0) startTimes[i] = 0;
    }

    undoStack_.push(new PasteMultipleClipsCommand(this, copiedClips_, startTimes));
}

void TimelineModel::duplicateClip(qint64 clipId) {
    const Clip* c = findClip(clipId);
    if (!c) return;
    QVector<Clip> clips;
    clips.append(*c);
    duplicateClips(clips);
}

void TimelineModel::duplicateClips(const QVector<Clip>& clips) {
    if (clips.isEmpty()) return;

    QVector<Clip> originals;
    for (const auto& c : clips) {
        originals.append(c);
    }
    undoStack_.push(new DuplicateClipCommand(this, originals));
}

void TimelineModel::cutClip(qint64 clipId) {
    const Clip* c = findClip(clipId);
    if (!c) return;
    QVector<Clip> clips;
    clips.append(*c);
    cutClips(clips);
}

void TimelineModel::cutClips(const QVector<Clip>& clips) {
    if (clips.isEmpty()) return;

    // Store a copy for the clipboard.
    copiedClips_ = clips;

    // Delete each clip individually (each goes through its own undo command).
    for (const auto& c : clips) {
        undoStack_.push(new CutClipCommand(this, c));
    }
}

// ---- Undo History ----

QVariantList TimelineModel::undoHistory() const {
    QVariantList history;
    int count = undoStack_.count();
    // Walk backwards from the most recent action.
    for (int i = count - 1; i >= 0; --i) {
        QString text = undoStack_.text(i);
        if (text.isEmpty()) text = "Action #" + QString::number(i + 1);
        history.append(text);
    }
    return history;
}

// ---- Waveform lazy loading ----

void TimelineModel::loadWaveforms()
{
    if (!waveformRenderer_) {
        waveformRenderer_ = new WaveformRenderer(this);
    }

    // Collect unique audio source paths.
    QStringList audioPaths;
    for (const auto& c : clips_) {
        if (c.kind == ClipKind::Audio && !c.sourcePath.isEmpty()) {
            if (!audioPaths.contains(c.sourcePath)) {
                audioPaths.append(c.sourcePath);
            }
        }
    }

    if (audioPaths.isEmpty()) return;

    // Load waveforms asynchronously on a timer to avoid blocking the UI thread.
    QTimer::singleShot(0, this, [this, audioPaths]() {
        for (const QString& path : audioPaths) {
            // Count how many columns we might need based on timeline width.
            // Use a fixed generous size; the QML Canvas scales it down.
            QVector<float> env = waveformRenderer_->getOrComputeEnvelope(path, kWaveformColumns);
            if (!env.isEmpty()) {
                waveformCache_[path] = QVariant::fromValue(env);
            }
        }
        // Notify QML that all waveform data is ready.
        emit dataChanged(index(0), index(rowCount() - 1), {WaveformRole});
    });
}

} // namespace ghita::timeline
