import 'package:flutter/foundation.dart';
import '../models/clip.dart';
import '../models/track.dart';
import '../models/project.dart';

/// Abstract command for undo/redo operations.
abstract class EditCommand {
  String get description;

  /// v0.7.8: When non-null, a new command with the same key replaces the
  /// previous one in the undo stack instead of pushing (one undo entry per
  /// gesture — used by slider drags).
  String? get coalesceKey => null;

  /// v0.7.8: Called when this command replaces an earlier one with the same
  /// [coalesceKey] — copy the earlier command's captured undo state so undo
  /// restores the value from before the gesture started.
  void inheritUndoState(EditCommand old) {}

  void execute(Project project);
  void undo(Project project);
}

/// Command: Add a clip to a track.
class AddClipCommand extends EditCommand {
  final String trackId;
  final Clip clip;
  final int positionMs;
  // v0.7.8: Original positions of clips shifted away by overlap resolution —
  // undo restores them (previously they stayed shifted forever, desyncing
  // the undo stack from the real timeline state).
  final Map<String, int> _shiftedOrigins = {};

  AddClipCommand({required this.trackId, required this.clip, required this.positionMs});

  @override
  String get description => 'Add clip "${clip.displayName}"';

  @override
  void execute(Project project) {
    final track = project.tracks.where((t) => t.id == trackId).firstOrNull;
    if (track == null) return;
    // v0.7.9: Deep-review — on redo this runs again; without clearing, stale
    // entries from the first execution (clips since deleted/moved) would be
    // captured at their CURRENT positions and undo would restore wrong values.
    _shiftedOrigins.clear();
    for (final existing in track.clips) {
      if (existing.id != clip.id &&
          existing.timelineStartMs < clip.timelineEndMs &&
          existing.timelineEndMs > clip.timelineStartMs) {
        _shiftedOrigins[existing.id] = existing.timelineStartMs;
      }
    }
    track.addClipAt(clip, positionMs);
  }

  @override
  void undo(Project project) {
    final track = project.tracks.where((t) => t.id == trackId).firstOrNull;
    if (track == null) return;
    track.removeClip(clip.id);
    for (final entry in _shiftedOrigins.entries) {
      final shifted = track.clips.where((c) => c.id == entry.key).firstOrNull;
      if (shifted != null) {
        shifted.timelineStartMs = entry.value;
      }
    }
    track.clips.sort((a, b) => a.timelineStartMs.compareTo(b.timelineStartMs));
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
    final track = project.tracks.where((t) => t.id == trackId).firstOrNull;
    track?.removeClip(clip.id);
  }

  @override
  void undo(Project project) {
    final track = project.tracks.where((t) => t.id == trackId).firstOrNull;
    track?.addClipAt(clip, _originalPosition);
  }
}

/// Command: Split a clip at the playhead.
class SplitClipCommand extends EditCommand {
  final String trackId;
  final String clipId;
  final int positionMs;
  late Clip _originalClip;
  // v0.7.8: Set only when the split actually happened — guards against
  // undoing a no-op split (which used to duplicate the clip on the track).
  bool _didSplit = false;

  SplitClipCommand({required this.trackId, required this.clipId, required this.positionMs});

  @override
  String get description => 'Split clip at ${positionMs}ms';

  @override
  void execute(Project project) {
    final track = project.tracks.where((t) => t.id == trackId).firstOrNull;
    if (track == null) return;
    final clip = track.clips.where((c) => c.id == clipId).firstOrNull;
    if (clip == null) return;
    _originalClip = clip.copyWith();
    _didSplit = track.splitClipAt(positionMs);
  }

  @override
  void undo(Project project) {
    if (!_didSplit) return;
    final track = project.tracks.where((t) => t.id == trackId).firstOrNull;
    if (track == null) return;
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
    final track = project.tracks.where((t) => t.id == trackId).firstOrNull;
    if (track == null) return;
    final idx = track.clips.indexWhere((c) => c.id == clipId);
    if (idx == -1) return;
    _oldStartMs = explicitOldStartMs ?? track.clips[idx].timelineStartMs;
    track.moveClip(clipId, newStartMs);
  }

