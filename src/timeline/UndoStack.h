#pragma once

// UndoStack: header-only note.
// TimelineModel uses QUndoStack directly (Qt provides it as a QObject).
// This header is kept as a placeholder for future standalone use.

namespace ghita::timeline {
// intentionally empty — TimelineModel owns QUndoStack directly.
} // namespace ghita::timeline
