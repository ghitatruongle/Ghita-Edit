#pragma once

#include "Clip.h"
#include "TimelineModel.h"

#include <QUndoCommand>

namespace ghita::timeline {

class TimelineModel;

// ---- AddClipCommand ----
class AddClipCommand : public QUndoCommand {
public:
    AddClipCommand(TimelineModel* model, const Clip& clip, QUndoCommand* parent = nullptr);
    void undo() override;
    void redo() override;
private:
    TimelineModel* model_;
    Clip clip_;
};

// ---- DeleteClipCommand ----
class DeleteClipCommand : public QUndoCommand {
public:
    DeleteClipCommand(TimelineModel* model, const Clip& clip, QUndoCommand* parent = nullptr);
    void undo() override;
    void redo() override;
private:
    TimelineModel* model_;
    Clip clip_;
};

// ---- CutCommand: splits one clip into two at a time point ----
class CutCommand : public QUndoCommand {
public:
    CutCommand(TimelineModel* model, int64_t clipId, int64_t cutPointMs,
               QUndoCommand* parent = nullptr);
    void undo() override;
    void redo() override;
private:
    TimelineModel* model_;
    int64_t clipId_;
    int64_t cutPointMs_;
    Clip originalClip_;   // restored on undo
    Clip leftClip_;       // created on redo
    Clip rightClip_;      // created on redo
};

// ---- TrimCommand: adjusts clip in or out point ----
class TrimCommand : public QUndoCommand {
public:
    enum Side { Left, Right };
    TrimCommand(TimelineModel* model, int64_t clipId, int64_t deltaMs,
                Side side, QUndoCommand* parent = nullptr);
    void undo() override;
    void redo() override;
private:
    TimelineModel* model_;
    int64_t clipId_;
    int64_t deltaMs_;
    Side side_;
    Clip beforeClip_;
};

// ---- MoveCommand: moves clip in time and/or track ----
class MoveCommand : public QUndoCommand {
public:
    MoveCommand(TimelineModel* model, int64_t clipId,
                int64_t timeDeltaMs, int trackDelta,
                QUndoCommand* parent = nullptr);
    void undo() override;
    void redo() override;
private:
    TimelineModel* model_;
    int64_t clipId_;
    int64_t timeDeltaMs_;
    int trackDelta_;
    Clip beforeClip_;
};

// ---- AddTrackCommand: adds a track at the end ----
class AddTrackCommand : public QUndoCommand {
public:
    AddTrackCommand(TimelineModel* model, TimelineModel::TrackType type,
                    QUndoCommand* parent = nullptr);
    void undo() override;
    void redo() override;
private:
    TimelineModel* model_;
    TimelineModel::TrackType type_;
    int insertedIndex_;
    TimelineModel::TrackInfo savedInfo_;
};

// ---- RemoveTrackCommand: removes a track at a given index ----
class RemoveTrackCommand : public QUndoCommand {
public:
    RemoveTrackCommand(TimelineModel* model, int trackIndex,
                       QUndoCommand* parent = nullptr);
    void undo() override;
    void redo() override;
private:
    TimelineModel* model_;
    int removedIndex_;
    TimelineModel::TrackInfo savedInfo_;
};

// ---- CopyClipCommand: copies a clip to the internal clipboard ----
class CopyClipCommand : public QUndoCommand {
public:
    CopyClipCommand(TimelineModel* model, const Clip& clip, QUndoCommand* parent = nullptr);
    void undo() override { /* copy is a no-op on undo */ }
    void redo() override { /* copy is a no-op on redo */ }
private:
    TimelineModel* model_;
    Clip clip_;
};

// ---- PasteClipCommand: pastes a previously copied clip at a new position ----
class PasteClipCommand : public QUndoCommand {
public:
    PasteClipCommand(TimelineModel* model, const Clip& templateClip,
                     qint64 newTimelineStart, QUndoCommand* parent = nullptr);
    void undo() override;
    void redo() override;
private:
    TimelineModel* model_;
    Clip templateClip_;
    qint64 newTimelineStart_;
    Clip pastedClip_;
};

// ---- PasteMultipleClipsCommand: pastes multiple copied clips at shifted positions ----
class PasteMultipleClipsCommand : public QUndoCommand {
public:
    PasteMultipleClipsCommand(TimelineModel* model,
                              const QVector<Clip>& templates,
                              const QVector<qint64>& newStartTimes,
                              QUndoCommand* parent = nullptr);
    void undo() override;
    void redo() override;
private:
    TimelineModel* model_;
    QVector<Clip> templates_;
    QVector<qint64> newStartTimes_;
    QVector<Clip> pastedClips_;
    void notifyPasted();
};

// ---- DuplicateClipCommand: copies and pastes clips in one action ----
class DuplicateClipCommand : public QUndoCommand {
public:
    DuplicateClipCommand(TimelineModel* model,
                         const QVector<Clip>& clips,
                         QUndoCommand* parent = nullptr);
    void undo() override;
    void redo() override;
private:
    TimelineModel* model_;
    QVector<Clip> clips_;
    QVector<Clip> duplicatedClips_;
};

// ---- CutClipCommand: copies a clip to clipboard and deletes it ----
class CutClipCommand : public QUndoCommand {
public:
    CutClipCommand(TimelineModel* model, const Clip& clip, QUndoCommand* parent = nullptr);
    void undo() override;
    void redo() override;
private:
    TimelineModel* model_;
    Clip clip_;
};

} // namespace ghita::timeline