  @override
  void undo(Project project) {
    final track = project.tracks.where((t) => t.id == trackId).firstOrNull;
    track?.moveClip(clipId, _oldStartMs);
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
    final clip = project.allClips.where((c) => c.id == clipId).firstOrNull;
    if (clip == null) return;
    _oldFilterType = clip.filterType;
    _oldIntensity = clip.filterIntensity;
    clip.filterType = newFilterType;
    clip.filterIntensity = newIntensity;
  }

  @override
  void undo(Project project) {
    final clip = project.allClips.where((c) => c.id == clipId).firstOrNull;
    if (clip == null) return;
    clip.filterType = _oldFilterType;
    clip.filterIntensity = _oldIntensity;
  }
}

/// Command: Apply one filter to many clips at once (v1.1.0).
/// The inspector multi-select "Apply Filter" used to mutate every clip
/// directly — not undoable and never mirrored to the engine. One command
/// snapshots the whole batch so a single Ctrl+Z restores every clip, and the
/// command-history listener triggers the engine timeline resync.
class ChangeMultiClipFilterCommand extends EditCommand {
  final List<String> clipIds;
  final int newFilterType;
  final double newIntensity;
  final Map<String, int> _oldTypes = {};
  final Map<String, double> _oldIntensities = {};

  ChangeMultiClipFilterCommand({
    required this.clipIds,
    required this.newFilterType,
    required this.newIntensity,
  });

  @override
  String get description => 'Apply filter to ${clipIds.length} clips';

  @override
  void execute(Project project) {
    // v1.1.0: Clear captured state on every execute (redo) — stale entries
    // from a previous run would restore wrong values (same pattern as
    // AddClipCommand._shiftedOrigins).
    _oldTypes.clear();
    _oldIntensities.clear();
    for (final clip in project.allClips) {
      if (!clipIds.contains(clip.id)) continue;
      _oldTypes[clip.id] = clip.filterType;
      _oldIntensities[clip.id] = clip.filterIntensity;
      clip.filterType = newFilterType;
      clip.filterIntensity = newIntensity;
    }
  }

  @override
  void undo(Project project) {
    for (final clip in project.allClips) {
      if (!clipIds.contains(clip.id)) continue;
      clip.filterType = _oldTypes[clip.id] ?? 0;
      clip.filterIntensity = _oldIntensities[clip.id] ?? 1.0;
    }
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
    final track = project.tracks.where((t) => t.id == trackId).firstOrNull;
    if (track == null) return;
    final clip = track.clips.where((c) => c.id == clipId).firstOrNull;
    if (clip == null) return;
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
    final track = project.tracks.where((t) => t.id == trackId).firstOrNull;
    if (track == null) return;
    final clip = track.clips.where((c) => c.id == clipId).firstOrNull;
    if (clip == null) return;
    clip.timelineStartMs = _oldStartMs;
    clip.durationMs = _oldDurationMs;
    clip.sourceInMs = _oldSourceInMs;
    clip.sourceOutMs = _oldSourceOutMs;
  }
}

/// Command: Change a scalar clip property (speed/opacity/volume) with undo.
/// v0.7.8: Inspector sliders go through this instead of mutating clips directly.
class ChangeClipPropertyCommand extends EditCommand {
  final String clipId;
  final String property; // 'speed' | 'opacity' | 'volume'
  final double newValue;
  // v0.7.8: Distinguishes separate drag gestures — without it, two consecutive
  // slider drags merged into one undo entry (undo jumped back past both).
  final int? gestureId;
  late double _oldValue;

  ChangeClipPropertyCommand({
    required this.clipId,
    required this.property,
    required this.newValue,
    this.gestureId,
  });

  /// One undo entry per drag gesture (slider drags fire many onChange ticks).
  @override
  String? get coalesceKey => 'clip-property:$clipId:$property:$gestureId';

