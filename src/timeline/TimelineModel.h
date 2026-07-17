#pragma once

#include "Clip.h"

#include <QAbstractListModel>
#include <QObject>
#include <QVector>
#include <QUndoStack>
#include <QPointF>
#include <QVariantMap>
#include <QMap>

namespace ghita::engine { class MediaEngine; }
namespace ghita::timeline { class WaveformRenderer; }

namespace ghita::timeline {

// TimelineModel: core data model for the editing timeline.
//
// Exposes a flat list of clips to QML (via QAbstractListModel) and provides
// slots for all editing operations (add, remove, split, trim, move). Each
// editing operation goes through the QUndoStack so it can be undone.
//
// Tracks: managed dynamically via a QVector<TrackInfo>. Default initial tracks:
//   0 = V1 (video), 1 = A1 (audio), 2 = V2 (overlay: Text/Sticker).
//
// Track types: VIDEO (rendered as video lane), AUDIO (rendered as audio lane),
// OVERLAY (text/sticker lane). Tracks can be added/removed at runtime.
class TimelineModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(qint64 durationMs READ durationMs NOTIFY durationChanged)
    Q_PROPERTY(qint64 playheadMs READ playheadMs WRITE setPlayheadMs NOTIFY playheadChanged)
    Q_PROPERTY(int trackCount READ trackCount NOTIFY trackCountChanged)
    Q_PROPERTY(bool canUndo READ canUndo NOTIFY undoRedoChanged)
    Q_PROPERTY(bool canRedo READ canRedo NOTIFY undoRedoChanged)
    Q_PROPERTY(QString lastUndoAction READ lastUndoAction NOTIFY lastUndoActionChanged)
    Q_PROPERTY(QString lastRedoAction READ lastRedoAction NOTIFY lastRedoActionChanged)
    Q_PROPERTY(int undoStackSize READ undoStackSize NOTIFY undoStackSizeChanged)

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
        WaveformRole,  // QVector<float> envelope for audio clips
        PlaybackSpeedRole,
        PitchCorrectionRole,
    };

    // Track type: determines icon, color, and behavior.
    enum TrackType { TrackVideo, TrackAudio, TrackOverlay };
    Q_ENUM(TrackType)

    // Track info: name, type, visibility, lock, mute.
    struct TrackInfo {
        QString name;
        TrackType type = TrackVideo;
        bool visible = true;
        bool locked = false;
        bool muted = false;
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
    int trackCount() const { return tracks_.size(); }
    bool canUndo() const;
    bool canRedo() const;
    QString lastUndoAction() const;
    QString lastRedoAction() const;
    int undoStackSize() const;

    // Track management (undoable).
    Q_INVOKABLE void addTrack(TrackType type);
    Q_INVOKABLE void removeTrack(int trackIndex);
    Q_INVOKABLE TrackType trackType(int trackIndex) const;

    // Direct track manipulation (called by undo commands, bypasses undo stack).
    void addTrackDirect(TrackType type);
    void removeTrackDirect(int trackIndex);

    // Check if a track has any clips.
    Q_INVOKABLE bool trackHasClips(int trackIndex) const;

    // Track info accessor (for undo commands).
    TrackInfo trackInfo(int trackIndex) const;
    void insertTrack(int index, const TrackInfo& info);

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

    // Kind of clip at a row: 0 Video, 1 Audio, 2 Text, 3 Sticker, 4 PipVideo, 5 PipImage.
    Q_INVOKABLE int clipKind(int row) const;

    // Kind of clip by id (used by selection-driven UI panels).
    Q_INVOKABLE int kindOfClip(qint64 id) const;

    // ---- PIP clip creation ----
    Q_INVOKABLE void addPipVideoClip(const QString& sourcePath, qint64 timelineStartMs,
                                      qint64 durationMs);
    Q_INVOKABLE void addPipImageClip(const QString& sourcePath, qint64 timelineStartMs,
                                      qint64 durationMs);

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

    // ---- Clip playback speed ----
    Q_INVOKABLE double playbackSpeed(qint64 id) const;
    Q_INVOKABLE void setPlaybackSpeed(qint64 id, double speed);
    Q_INVOKABLE bool pitchCorrection(qint64 id) const;
    Q_INVOKABLE void setPitchCorrection(qint64 id, bool enabled);

    // ---- Crop accessors (fractions 0..1) ----
    Q_INVOKABLE double overlayCropLeft(qint64 id) const;
    Q_INVOKABLE void setOverlayCropLeft(qint64 id, double v);
    Q_INVOKABLE double overlayCropTop(qint64 id) const;
    Q_INVOKABLE void setOverlayCropTop(qint64 id, double v);
    Q_INVOKABLE double overlayCropRight(qint64 id) const;
    Q_INVOKABLE void setOverlayCropRight(qint64 id, double v);
    Q_INVOKABLE double overlayCropBottom(qint64 id) const;
    Q_INVOKABLE void setOverlayCropBottom(qint64 id, double v);
    Q_INVOKABLE bool overlayCropLockAspect(qint64 id) const;
    Q_INVOKABLE void setOverlayCropLockAspect(qint64 id, bool v);
    Q_INVOKABLE bool overlayCropSnapCenter(qint64 id) const;
    Q_INVOKABLE void setOverlayCropSnapCenter(qint64 id, bool v);

    // ---- PIP (Picture-in-Picture) ----
    // Quick-position presets: 0=custom, 1=top-left, 2=top-right, 3=bottom-left, 4=bottom-right
    Q_INVOKABLE void setPipPreset(qint64 id, int preset);
    Q_INVOKABLE int pipPreset(qint64 id) const;

    // PIP border / stroke
    Q_INVOKABLE double pipBorderWidth(qint64 id) const;
    Q_INVOKABLE void setPipBorderWidth(qint64 id, double w);
    Q_INVOKABLE QString pipBorderColor(qint64 id) const;
    Q_INVOKABLE void setPipBorderColor(qint64 id, const QString& c);

    // PIP corner radius
    Q_INVOKABLE double pipCornerRadius(qint64 id) const;
    Q_INVOKABLE void setPipCornerRadius(qint64 id, double r);

    // PIP shadow
    Q_INVOKABLE bool pipShadowEnabled(qint64 id) const;
    Q_INVOKABLE void setPipShadowEnabled(qint64 id, bool e);
    Q_INVOKABLE int pipShadowBlur(qint64 id) const;
    Q_INVOKABLE void setPipShadowBlur(qint64 id, int b);
    Q_INVOKABLE int pipShadowOffsetX(qint64 id) const;
    Q_INVOKABLE void setPipShadowOffsetX(qint64 id, int ox);
    Q_INVOKABLE int pipShadowOffsetY(qint64 id) const;
    Q_INVOKABLE void setPipShadowOffsetY(qint64 id, int oy);
    Q_INVOKABLE QString pipShadowColor(qint64 id) const;
    Q_INVOKABLE void setPipShadowColor(qint64 id, const QString& c);

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
                                   qint64 durationMs, const QVariantMap& params = {});
    Q_INVOKABLE void removeTransition(qint64 clipAId, qint64 clipBId);
    Q_INVOKABLE QVariantMap transitionBetween(qint64 clipAId, qint64 clipBId) const;
    Q_INVOKABLE QVariantList transitions() const;

    // Internal access for commands and the export Compositor.
    Clip* findClip(int64_t id);
    const Clip* findClip(int64_t id) const;

    // Called by PasteMultipleClipsCommand after redo to notify QML.
    void notifyPastedClips(const QVector<Clip>& pasted);

    // Direct read-only access to the full clip list (used by the timeline
    // audio mixer to enumerate audio clips).
    const QVector<ghita::timeline::Clip>& allClips() const { return clips_; }
    void insertClipDirect(const Clip& clip);
    void removeClipDirect(int64_t id);
    void modifyClipDirect(const Clip& clip);

    // ---- Waveform lazy loading ----
    // Trigger asynchronous waveform extraction for all audio clips.
    Q_INVOKABLE void loadWaveforms();

    // C++ helper for the export Compositor: returns the active transition at
    // time t (where t lies in the overlap region), or nullptr.
    const Transition* transitionAt(qint64 t) const;

    // Track state: visibility, lock, mute per track.
    // Track 0 = V1 (video), 1 = A1 (audio), 2 = V2 (overlay).
    Q_INVOKABLE bool isTrackVisible(int trackIndex) const;
    Q_INVOKABLE void setTrackVisible(int trackIndex, bool visible);
    Q_INVOKABLE bool isTrackLocked(int trackIndex) const;
    Q_INVOKABLE void setTrackLocked(int trackIndex, bool locked);
    Q_INVOKABLE bool isTrackMuted(int trackIndex) const;
    Q_INVOKABLE void setTrackMuted(int trackIndex, bool muted);

    // Track name lookups.
    Q_INVOKABLE QString trackName(int trackIndex) const;

    // Drag-and-drop from media bin: drops a list of file paths at a timeline position
    // and assigns each to the best track (video -> first video track, audio -> first audio track).
    Q_INVOKABLE void dropMediaFiles(const QStringList &paths, qint64 timelineStartMs, int trackIndex);

    // ---- Clip clipboard (internal, not system) ----
    // Stores copied clips for paste/duplicate/cut operations.
    Q_INVOKABLE void copyClipIds(const QVariantList& clipIds);
    Q_INVOKABLE void copyClips(const QVector<Clip>& clips);
    Q_INVOKABLE QVector<Clip> copiedClips() const { return copiedClips_; }
    Q_INVOKABLE bool hasCopiedClips() const { return !copiedClips_.isEmpty(); }
    Q_INVOKABLE void pasteClipsAt(qint64 startTime);
    Q_INVOKABLE void duplicateClip(qint64 clipId);
    Q_INVOKABLE void duplicateClips(const QVector<Clip>& clips);
    Q_INVOKABLE void cutClip(qint64 clipId);
    Q_INVOKABLE void cutClips(const QVector<Clip>& clips);

    // ---- Undo History ----
    // Returns a list of action descriptions from the undo stack (most recent first).
    Q_INVOKABLE QVariantList undoHistory() const;

