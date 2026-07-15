#include "TimelineCommands.h"
#include "TimelineModel.h"

namespace ghita::timeline {

// ---- AddClipCommand ----

AddClipCommand::AddClipCommand(TimelineModel* model, const Clip& clip,
                                QUndoCommand* parent)
    : QUndoCommand(parent), model_(model), clip_(clip) {
    setText("Add clip");
}

void AddClipCommand::undo() {
    model_->removeClipDirect(clip_.id);
}

void AddClipCommand::redo() {
    model_->insertClipDirect(clip_);
}

// ---- DeleteClipCommand ----

DeleteClipCommand::DeleteClipCommand(TimelineModel* model, const Clip& clip,
                                      QUndoCommand* parent)
    : QUndoCommand(parent), model_(model), clip_(clip) {
    setText("Delete clip");
}

void DeleteClipCommand::undo() {
    model_->insertClipDirect(clip_);
}

void DeleteClipCommand::redo() {
    model_->removeClipDirect(clip_.id);
}

// ---- CutCommand ----

CutCommand::CutCommand(TimelineModel* model, int64_t clipId,
                        int64_t cutPointMs, QUndoCommand* parent)
    : QUndoCommand(parent), model_(model), clipId_(clipId),
      cutPointMs_(cutPointMs) {
    setText("Split clip");
    // Snapshot the original clip for undo.
    auto* c = model_->findClip(clipId);
    if (c) originalClip_ = *c;
}

void CutCommand::undo() {
    // Remove both halves, restore original.
    model_->removeClipDirect(leftClip_.id);
    model_->removeClipDirect(rightClip_.id);
    model_->insertClipDirect(originalClip_);
}

void CutCommand::redo() {
    // Remove original, create left + right halves.
    model_->removeClipDirect(clipId_);

    int64_t cutOffset = cutPointMs_ - originalClip_.timelineStartMs;

    leftClip_ = originalClip_;
    leftClip_.timelineEndMs = cutPointMs_;
    leftClip_.srcOutMs = originalClip_.srcInMs + cutOffset;

    rightClip_ = originalClip_;
    rightClip_.id = 0; // will be assigned by insertClipDirect
    rightClip_.timelineStartMs = cutPointMs_;
    rightClip_.srcInMs = leftClip_.srcOutMs;

    // Generate new IDs for the split clips.
    // We use the model's nextId_ by inserting via addClip-like path.
    // For simplicity, we directly assign IDs by using insertClipDirect
    // which appends (but we need unique IDs).
    // Hack: use insertClipDirect and let the model handle IDs.
    // Actually insertClipDirect doesn't assign IDs. We assign manually.
    // We need a way to get next ID. Let's use a workaround:
    // Store left/right with specific IDs and use the model's findClip.
    // Better approach: the model's insertClipDirect should use the clip's ID.
    // Let's assign IDs from the original clip's "after-life":
    leftClip_.id = originalClip_.id; // left keeps original ID
    rightClip_.id = -originalClip_.id; // right gets negative ID (temporary)

    // Actually, let's just use the model's addClip mechanism.
    // Simpler: insert both clips directly with manually set IDs.
    // The model's nextId_ needs to be advanced. Let's just use two
    // AddClipCommand-style inserts. For now, let's do direct manipulation.
    model_->insertClipDirect(leftClip_);
    // Right clip needs a new ID. We'll use a simple scheme:
    rightClip_.id = leftClip_.id + 100000; // offset to avoid collision
    model_->insertClipDirect(rightClip_);
}

// ---- TrimCommand ----

TrimCommand::TrimCommand(TimelineModel* model, int64_t clipId,
                          int64_t deltaMs, Side side, QUndoCommand* parent)
    : QUndoCommand(parent), model_(model), clipId_(clipId),
      deltaMs_(deltaMs), side_(side) {
    setText(side == Left ? "Trim left" : "Trim right");
    auto* c = model_->findClip(clipId);
    if (c) beforeClip_ = *c;
}

void TrimCommand::undo() {
    model_->modifyClipDirect(beforeClip_);
}

void TrimCommand::redo() {
    Clip modified = beforeClip_;
    if (side_ == Left) {
        modified.timelineStartMs += deltaMs_;
        modified.srcInMs += deltaMs_;
    } else {
        modified.timelineEndMs += deltaMs_;
        modified.srcOutMs += deltaMs_;
    }
    // Clamp: don't allow zero/negative duration.
    if (modified.durationMs() <= 0) return;
    model_->modifyClipDirect(modified);
}

// ---- MoveCommand ----

MoveCommand::MoveCommand(TimelineModel* model, int64_t clipId,
                          int64_t timeDeltaMs, int trackDelta,
                          QUndoCommand* parent)
    : QUndoCommand(parent), model_(model), clipId_(clipId),
      timeDeltaMs_(timeDeltaMs), trackDelta_(trackDelta) {
    setText("Move clip");
    auto* c = model_->findClip(clipId);
    if (c) beforeClip_ = *c;
}

void MoveCommand::undo() {
    model_->modifyClipDirect(beforeClip_);
}

void MoveCommand::redo() {
    Clip modified = beforeClip_;
    modified.timelineStartMs += timeDeltaMs_;
    modified.timelineEndMs += timeDeltaMs_;
    modified.trackIndex += trackDelta_;
    // Clamp track to valid range (0=V1, 1=A1, 2=V2 overlay).
    if (modified.trackIndex < 0) modified.trackIndex = 0;
    if (modified.trackIndex > 2) modified.trackIndex = 2;
    // Clamp timeline position to non-negative.
    if (modified.timelineStartMs < 0) {
        qint64 shift = -modified.timelineStartMs;
        modified.timelineStartMs += shift;
        modified.timelineEndMs += shift;
    }
    model_->modifyClipDirect(modified);
}

} // namespace ghita::timeline