  @override
  String get description => 'Change clip $property to $newValue';

  @override
  void inheritUndoState(EditCommand old) {
    if (old is ChangeClipPropertyCommand) {
      _oldValue = old._oldValue;
    }
  }

  double _read(Clip clip) {
    switch (property) {
      case 'speed':
        return clip.speed;
      case 'opacity':
        return clip.opacity;
      case 'volume':
        return clip.volume;
      default:
        throw ArgumentError('Unknown clip property: $property');
    }
  }

  void _write(Clip clip, double value) {
    switch (property) {
      case 'speed':
        clip.speed = value;
        break;
      case 'opacity':
        clip.opacity = value;
        break;
      case 'volume':
        clip.volume = value;
        break;
      default:
        throw ArgumentError('Unknown clip property: $property');
    }
  }

  @override
  void execute(Project project) {
    final clip = project.allClips.where((c) => c.id == clipId).firstOrNull;
    if (clip == null) return;
    _oldValue = _read(clip);
    _write(clip, newValue);
  }

  @override
  void undo(Project project) {
    final clip = project.allClips.where((c) => c.id == clipId).firstOrNull;
    if (clip == null) return;
    _write(clip, _oldValue);
  }
}

/// Command: Change a clip's transition (type + duration) with undo.
/// v0.7.8: Inspector transition dropdown now goes through this — previously
/// the change was applied outside the command history (not undoable).
class ChangeClipTransitionCommand extends EditCommand {
  final String clipId;
  final int newType;
  final int newDurationMs;
  late int _oldType;
  late int _oldDurationMs;
  bool _applied = false;

  ChangeClipTransitionCommand({
    required this.clipId,
    required this.newType,
    required this.newDurationMs,
  });

  @override
  String get description => 'Set transition to type $newType';

  @override
  void execute(Project project) {
    final clip = project.allClips.where((c) => c.id == clipId).firstOrNull;
    if (clip == null) return;
    _oldType = clip.transitionType;
    _oldDurationMs = clip.transitionDurationMs;
    clip.transitionType = newType;
    clip.transitionDurationMs = newDurationMs;
    _applied = true;
  }

  @override
  void undo(Project project) {
    if (!_applied) return;
    final clip = project.allClips.where((c) => c.id == clipId).firstOrNull;
    if (clip == null) return;
    clip.transitionType = _oldType;
    clip.transitionDurationMs = _oldDurationMs;
  }
}

/// Command: Change a clip's color correction (all 8 fields) with undo.
/// v1.0.0: Previously `EditorController.setClipColorCorrection` mutated the
/// clip directly, bypassing the command history — color edits were NOT
/// undoable. This command routes them through the undo stack with one entry
/// per drag gesture (sliders fire many onChange ticks).
class ChangeClipColorCorrectionCommand extends EditCommand {
  final String clipId;
  final double newExposure;
  final double newContrast;
  final double newHighlights;
  final double newShadows;
  final double newTemperature;
  final double newTint;
  final double newVibrance;
  final double newSaturation;
  final int? gestureId;

  late double _oldExposure;
  late double _oldContrast;
  late double _oldHighlights;
  late double _oldShadows;
  late double _oldTemperature;
  late double _oldTint;
  late double _oldVibrance;
  late double _oldSaturation;

  ChangeClipColorCorrectionCommand({
    required this.clipId,
    required this.newExposure,
    required this.newContrast,
    required this.newHighlights,
    required this.newShadows,
    required this.newTemperature,
    required this.newTint,
    required this.newVibrance,
    required this.newSaturation,
    this.gestureId,
  });

  @override
  String? get coalesceKey => 'clip-color:$clipId:$gestureId';

  @override
  String get description => 'Adjust color correction';

