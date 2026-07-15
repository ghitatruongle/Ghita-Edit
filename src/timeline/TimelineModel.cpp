#include "TimelineModel.h"
#include "TimelineCommands.h"

#include <QColor>
#include <QDebug>
#include <QFileInfo>
#include <algorithm>
#include <functional>

namespace ghita::timeline {

TimelineModel::TimelineModel(QObject* parent)
    : QAbstractListModel(parent) {
    connect(&undoStack_, &QUndoStack::indexChanged,
            this, &TimelineModel::undoRedoChanged);
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
            return QFileInfo(c.sourcePath).fileName();
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
                                   qint64 durationMs) {
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

} // namespace ghita::timeline
