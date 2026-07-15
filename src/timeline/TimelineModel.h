#pragma once

#include "Clip.h"

#include <QAbstractListModel>
#include <QObject>
#include <QVector>
#include <QUndoStack>
#include <QPointF>
#include <QVariantMap>

namespace ghita::engine { class MediaEngine; }

namespace ghita::timeline {

// TimelineModel: core data model for the editing timeline.
//
// Exposes a flat list of clips to QML (via QAbstractListModel) and provides
// slots for all editing operations (add, remove, split, trim, move). Each
// editing operation goes through the QUndoStack so it can be undone.
//
// Tracks: 0 = V1 (video), 1 = A1 (audio), 2 = V2 (overlay: Text/Sticker).
class TimelineModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(qint64 durationMs READ durationMs NOTIFY durationChanged)
    Q_PROPERTY(qint64 playheadMs READ playheadMs WRITE setPlayheadMs NOTIFY playheadChanged)
    Q_PROPERTY(int trackCount READ trackCount CONSTANT)
    Q_PROPERTY(bool canUndo READ canUndo NOTIFY undoRedoChanged)
    Q_PROPERTY(bool canRedo READ canRedo NOTIFY undoRedoChanged)

public:
    // Roles for QML delegates.
    enum Roles {
        IdRole = Qt::UserRole + 1,
        SourcePathRole,
        TimelineStartRole,
        TimelineEndRole,
        SrcInRole,
        SrcOutRole,
        TrackIndexRole,
        ColorRole,
        DurationRole,
        KindRole,
        OverlayLabelRole,
    };

    explicit TimelineModel(QObject* parent = nullptr);

    // QAbstractListModel interface.
    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    // Properties.
    qint64 durationMs() const;
    qint64 playheadMs() const { return playheadMs_; }
    void setPlayheadMs(qint64 ms);
    int trackCount() const { return 3; } // V1 + A1 + V2 (overlay)
    bool canUndo() const;
    bool canRedo() const;

    // Editing operations (go through undo stack).
    Q_INVOKABLE void addClip(const QString& sourcePath, qint64 srcInMs,
                             qint64 srcOutMs, qint64 timelineStartMs,
                             int trackIndex);
    Q_INVOKABLE void splitClipAtPlayhead(qint64 clipId);
    Q_INVOKABLE void trimClipLeft(qint64 clipId, qint64 newTimelineStartMs);
    Q_INVOKABLE void trimClipRight(qint64 clipId, qint64 newTimelineEndMs);
    Q_INVOKABLE void moveClip(qint64 clipId, qint64 newTimelineStartMs, int newTrackIndex);
    Q_INVOKABLE void deleteClip(qint64 clipId);
    Q_INVOKABLE void undo();
    Q_INVOKABLE void redo();

    // Snap support: returns a list of snap target positions (clip edges + playhead).
    Q_INVOKABLE QVariantList snapTargets() const;

    // Typed accessors for QML so shortcuts don't need fragile role numbers.
    Q_INVOKABLE qint64 clipId(int row) const;
    Q_INVOKABLE qint64 clipStartMs(int row) const;
    Q_INVOKABLE qint64 clipEndMs(int row) const;

    // ---- Overlay clips (Text / Sticker) on V2 ----
    Q_INVOKABLE void addTextClip(qint64 timelineStartMs, qint64 durationMs);
    Q_INVOKABLE void addTextClip(const QString& text, qint64 timelineStartMs, qint64 durationMs);
    Q_INVOKABLE void addStickerClip(const QString& stickerPath, qint64 timelineStartMs,
                                    qint64 durationMs);

    // Kind of clip at a row: 0 Video, 1 Audio, 2 Text, 3 Sticker.
    Q_INVOKABLE int clipKind(int row) const;

    // Kind of clip by id (used by selection-driven UI panels).
    Q_INVOKABLE int kindOfClip(qint64 id) const;