  @override
  void inheritUndoState(EditCommand old) {
    if (old is ChangeClipColorCorrectionCommand) {
      _oldExposure = old._oldExposure;
      _oldContrast = old._oldContrast;
      _oldHighlights = old._oldHighlights;
      _oldShadows = old._oldShadows;
      _oldTemperature = old._oldTemperature;
      _oldTint = old._oldTint;
      _oldVibrance = old._oldVibrance;
      _oldSaturation = old._oldSaturation;
    }
  }

  void _capture(Clip clip) {
    _oldExposure = clip.colorExposure;
    _oldContrast = clip.colorContrast;
    _oldHighlights = clip.colorHighlights;
    _oldShadows = clip.colorShadows;
    _oldTemperature = clip.colorTemperature;
    _oldTint = clip.colorTint;
    _oldVibrance = clip.colorVibrance;
    _oldSaturation = clip.colorSaturation;
  }

  void _apply(Clip clip) {
    clip.colorExposure = newExposure;
    clip.colorContrast = newContrast;
    clip.colorHighlights = newHighlights;
    clip.colorShadows = newShadows;
    clip.colorTemperature = newTemperature;
    clip.colorTint = newTint;
    clip.colorVibrance = newVibrance;
    clip.colorSaturation = newSaturation;
  }

  void _restore(Clip clip) {
    clip.colorExposure = _oldExposure;
    clip.colorContrast = _oldContrast;
    clip.colorHighlights = _oldHighlights;
    clip.colorShadows = _oldShadows;
    clip.colorTemperature = _oldTemperature;
    clip.colorTint = _oldTint;
    clip.colorVibrance = _oldVibrance;
    clip.colorSaturation = _oldSaturation;
  }

  @override
  void execute(Project project) {
    final clip = project.allClips.where((c) => c.id == clipId).firstOrNull;
    if (clip == null) return;
    _capture(clip);
    _apply(clip);
  }

  @override
  void undo(Project project) {
    final clip = project.allClips.where((c) => c.id == clipId).firstOrNull;
    if (clip == null) return;
    _restore(clip);
  }
}

/// Command: Change a clip's text-overlay properties with undo.
/// v1.0.0: The inspector rich-text editor previously mutated clip fields
/// directly (not undoable). This command snapshots the whole text-property
/// set and coalesces a typing session into a single undo entry.
class ChangeClipTextCommand extends EditCommand {
  final String clipId;
  final String newContent;
  final String newFont;
  final double newFontSize;
  final int newColorValue;
  final bool newBold;
  final bool newItalic;
  final bool newUnderline;
  final double newStrokeWidth;
  final int newStrokeColorValue;
  final bool newShadow;
  final int newBgColorValue;
  final int newAlignment;
  // v1.0.1: gradient was missing from the text command — toggling it in the
  // inspector was not undoable.
  final bool newGradient;

  late String _oldContent;
  late String _oldFont;
  late double _oldFontSize;
  late int _oldColorValue;
  late bool _oldBold;
  late bool _oldItalic;
  late bool _oldUnderline;
  late double _oldStrokeWidth;
  late int _oldStrokeColorValue;
  late bool _oldShadow;
  late int _oldBgColorValue;
  late int _oldAlignment;
  late bool _oldGradient;

  ChangeClipTextCommand({
    required this.clipId,
    required this.newContent,
    required this.newFont,
    required this.newFontSize,
    required this.newColorValue,
    required this.newBold,
    required this.newItalic,
    required this.newUnderline,
    required this.newStrokeWidth,
    required this.newStrokeColorValue,
    required this.newShadow,
    required this.newBgColorValue,
    required this.newAlignment,
    required this.newGradient,
  });

  /// One undo entry per clip text-edit session — coalesce on the clip id only
  /// (no gestureId) so a whole typing run collapses to a single undo.
  @override
  String? get coalesceKey => 'clip-text:$clipId';

  @override
  String get description => 'Edit text';