signals:
    void durationChanged(qint64);
    void playheadChanged(qint64);
    void undoRedoChanged();
    void lastUndoActionChanged();
    void lastRedoActionChanged();
    void undoStackSizeChanged();
    void clipAdded(qint64 id);
    void clipRemoved(qint64 id);
    void clipModified(qint64 id);
    // Emitted when new clips are pasted (for visual feedback).
    void clipsPasted(const QVariantList& pastedIds);
    void trackVisibilityChanged(int trackIndex);
    void trackLockChanged(int trackIndex);
    void trackMuteChanged(int trackIndex);
    void trackCountChanged();
    void trackAdded(int index);
    void trackRemoved(int index);

private:
    QVector<Clip> clips_;
    QVector<Transition> transitions_;
    int64_t nextId_ = 1;
    int64_t playheadMs_ = 0;
    int64_t durationMs_ = 0;
    QUndoStack undoStack_;

    // Cached action text for the last undo/redo actions.
    QString lastUndoActionText_;
    QString lastRedoActionText_;

    // ---- Waveform cache ----
    // Maps source path -> QVariantList of envelope values (one per column).
    QMap<QString, QVariant> waveformCache_;
    WaveformRenderer* waveformRenderer_ = nullptr;
    // Number of pixel columns to compute per waveform.
    static constexpr int kWaveformColumns = 200;

    // ---- Dynamic track management ----
    QVector<TrackInfo> tracks_;

    // ---- Internal clipboard ----
    QVector<Clip> copiedClips_;

    // Helpers to initialize default tracks.
    void initDefaultTracks();
    void syncTrackStates(int minSize);

    void recalcDuration();

} // namespace ghita::timeline