    // Overlay property accessors (by clip id). Used by the Text/Sticker panels.
    Q_INVOKABLE QString overlayText(qint64 id) const;
    Q_INVOKABLE void setOverlayText(qint64 id, const QString&);
    Q_INVOKABLE double overlayFontSize(qint64 id) const;
    Q_INVOKABLE void setOverlayFontSize(qint64 id, double);
    Q_INVOKABLE bool overlayBold(qint64 id) const;
    Q_INVOKABLE void setOverlayBold(qint64 id, bool);
    Q_INVOKABLE QString overlayColor(qint64 id) const;
    Q_INVOKABLE void setOverlayColor(qint64 id, const QString&);
    Q_INVOKABLE int overlayAlign(qint64 id) const;
    Q_INVOKABLE void setOverlayAlign(qint64 id, int);
    Q_INVOKABLE QString overlayBg(qint64 id) const;
    Q_INVOKABLE void setOverlayBg(qint64 id, const QString&);
    Q_INVOKABLE QString overlaySticker(qint64 id) const;
    Q_INVOKABLE void setOverlaySticker(qint64 id, const QString&);

    // Transform accessors (normalized 0..1, degrees, 0..1 opacity).
    Q_INVOKABLE void setOverlayPos(qint64 id, double x, double y);
    Q_INVOKABLE QPointF overlayPos(qint64 id) const;
    Q_INVOKABLE void setOverlayScale(qint64 id, double);
    Q_INVOKABLE double overlayScale(qint64 id) const;
    Q_INVOKABLE void setOverlayRotation(qint64 id, double);
    Q_INVOKABLE double overlayRotation(qint64 id) const;
    Q_INVOKABLE void setOverlayOpacity(qint64 id, double);
    Q_INVOKABLE double overlayOpacity(qint64 id) const;

    // Keyframes: interpolated value at time t (falls back to base overlay value).
    Q_INVOKABLE double overlayValueAt(qint64 id, const QString& prop, qint64 t) const;
    Q_INVOKABLE void setKeyframe(qint64 id, const QString& prop, qint64 t, double value);
    Q_INVOKABLE void moveKeyframe(qint64 id, const QString& prop, qint64 oldT,
                                 qint64 newT, double value);
    Q_INVOKABLE void removeKeyframeAt(qint64 id, const QString& prop, qint64 t);
    Q_INVOKABLE void clearKeyframes(qint64 id, const QString& prop);
    Q_INVOKABLE QVariantList keyframes(qint64 id, const QString& prop) const;

    // Transitions between adjacent video clips.
    Q_INVOKABLE void addTransition(qint64 clipAId, qint64 clipBId, const QString& type,
                                   qint64 durationMs);
    Q_INVOKABLE void removeTransition(qint64 clipAId, qint64 clipBId);
    Q_INVOKABLE QVariantMap transitionBetween(qint64 clipAId, qint64 clipBId) const;
    Q_INVOKABLE QVariantList transitions() const;

    // Internal access for commands and the export Compositor.
    Clip* findClip(int64_t id);
    const Clip* findClip(int64_t id) const;
    void insertClipDirect(const Clip& clip);
    void removeClipDirect(int64_t id);
    void modifyClipDirect(const Clip& clip);

    // C++ helper for the export Compositor: returns the active transition at
    // time t (where t lies in the overlap region), or nullptr.
    const Transition* transitionAt(qint64 t) const;

signals:
    void durationChanged(qint64);
    void playheadChanged(qint64);
    void undoRedoChanged();
    void clipAdded(qint64 id);
    void clipRemoved(qint64 id);
    void clipModified(qint64 id);

protected:
    void recalcDuration();

private:
    QVector<Clip> clips_;
    QVector<Transition> transitions_;
    int64_t nextId_ = 1;
    int64_t playheadMs_ = 0;
    int64_t durationMs_ = 0;
    QUndoStack undoStack_;
};

} // namespace ghita::timeline