  @override
  void inheritUndoState(EditCommand old) {
    if (old is ChangeClipTextCommand) {
      _oldContent = old._oldContent;
      _oldFont = old._oldFont;
      _oldFontSize = old._oldFontSize;
      _oldColorValue = old._oldColorValue;
      _oldBold = old._oldBold;
      _oldItalic = old._oldItalic;
      _oldUnderline = old._oldUnderline;
      _oldStrokeWidth = old._oldStrokeWidth;
      _oldStrokeColorValue = old._oldStrokeColorValue;
      _oldShadow = old._oldShadow;
      _oldBgColorValue = old._oldBgColorValue;
      _oldAlignment = old._oldAlignment;
      _oldGradient = old._oldGradient;
    }
  }

  void _capture(Clip clip) {
    _oldContent = clip.textContent;
    _oldFont = clip.textFont;
    _oldFontSize = clip.textFontSize;
    _oldColorValue = clip.textColorValue;
    _oldBold = clip.textBold;
    _oldItalic = clip.textItalic;
    _oldUnderline = clip.textUnderline;
    _oldStrokeWidth = clip.textStrokeWidth;
    _oldStrokeColorValue = clip.textStrokeColorValue;
    _oldShadow = clip.textShadow;
    _oldBgColorValue = clip.textBackgroundColorValue;
    _oldAlignment = clip.textAlignment;
    _oldGradient = clip.textGradient;
  }

  void _apply(Clip clip) {
    clip.textContent = newContent;
    clip.textFont = newFont;
    clip.textFontSize = newFontSize;
    clip.textColorValue = newColorValue;
    clip.textBold = newBold;
    clip.textItalic = newItalic;
    clip.textUnderline = newUnderline;
    clip.textStrokeWidth = newStrokeWidth;
    clip.textStrokeColorValue = newStrokeColorValue;
    clip.textShadow = newShadow;
    clip.textBackgroundColorValue = newBgColorValue;
    clip.textAlignment = newAlignment;
    clip.textGradient = newGradient;
  }

  @override
  void execute(Project project) {
    final clip = project.allClips.where((c) => c.id == clipId).firstOrNull;
    if (clip == null) return;
    _capture(clip);
    _apply(clip);
  }

  @override
  void undo(Project project) {
    final clip = project.allClips.where((c) => c.id == clipId).firstOrNull;
    if (clip == null) return;
    clip.textContent = _oldContent;
    clip.textFont = _oldFont;
    clip.textFontSize = _oldFontSize;
    clip.textColorValue = _oldColorValue;
    clip.textBold = _oldBold;
    clip.textItalic = _oldItalic;
    clip.textUnderline = _oldUnderline;
    clip.textStrokeWidth = _oldStrokeWidth;
    clip.textStrokeColorValue = _oldStrokeColorValue;
    clip.textShadow = _oldShadow;
    clip.textBackgroundColorValue = _oldBgColorValue;
    clip.textAlignment = _oldAlignment;
    clip.textGradient = _oldGradient;
  }
}

/// Command: Set a clip's speed-ramp curve (v1.1.0, PLAN 3.11) — undoable,
/// engine-synced via the command-history listener.
class ChangeSpeedCurveCommand extends EditCommand {
  final String clipId;
  final List<SpeedRampPoint> newCurve;
  late List<SpeedRampPoint> _oldCurve;
  bool _applied = false;

  ChangeSpeedCurveCommand({required this.clipId, required this.newCurve});

  @override
  String get description =>
      newCurve.isEmpty ? 'Clear speed ramp' : 'Set speed ramp curve';

  @override
  void execute(Project project) {
    final clip = project.allClips.where((c) => c.id == clipId).firstOrNull;
    if (clip == null) return;
    _oldCurve = List.of(clip.speedCurve);
    clip.speedCurve = List.of(newCurve);
    _applied = true;
  }

  @override
  void undo(Project project) {
    if (!_applied) return;
    final clip = project.allClips.where((c) => c.id == clipId).firstOrNull;
    if (clip == null) return;
    clip.speedCurve = List.of(_oldCurve);
  }
}

