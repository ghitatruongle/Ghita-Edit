import 'package:flutter/foundation.dart';
import '../models/clip.dart';
import '../models/track.dart';
import '../models/project.dart';

/// Abstract command for undo/redo operations.
abstract class EditCommand {
  String get description;
  void execute(Project project);
  void undo(Project project);
}

/// Command: Add a clip to a track.
class AddClipCommand extends EditCommand {
  final String trackId;
  final Clip clip;
  final int positionMs;

  AddClipCommand({required this.trackId, required this.clip, required this.positionMs});

  @override
  String get description => 'Add clip "${clip.displayName}"';

  @override
  void execute(Project project) {
    final track = project.tracks.firstWhere((t) => t.id == trackId);
    track.addClipAt(clip, positionMs);
  }

  @override
  void undo(Project project) {
    final track = project.tracks.firstWhere((t) => t.id == trackId);
    track.removeClip(clip.id);
  }
}

/// Command: Delete a clip from a track.
class DeleteClipCommand extends EditCommand {
  final String trackId;
  final Clip clip;
  late int _originalPosition;

  DeleteClipCommand({required this.trackId, required this.clip});

  @override
  String get description => 'Delete clip "${clip.displayName}"';

  @override
  void execute(Project project) {
    _originalPosition = clip.timelineStartMs;
    final track = project.tracks.firstWhere((t) => t.id == trackId);
    track.removeClip(clip.id);
  }

  @override
  void undo(Project project) {
    final track = project.tracks.firstWhere((t) => t.id == trackId);
    track.addClipAt(clip, _originalPosition);
  }
}

/// Command: Split a clip at the playhead.
class SplitClipCommand extends EditCommand {
  final String trackId;
  final String clipId;
  final int positionMs;
  late Clip _originalClip;

  SplitClipCommand({required this.trackId, required this.clipId, required this.positionMs});

  @override
  String get description => 'Split clip at ${positionMs}ms';

  @override
  void execute(Project project) {
    final track = project.tracks.firstWhere((t) => t.id == trackId);
    final clip = track.clips.firstWhere((c) => c.id == clipId);
    _originalClip = clip.copyWith();
    track.splitClipAt(positionMs);
  }

  @override
  void undo(Project project) {
    final track = project.tracks.firstWhere((t) => t.id == trackId);
    // Remove the split parts and restore original
    track.clips.removeWhere((c) => c.id == '${clipId}_L' || c.id == '${clipId}_R');
    track.clips.add(_originalClip);
    track.clips.sort((a, b) => a.timelineStartMs.compareTo(b.timelineStartMs));
  }
}

/// Command: Move a clip to a new position.
class MoveClipCommand extends EditCommand {
  final String trackId;
  final String clipId;
  final int newStartMs;
  final int? explicitOldStartMs;
  late int _oldStartMs;

  MoveClipCommand({required this.trackId, required this.clipId, required this.newStartMs, this.explicitOldStartMs});

  @override
  String get description => 'Move clip to ${newStartMs}ms';

  @override
  void execute(Project project) {
    final track = project.tracks.firstWhere((t) => t.id == trackId);
    final idx = track.clips.indexWhere((c) => c.id == clipId);
    if (idx == -1) return;
    _oldStartMs = explicitOldStartMs ?? track.clips[idx].timelineStartMs;
    track.moveClip(clipId, newStartMs);
  }

  @override
  void undo(Project project) {
    final track = project.tracks.firstWhere((t) => t.id == trackId);
    track.moveClip(clipId, _oldStartMs);
  }
}

/// Command: Change clip filter.
class ChangeFilterCommand extends EditCommand {
  final String clipId;
  final int newFilterType;
  final double newIntensity;
  late int _oldFilterType;
  late double _oldIntensity;

  ChangeFilterCommand({required this.clipId, required this.newFilterType, required this.newIntensity});

  @override
  String get description => 'Change filter to type $newFilterType';

  @override
  void execute(Project project) {
    final clip = project.allClips.firstWhere((c) => c.id == clipId);
    _oldFilterType = clip.filterType;
    _oldIntensity = clip.filterIntensity;
    clip.filterType = newFilterType;
    clip.filterIntensity = newIntensity;
  }

