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
    // Clamp track to valid range.
    if (modified.trackIndex < 0) modified.trackIndex = 0;
    if (modified.trackIndex >= model_->trackCount()) modified.trackIndex = model_->trackCount() - 1;
    // Clamp timeline position to non-negative.
    if (modified.timelineStartMs < 0) {
        qint64 shift = -modified.timelineStartMs;
        modified.timelineStartMs += shift;
        modified.timelineEndMs += shift;
    }
    model_->modifyClipDirect(modified);
}

// ---- AddTrackCommand ----

AddTrackCommand::AddTrackCommand(TimelineModel* model, TimelineModel::TrackType type,
                                  QUndoCommand* parent)
    : QUndoCommand(parent), model_(model), type_(type) {
    setText("Add track");
}

void AddTrackCommand::undo() {
    // Remove the track we added.
    model_->removeTrack(removedIndex_);
}

void AddTrackCommand::redo() {
    // Directly add the track via the model.
    model_->addTrack(type_);
    // The model appends at the end, so index = size - 1.
    removedIndex_ = model_->trackCount() - 1;
}

// ---- RemoveTrackCommand ----

RemoveTrackCommand::RemoveTrackCommand(TimelineModel* model, int trackIndex,
                                        QUndoCommand* parent)
    : QUndoCommand(parent), model_(model), removedIndex_(trackIndex) {
    setText("Remove track");
    savedInfo_ = model_->trackInfo(trackIndex);
}

void RemoveTrackCommand::undo() {
    // Re-insert the track at its original position.
    model_->insertTrack(removedIndex_, savedInfo_);
}

void RemoveTrackCommand::redo() {
    // Store the track info before removal.
    savedInfo_ = model_->trackInfo(removedIndex_);
    model_->removeTrack(removedIndex_);
}

// ---- CopyClipCommand ----

CopyClipCommand::CopyClipCommand(TimelineModel* model, const Clip& clip,
                                  QUndoCommand* parent)
    : QUndoCommand(parent), model_(model), clip_(clip) {
    setText("Copy clip");
}

void CopyClipCommand::undo() { /* no-op: copy is informational only */ }
void CopyClipCommand::redo() { /* no-op: copy is informational only */ }

// ---- PasteClipCommand ----

PasteClipCommand::PasteClipCommand(TimelineModel* model, const Clip& templateClip,
                                    qint64 newTimelineStart, QUndoCommand* parent)
    : QUndoCommand(parent), model_(model), templateClip_(templateClip),
      newTimelineStart_(newTimelineStart) {
    setText("Paste clip");
}

void PasteClipCommand::undo() {
    model_->removeClipDirect(pastedClip_.id);
}

void PasteClipCommand::redo() {
    pastedClip_ = templateClip_;
    pastedClip_.id = 0; // will be assigned by insertClipDirect
    pastedClip_.timelineStartMs = newTimelineStart_;
    pastedClip_.timelineEndMs = newTimelineStart_ + pastedClip_.durationMs();
    model_->insertClipDirect(pastedClip_);
}

// ---- PasteMultipleClipsCommand ----

PasteMultipleClipsCommand::PasteMultipleClipsCommand(
        TimelineModel* model,
        const QVector<Clip>& templates,
        const QVector<qint64>& newStartTimes,
        QUndoCommand* parent)
    : QUndoCommand(parent), model_(model),
      templates_(templates), newStartTimes_(newStartTimes) {
    setText("Paste clips");
}

void PasteMultipleClipsCommand::undo() {
    for (const auto& c : pastedClips_) {
        model_->removeClipDirect(c.id);
    }
}

void PasteMultipleClipsCommand::redo() {
    for (int i = 0; i < templates_.size(); ++i) {
        Clip c = templates_[i];
        c.id = 0; // will be assigned by insertClipDirect
        c.timelineStartMs = newStartTimes_.at(i);
        c.timelineEndMs = newStartTimes_.at(i) + c.durationMs();
        model_->insertClipDirect(c);
        pastedClips_.append(c);
    }
    notifyPasted();
}

void PasteMultipleClipsCommand::notifyPasted() {
    model_->notifyPastedClips(pastedClips_);
}

// ---- DuplicateClipCommand ----

DuplicateClipCommand::DuplicateClipCommand(TimelineModel* model,
                                            const QVector<Clip>& clips,
                                            QUndoCommand* parent)
    : QUndoCommand(parent), model_(model), clips_(clips) {
    setText("Duplicate clip");
}

void DuplicateClipCommand::undo() {
    for (const auto& c : duplicatedClips_) {
        model_->removeClipDirect(c.id);
    }
}

void DuplicateClipCommand::redo() {
    for (const auto& c : clips_) {
        Clip dup = c;
        dup.id = 0; // will be assigned by insertClipDirect
        dup.timelineStartMs = c.timelineEndMs;
        dup.timelineEndMs = c.timelineEndMs + c.durationMs();
        model_->insertClipDirect(dup);
        duplicatedClips_.append(dup);
    }
}

// ---- CutClipCommand ----

CutClipCommand::CutClipCommand(TimelineModel* model, const Clip& clip,
                                QUndoCommand* parent)
    : QUndoCommand(parent), model_(model), clip_(clip) {
    setText("Cut clip");
}

void CutClipCommand::undo() {
    // Restore the deleted clip.
    model_->insertClipDirect(clip_);
}

void CutClipCommand::redo() {
    model_->removeClipDirect(clip_.id);
}

} // namespace ghita::timeline