/// Command: Set a clip's picture-in-picture geometry (v1.1.0, PLAN 3.4) —
/// undoable, engine-synced via the command-history listener. Coalesces per
/// slider gesture (same pattern as ChangeClipPropertyCommand).
class ChangePipCommand extends EditCommand {
  final String clipId;
  final double newX, newY, newW, newH, newRotation;
  final int? gestureId;
  late double _oldX, _oldY, _oldW, _oldH, _oldRotation;
  bool _applied = false;

  ChangePipCommand({
    required this.clipId,
    required this.newX,
    required this.newY,
    required this.newW,
    required this.newH,
    required this.newRotation,
    this.gestureId,
  });

  @override
  String? get coalesceKey => 'clip-pip:$clipId:$gestureId';

  @override
  String get description => 'Set picture-in-picture geometry';

  @override
  void inheritUndoState(EditCommand old) {
    if (old is ChangePipCommand) {
      _oldX = old._oldX;
      _oldY = old._oldY;
      _oldW = old._oldW;
      _oldH = old._oldH;
      _oldRotation = old._oldRotation;
      _applied = true;
    }
  }

  @override
  void execute(Project project) {
    final clip = project.allClips.where((c) => c.id == clipId).firstOrNull;
    if (clip == null) return;
    _oldX = clip.pipX;
    _oldY = clip.pipY;
    _oldW = clip.pipW;
    _oldH = clip.pipH;
    _oldRotation = clip.pipRotation;
    clip.pipX = newX;
    clip.pipY = newY;
    clip.pipW = newW;
    clip.pipH = newH;
    clip.pipRotation = newRotation;
    _applied = true;
  }

  @override
  void undo(Project project) {
    if (!_applied) return;
    final clip = project.allClips.where((c) => c.id == clipId).firstOrNull;
    if (clip == null) return;
    clip.pipX = _oldX;
    clip.pipY = _oldY;
    clip.pipW = _oldW;
    clip.pipH = _oldH;
    clip.pipRotation = _oldRotation;
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
  bool _disposed = false;

  CommandHistory({this.maxHistory = 100});

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  String? get lastUndoDescription => canUndo ? _undoStack.last.description : null;
  String? get lastRedoDescription => canRedo ? _redoStack.last.description : null;

  int get undoCount => _undoStack.length;
  int get redoCount => _redoStack.length;

  List<EditCommand> get undoStack => List.unmodifiable(_undoStack);
  List<EditCommand> get redoStack => List.unmodifiable(_redoStack);

  /// Execute a command and push it to the undo stack.
  void execute(EditCommand command, Project project) {
    if (_disposed) return;
    command.execute(project);

    // v0.7.8: Coalesce consecutive commands with the same key (e.g. slider
    // drags) so one gesture produces exactly one undo entry. The replacement
    // inherits the original captured value, so undo restores pre-gesture state.
    final last = _undoStack.isNotEmpty ? _undoStack.last : null;
    final key = command.coalesceKey;
    if (key != null && last != null && last.coalesceKey == key) {
      command.inheritUndoState(last);
      _undoStack[_undoStack.length - 1] = command;
    } else {
      _undoStack.add(command);
    }
    _redoStack.clear(); // New action invalidates redo history

    if (_undoStack.length > maxHistory) {
      _undoStack.removeAt(0);
    }

    project.markModified();
    notifyListeners();
  }

  /// Undo the last command.
  bool undo(Project project) {
    if (_disposed || !canUndo) return false;
    final command = _undoStack.removeLast();
    command.undo(project);
    _redoStack.add(command);
    project.markModified();
    notifyListeners();
    return true;
  }

  /// Redo the last undone command.
  bool redo(Project project) {
    if (_disposed || !canRedo) return false;
    final command = _redoStack.removeLast();
    command.execute(project);
    _undoStack.add(command);
    project.markModified();
    notifyListeners();
    return true;
  }

  /// Clear all history.
  void clear() {
    if (_disposed) return;
    _undoStack.clear();
    _redoStack.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}