  @override
  void undo(Project project) {
    final clip = project.allClips.firstWhere((c) => c.id == clipId);
    clip.filterType = _oldFilterType;
    clip.filterIntensity = _oldIntensity;
  }
}

/// Command: Trim clip (start or end).
class TrimClipCommand extends EditCommand {
  final String trackId;
  final String clipId;
  final bool trimStart;
  final int newBoundaryMs;
  late int _oldStartMs;
  late int _oldDurationMs;
  late int _oldSourceInMs;
  late int _oldSourceOutMs;

  TrimClipCommand({
    required this.trackId,
    required this.clipId,
    required this.trimStart,
    required this.newBoundaryMs,
  });

  @override
  String get description => trimStart ? 'Trim clip start' : 'Trim clip end';

  @override
  void execute(Project project) {
    final track = project.tracks.firstWhere((t) => t.id == trackId);
    final clip = track.clips.firstWhere((c) => c.id == clipId);
    _oldStartMs = clip.timelineStartMs;
    _oldDurationMs = clip.durationMs;
    _oldSourceInMs = clip.sourceInMs;
    _oldSourceOutMs = clip.sourceOutMs;

    if (trimStart) {
      track.trimClipStart(clipId, newBoundaryMs);
    } else {
      track.trimClipEnd(clipId, newBoundaryMs);
    }
  }

  @override
  void undo(Project project) {
    final track = project.tracks.firstWhere((t) => t.id == trackId);
    final clip = track.clips.firstWhere((c) => c.id == clipId);
    clip.timelineStartMs = _oldStartMs;
    clip.durationMs = _oldDurationMs;
    clip.sourceInMs = _oldSourceInMs;
    clip.sourceOutMs = _oldSourceOutMs;
  }
}

/// Command: Add a track dynamically (v0.3.5).
class AddTrackCommand extends EditCommand {
  final Track track;

  AddTrackCommand({required this.track});

  @override
  String get description => 'Add track "${track.name}"';

  @override
  void execute(Project project) {
    project.addTrack(track);
  }

  @override
  void undo(Project project) {
    project.removeTrack(track.id);
  }
}

/// Command: Remove a track dynamically (v0.3.5).
class RemoveTrackCommand extends EditCommand {
  final Track track;
  late int _originalIndex;

  RemoveTrackCommand({required this.track});

  @override
  String get description => 'Remove track "${track.name}"';

  @override
  void execute(Project project) {
    _originalIndex = project.tracks.indexWhere((t) => t.id == track.id);
    project.removeTrack(track.id);
  }

  @override
  void undo(Project project) {
    if (_originalIndex >= 0 && _originalIndex <= project.tracks.length) {
      project.tracks.insert(_originalIndex, track);
      project.markModified();
    } else {
      project.addTrack(track);
    }
  }
}

/// Manages undo/redo history with a fixed capacity.
class CommandHistory extends ChangeNotifier {
  final List<EditCommand> _undoStack = [];
  final List<EditCommand> _redoStack = [];
  final int maxHistory;

  CommandHistory({this.maxHistory = 100});

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  String? get lastUndoDescription => canUndo ? _undoStack.last.description : null;
  String? get lastRedoDescription => canRedo ? _redoStack.last.description : null;

  int get undoCount => _undoStack.length;
  int get redoCount => _redoStack.length;

  /// Execute a command and push it to the undo stack.
  void execute(EditCommand command, Project project) {
    command.execute(project);
    _undoStack.add(command);
    _redoStack.clear(); // New action invalidates redo history

    if (_undoStack.length > maxHistory) {
      _undoStack.removeAt(0);
    }

    project.markModified();
    notifyListeners();
  }

  /// Undo the last command.
  bool undo(Project project) {
    if (!canUndo) return false;
    final command = _undoStack.removeLast();
    command.undo(project);
    _redoStack.add(command);
    project.markModified();
    notifyListeners();
    return true;
  }

  /// Redo the last undone command.
  bool redo(Project project) {
    if (!canRedo) return false;
    final command = _redoStack.removeLast();
    command.execute(project);
    _undoStack.add(command);
    project.markModified();
    notifyListeners();
    return true;
  }

  /// Clear all history.
  void clear() {
    _undoStack.clear();
    _redoStack.clear();
    notifyListeners();
  }
}
