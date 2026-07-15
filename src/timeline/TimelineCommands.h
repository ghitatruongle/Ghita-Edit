#pragma once

#include "Clip.h"
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

} // namespace ghita::timeline
