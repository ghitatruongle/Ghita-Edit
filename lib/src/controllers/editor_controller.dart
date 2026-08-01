import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'engine_service.dart';
import 'command_history.dart';
import 'project_service.dart';
import '../models/project.dart';
import '../models/clip.dart';
import '../models/track.dart';
import '../core/version.dart';

/// Orchestrates UI state, project model, undo/redo, and native engine.
/// This is the central state manager for the entire editor.
class EditorController extends ChangeNotifier {
  final EngineService _engine;
  final CommandHistory commandHistory = CommandHistory();
  final ProjectService projectService = ProjectService();

  bool _disposed = false;
  String _statusMessage = 'Initializing...';
  Timer? _autoSaveTimer;

  // --- Project State ---
  late Project project;

  // --- Engine State ---
  EngineService get engineService => _engine;
  bool get isEngineReady => _engine.isReady;
  String get engineVersion => _engine.engineVersion;

  bool _isPlaying = false;
  int _positionMs = 0;
  double _volume = 1.0;
  int _activeFilterType = 0;
  double _filterIntensity = 1.0;

  bool get isPlaying => _isPlaying;
  int get positionMs => _positionMs;
  int get durationMs => project.totalDurationMs;
  double get volume => _volume;
  int get activeFilterType => _activeFilterType;
  double get filterIntensity => _filterIntensity;
  Uint8List? get frameBytes => _engine.frameBytes;

  String get statusMessage => _statusMessage;
  bool get isEngineNativeAvailable => _engine.isNativeLibraryLoaded; // Check if native library loaded successfully

  // --- Clipboard ---
  Clip? _clipboardClip;
  bool get hasClipboard => _clipboardClip != null;

  // --- Project Accessors ---
  List<Track> get tracks => project.tracks;
  Clip? get selectedClip => project.selectedClip;

  // v0.5.8: Export state access
  bool get isExporting => _engine.isExporting;
  List<Clip> get selectedClips => project.selectedClips;
  int get selectedClipCount => project.selectedClipCount;
  bool get canUndo => commandHistory.canUndo;
  bool get canRedo => commandHistory.canRedo;
  bool get isProjectModified => project.modifiedAt.isAfter(project.createdAt);

  String get currentMediaName {
    final sel = selectedClip;
    if (sel != null) return sel.displayName;
    if (project.allClips.isNotEmpty) return project.allClips.first.displayName;
    return 'No media loaded';
  }

  EditorController({EngineService? engine})
      : _engine = engine ?? EngineService() {
    project = Project(name: 'Untitled Project');
    commandHistory.addListener(_onCommandHistoryChanged);
    // v0.7.8: Forward engine tick notifications so the UI (playhead,
    // timecode, frame preview) actually moves during playback.
    _engine.addListener(_onEngineTick);
  }

  void _onEngineTick() {
    if (!_disposed) notifyListeners();
  }

  /// Initialize the native engine asynchronously.
  Future<void> init() async {
    if (_disposed) return;
    try {
      await _engine.initialize();
      if (_disposed) return;
      
      // Check if engine is actually ready or if we're in demo mode
      if (!_engine.isNativeLibraryLoaded || !isEngineReady) {
        _statusMessage = 'Native engine unavailable (Demo Mode - limited features)';
        // v0.7.8: Autosave must run in every mode — losing a project in
        // Demo Mode is just as bad as with the engine present
        _startAutoSave();
        notifyListeners();
        return;
      }
      _statusMessage = 'Engine ready • v$flutterVersion';
      _startAutoSave();
      notifyListeners();
    } catch (e, st) {
      if (!_disposed) {
        _statusMessage = 'Error: $e\n$st';
        notifyListeners();
      }
    }
  }

  // ========== PLAYBACK CONTROLS ==========

  void togglePlayPause() {
    if (_disposed) return;
    _isPlaying = !_isPlaying;
    if (_engine.isReady) {
      if (_isPlaying) {
        _engine.play();
      } else {
        _engine.pause();
      }
    }
    notifyListeners();
  }

  void play() {
    if (_disposed || _isPlaying) return;
    _isPlaying = true;
    if (_engine.isReady) _engine.play();
    notifyListeners();
  }

  void pause() {
    if (_disposed || !_isPlaying) return;
    _isPlaying = false;
    if (_engine.isReady) _engine.pause();
    notifyListeners();
  }

  void seek(int positionMs) {
    if (_disposed) return;
    final clamped = positionMs.clamp(0, durationMs);
    _positionMs = clamped;
    project.playheadMs = clamped;
    if (_engine.isReady) {
      _engine.seek(clamped);
    }
    notifyListeners();
  }

  void seekRelative(int deltaMs) {
    seek(_positionMs + deltaMs);
  }

  void setVolume(double val) {
    if (_disposed) return;
    final clamped = val.clamp(0.0, 2.0);
    _volume = clamped;
    if (_engine.isReady) {
      _engine.setVolume(clamped);
    }
    notifyListeners();
  }

  void setFilter(int filterType, double intensity) {
    if (_disposed) return;
    // v0.4.5: Extended filter range 0-10 (was 0-4)
    final safeType = filterType.clamp(0, 10);
    final safeIntensity = intensity.clamp(0.0, 1.0);
    _activeFilterType = safeType;
    _filterIntensity = safeIntensity;
    if (_engine.isReady) {
      _engine.applyFilter(safeType, safeIntensity);
    }
    notifyListeners();
  }

  // v0.4.5: Maps Dart clip IDs (String) → native engine clip IDs (int)
  final Map<String, int> _nativeClipIdMap = {};
  int _nextNativeClipId = 1;

  int _getOrCreateNativeClipId(String dartClipId) {
    return _nativeClipIdMap.putIfAbsent(dartClipId, () => _nextNativeClipId++);
  }

  // v0.4.5: Set clip transition via native engine
  // v0.7.8: Persists on the Dart clip model through an undoable command
  // (inspector dropdown reflects state, Ctrl+Z reverts, JSON round-trips).
  void setClipTransition(String clipId, int transitionType, int durationMs) {
    if (_disposed) return;
    // v0.7.8: Clamp — engine transition enum is 0..8, duration must be > 0.
    final safeType = transitionType.clamp(0, 8);
    final safeDuration = durationMs < 1 ? 500 : durationMs;
    commandHistory.execute(
      ChangeClipTransitionCommand(
        clipId: clipId,
        newType: safeType,
        newDurationMs: safeDuration,
      ),
      project,
    );
    if (_engine.isReady && _engine.bindings != null) {
      final nativeId = _getOrCreateNativeClipId(clipId);
      _engine.bindings!.setClipTransition(
        _engine.ctx,
        nativeId,
        safeType,
        safeDuration,
      );
    }
    notifyListeners();
  }

  // ========== CLIP & TIMELINE OPERATIONS ==========

  /// Import a media file and add it as a clip to the video track.
  void importMedia(String path) {
    if (_disposed || path.isEmpty) return;

    // Use path package for proper cross-platform path handling with Unicode support
    final fileName = basename(path);
    // extension() returns '.mp3' (with leading dot) — strip it before matching
    final fileExtension = extension(fileName).toLowerCase().replaceFirst('.', '');

    // Determine clip type from fileExtension
    ClipType clipType;
    String? targetTrackId;
    if (['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(fileExtension)) {
      clipType = ClipType.video;
    } else if (['mp3', 'wav', 'flac', 'aac', 'ogg'].contains(fileExtension)) {
      clipType = ClipType.audio;
    } else if (['png', 'jpg', 'jpeg', 'gif', 'bmp'].contains(fileExtension)) {
      clipType = ClipType.image;
    } else {
      clipType = ClipType.video;
    }
    targetTrackId = trackIdForClipType(clipType);
    if (targetTrackId == null) {
      _statusMessage = 'No track available for this media type';
      notifyListeners();
      return;
    }

    final clip = Clip(
      id: Clip.nextId(),
      sourceFilePath: path,
      displayName: fileName,
      timelineStartMs: 0,
      durationMs: 10000, // Provisional; synced from engine below
      type: clipType,
    );

    // Use command pattern for undo support
    final cmd = AddClipCommand(
      trackId: targetTrackId,
      clip: clip,
      positionMs: _getNextAvailablePosition(targetTrackId),
    );
    commandHistory.execute(cmd, project);

    // Tell native engine and sync real media duration back to the clip
    if (_engine.isReady) {
      _engine.loadMedia(path);
      final engineDuration = _engine.durationMs;
      if (engineDuration > 0) {
        clip.durationMs = engineDuration;
        clip.sourceOutMs = clip.sourceInMs + engineDuration;
      }
    }

    _statusMessage = 'Imported: $fileName';
    notifyListeners();
  }

  /// Legacy loadMedia compatibility.
  void loadMedia(String path) => importMedia(path);

  /// Split the clip at the current playhead position.
  void splitAtPlayhead() {
    if (_disposed) return;

    for (final track in project.tracks) {
      final clip = track.clipAtPosition(_positionMs);
      if (clip != null) {
        // v0.7.8: Splitting exactly at a clip boundary is a no-op — do not
        // push a command for it: undoing such a command re-added the original
        // clip and produced a duplicate on the track.
        if (_positionMs <= clip.timelineStartMs || _positionMs >= clip.timelineEndMs) {
          _statusMessage = 'No clip at playhead to split';
          notifyListeners();
          return;
        }
        final cmd = SplitClipCommand(
          trackId: track.id,
          clipId: clip.id,
          positionMs: _positionMs,
        );
        commandHistory.execute(cmd, project);
        // v0.7.8: The original clip id disappears after split — drop it from
        // the selection so highlight/count stay consistent with reality.
        project.pruneSelection();
        _statusMessage = 'Split clip at ${(_positionMs / 1000).toStringAsFixed(1)}s';
        notifyListeners();
        return;
      }
    }
    _statusMessage = 'No clip at playhead to split';
    notifyListeners();
  }

  /// Delete the currently selected clip(s). Deletes all selected clips in multi-select mode.
  void deleteSelectedClip() {
    if (_disposed) return;

    if (project.selectedClipCount > 1) {
      // Multi-delete: delete all selected clips
      final selectedClips = project.selectedClips.toList();
      if (selectedClips.isEmpty) {
        _statusMessage = 'No clips selected';
        notifyListeners();
        return;
      }
      for (final sel in selectedClips) {
        final track = project.trackForClip(sel.id);
        if (track == null) continue;
        final cmd = DeleteClipCommand(trackId: track.id, clip: sel);
        commandHistory.execute(cmd, project);
      }
      // v0.7.8: Drop selection ids of deleted clips (stale selection caused
      // "N selected" with nothing selectable and phantom highlights).
      project.pruneSelection();
      _statusMessage = 'Deleted ${selectedClips.length} clips';
      notifyListeners();
      return;
    }

    // Single delete: backward compatible
    final sel = project.selectedClip;
    if (sel == null) {
      _statusMessage = 'No clip selected';
      notifyListeners();
      return;
    }

    final track = project.trackForClip(sel.id);
    if (track == null) return;

    final cmd = DeleteClipCommand(trackId: track.id, clip: sel);
    commandHistory.execute(cmd, project);
    project.pruneSelection();
    _statusMessage = 'Deleted: ${sel.displayName}';
    notifyListeners();
  }

  /// Add a new track dynamically (v0.3.5).
  void addNewTrack(String name, TrackType type) {
    if (_disposed) return;
    final newTrack = Track(
      id: Track.nextId(),
      name: name,
      type: type,
    );
    final cmd = AddTrackCommand(track: newTrack);
    commandHistory.execute(cmd, project);
    _statusMessage = 'Added track: $name';
    notifyListeners();
  }

  /// Remove a track dynamically by ID (v0.3.5).
  void removeTrack(String trackId) {
    if (_disposed) return;
    final track = project.tracks.firstWhere((t) => t.id == trackId, orElse: () => Track(id: '', name: '', type: TrackType.video));
    if (track.id.isEmpty) return;
    final cmd = RemoveTrackCommand(track: track);
    commandHistory.execute(cmd, project);
    _statusMessage = 'Removed track: ${track.name}';
    notifyListeners();
  }

  /// Trim the start of a clip at a new position (undoable).
  void trimClipStart(String clipId, int newStartMs) {
    if (_disposed) return;
    final track = project.trackForClip(clipId);
    if (track == null) return;
    final clip = track.clips.firstWhere((c) => c.id == clipId, orElse: () => Clip(id: '', sourceFilePath: '', displayName: '', timelineStartMs: 0, durationMs: 0));
    if (clip.id.isEmpty) return;
    final cmd = TrimClipCommand(trackId: track.id, clipId: clipId, trimStart: true, newBoundaryMs: newStartMs);
    commandHistory.execute(cmd, project);
    notifyListeners();
  }

  /// Trim the end of a clip at a new position (undoable).
  void trimClipEnd(String clipId, int newEndMs) {
    if (_disposed) return;
    final track = project.trackForClip(clipId);
    if (track == null) return;
    final clip = track.clips.firstWhere((c) => c.id == clipId, orElse: () => Clip(id: '', sourceFilePath: '', displayName: '', timelineStartMs: 0, durationMs: 0));
    if (clip.id.isEmpty) return;
    final cmd = TrimClipCommand(trackId: track.id, clipId: clipId, trimStart: false, newBoundaryMs: newEndMs);
    commandHistory.execute(cmd, project);
    notifyListeners();
  }

  // v0.7.8: Per-clip scalar properties with undo/redo support (one undo entry
  // per drag gesture thanks to command coalescing keyed by _propertyGesture).
  int _propertyGestureCounter = 0;

  /// Call on slider drag start — a fresh gesture id breaks the coalescing
  /// chain, so two separate drags produce two undo entries.
  void beginPropertyGesture() {
    _propertyGestureCounter++;
  }

  void setClipSpeed(String clipId, double speed) {
    if (_disposed) return;
    commandHistory.execute(
      ChangeClipPropertyCommand(
        clipId: clipId,
        property: 'speed',
        newValue: speed.clamp(0.25, 4.0),
        gestureId: _propertyGestureCounter,
      ),
      project,
    );
    notifyListeners();
  }

  void setClipOpacity(String clipId, double opacity) {
    if (_disposed) return;
    commandHistory.execute(
      ChangeClipPropertyCommand(
        clipId: clipId,
        property: 'opacity',
        newValue: opacity.clamp(0.0, 1.0),
        gestureId: _propertyGestureCounter,
      ),
      project,
    );
    notifyListeners();
  }

  void setClipVolume(String clipId, double volume) {
    if (_disposed) return;
    commandHistory.execute(
      ChangeClipPropertyCommand(
        clipId: clipId,
        property: 'volume',
        newValue: volume.clamp(0.0, 2.0),
        gestureId: _propertyGestureCounter,
      ),
      project,
    );
    notifyListeners();
  }

  /// Set track mute state.
  void setTrackMute(String trackId, bool muted) {
    if (_disposed) return;
    final track = project.tracks.firstWhere((t) => t.id == trackId, orElse: () => Track(id: '', name: '', type: TrackType.video));
    if (track.id.isEmpty) return;
    track.isMuted = muted;
    _statusMessage = muted ? 'Track muted' : 'Track unmuted';
    notifyListeners();
  }

  /// Set track visibility.
  void setTrackVisible(String trackId, bool visible) {
    if (_disposed) return;
    final track = project.tracks.firstWhere((t) => t.id == trackId, orElse: () => Track(id: '', name: '', type: TrackType.video));
    if (track.id.isEmpty) return;
    track.isVisible = visible;
    notifyListeners();
  }

  /// Set track lock state.
  void setTrackLock(String trackId, bool locked) {
    if (_disposed) return;
    final track = project.tracks.firstWhere((t) => t.id == trackId, orElse: () => Track(id: '', name: '', type: TrackType.video));
    if (track.id.isEmpty) return;
    track.isLocked = locked;
    notifyListeners();
  }

  /// Set track volume.
  void setTrackVolume(String trackId, double volume) {
    if (_disposed) return;
    final track = project.tracks.firstWhere((t) => t.id == trackId, orElse: () => Track(id: '', name: '', type: TrackType.video));
    if (track.id.isEmpty) return;
    track.volume = volume.clamp(0.0, 2.0);
    notifyListeners();
  }

  /// Select a clip by ID (single-select).
  void selectClip(String clipId) {
    if (_disposed) return;
    project.selectClip(clipId);
    notifyListeners();
  }

  /// Toggle a clip in/out of the current multi-selection.
  void toggleClipSelection(String clipId) {
    if (_disposed) return;
    project.toggleClipSelection(clipId);
    notifyListeners();
  }

  /// Select a range of clips between two clip IDs (Shift+click).
  void selectRange(String fromClipId, String toClipId) {
    if (_disposed) return;
    project.selectRange(fromClipId, toClipId);
    notifyListeners();
  }

  /// Deselect all clips.
  void deselectAll() {
    if (_disposed) return;
    project.deselectAll();
    notifyListeners();
  }

  /// Move a clip to a new timeline position.
  void moveClip(String trackId, String clipId, int newStartMs) {
    if (_disposed) return;
    final cmd = MoveClipCommand(trackId: trackId, clipId: clipId, newStartMs: newStartMs);
    commandHistory.execute(cmd, project);
    notifyListeners();
  }

  /// Move a clip with explicit original position (used by drag-drop for correct undo).
  void moveClipFrom(String trackId, String clipId, int oldStartMs, int newStartMs) {
    if (_disposed) return;
    final cmd = MoveClipCommand(trackId: trackId, clipId: clipId, newStartMs: newStartMs, explicitOldStartMs: oldStartMs);
    commandHistory.execute(cmd, project);
    notifyListeners();
  }

  /// Copy selected clip to clipboard.
  void copySelectedClip() {
    final sel = project.selectedClip;
    if (sel != null) {
      _clipboardClip = sel.copyWith(id: Clip.nextId());
      _statusMessage = 'Copied: ${sel.displayName}';
      notifyListeners();
    }
  }

  /// Paste clip from clipboard at playhead.
  void pasteClip() {
    if (_clipboardClip == null) return;
    final trackId = trackIdForClipType(_clipboardClip!.type);
    if (trackId == null) return;
    final clip = _clipboardClip!.copyWith(
      id: Clip.nextId(),
      timelineStartMs: _positionMs,
    );
    final cmd = AddClipCommand(trackId: trackId, clip: clip, positionMs: _positionMs);
    commandHistory.execute(cmd, project);
    _statusMessage = 'Pasted: ${clip.displayName}';
    notifyListeners();
  }

  // v0.7.8: Per-clip filter with undo/redo (ChangeFilterCommand).
  void setClipFilter(String clipId, int filterType, double intensity) {
    if (_disposed) return;
    commandHistory.execute(
      ChangeFilterCommand(
        clipId: clipId,
        newFilterType: filterType.clamp(0, 10),
        newIntensity: intensity.clamp(0.0, 1.0),
      ),
      project,
    );
    notifyListeners();
  }

  // ========== UNDO / REDO ==========

  void undo() {
    if (_disposed) return;
    if (commandHistory.undo(project)) {
      _statusMessage = 'Undo: ${commandHistory.lastRedoDescription ?? ""}';
      notifyListeners();
    }
  }

  void redo() {
    if (_disposed) return;
    if (commandHistory.redo(project)) {
      _statusMessage = 'Redo: ${commandHistory.lastUndoDescription ?? ""}';
      notifyListeners();
    }
  }

  // ========== PROJECT MANAGEMENT ==========

  /// Create a new empty project.
  void newProject() {
    if (_disposed) return;
    project = Project(name: 'Untitled Project');
    commandHistory.clear();
    _positionMs = 0;
    _isPlaying = false;
    _volume = 1.0;
    _activeFilterType = 0;
    _filterIntensity = 1.0;
    if (_engine.isReady) {
      _engine.pause();
      _engine.seek(0);
    }
    // v0.7.8: Reset the Dart↔native clip id map — stale ids would alias
    // clips of the new project (and the map grew unbounded across projects).
    _nativeClipIdMap.clear();
    _nextNativeClipId = 1;
    _statusMessage = 'New project created';
    notifyListeners();
  }

  /// Save project to file.
  Future<bool> saveProject(String filePath) async {
    final success = await projectService.saveProject(project, filePath);
    if (success) {
      _statusMessage = 'Project saved: ${project.name}';
      notifyListeners();
    }
    return success;
  }

  /// Quick save (to last path).
  Future<bool> quickSave() async {
    final success = await projectService.quickSave(project);
    if (success) {
      _statusMessage = 'Project saved';
      notifyListeners();
    }
    return success;
  }

  /// Load project from file.
  Future<bool> loadProject(String filePath) async {
    final loaded = await projectService.loadProject(filePath);
    if (loaded != null) {
      project = loaded;
      commandHistory.clear();
      _positionMs = 0;
      _isPlaying = false;
      _volume = 1.0;
      _activeFilterType = 0;
      _filterIntensity = 1.0;
      if (_engine.isReady) {
        _engine.pause();
        _engine.seek(0);
      }
      // v0.7.8: Reset native clip id mapping for the new project.
      _nativeClipIdMap.clear();
      _nextNativeClipId = 1;
      _statusMessage = 'Loaded: ${project.name}';
      notifyListeners();
      return true;
    }
    return false;
  }

  // ========== KEYBOARD SHORTCUTS ==========

  /// Handle keyboard event — returns true if consumed.
  bool handleKeyEvent(KeyEvent event) {
    if (_disposed) return false;
    if (event is! KeyDownEvent) return false;

    // v0.7.8: Never hijack keys while the user is typing in a text field —
    // space/backspace/arrows would otherwise control playback and seeking
    // instead of editing the field.
    final focusedWidget = FocusManager.instance.primaryFocus?.context?.widget;
    if (focusedWidget is EditableText) return false;

    final key = event.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;

    // Ctrl+Z = Undo
    if (ctrl && key == LogicalKeyboardKey.keyZ) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        redo();
      } else {
        undo();
      }
      return true;
    }

    // Ctrl+Y = Redo
    if (ctrl && key == LogicalKeyboardKey.keyY) {
      redo();
      return true;
    }

    // Ctrl+S = Save
    if (ctrl && key == LogicalKeyboardKey.keyS) {
      quickSave();
      return true;
    }

    // Ctrl+C = Copy
    if (ctrl && key == LogicalKeyboardKey.keyC) {
      copySelectedClip();
      return true;
    }

    // Ctrl+X = Cut (copy + delete) — v0.7.8: advertised in the shortcuts
    // dialog but never handled.
    if (ctrl && key == LogicalKeyboardKey.keyX) {
      copySelectedClip();
      deleteSelectedClip();
      return true;
    }

    // Ctrl+A = Select all clips — v0.7.8: advertised but never handled.
    if (ctrl && key == LogicalKeyboardKey.keyA) {
      project.selectAll();
      notifyListeners();
      return true;
    }

    // Ctrl+V = Paste
    if (ctrl && key == LogicalKeyboardKey.keyV) {
      pasteClip();
      return true;
    }

    // Space = Play/Pause
    if (key == LogicalKeyboardKey.space) {
      togglePlayPause();
      return true;
    }

    // S = Split at playhead
    if (key == LogicalKeyboardKey.keyS && !ctrl) {
      splitAtPlayhead();
      return true;
    }

    // Delete/Backspace = Delete selected
    if (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace) {
      deleteSelectedClip();
      return true;
    }

    // Left/Right arrow = seek +-1s
    if (key == LogicalKeyboardKey.arrowLeft) {
      seekRelative(-1000);
      return true;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      seekRelative(1000);
      return true;
    }

    // J/K/L = JKL shuttle control
    if (key == LogicalKeyboardKey.keyJ) {
      seekRelative(-5000);
      return true;
    }
    if (key == LogicalKeyboardKey.keyK) {
      if (_isPlaying) {
        pause();
      } else {
        play();
      }
      return true;
    }
    if (key == LogicalKeyboardKey.keyL) {
      seekRelative(5000);
      return true;
    }

    // Home = go to start
    if (key == LogicalKeyboardKey.home) {
      seek(0);
      return true;
    }

    // End = go to end
    if (key == LogicalKeyboardKey.end) {
      seek(durationMs);
      return true;
    }

    return false;
  }

  // ========== PRIVATE HELPERS ==========

  /// v0.7.8: Resolve the track for a clip type, falling back to the first
  /// available track. Never throws — a project loaded from disk may not have
  /// the default track ids (previously firstWhere threw StateError → crash).
  String? trackIdForClipType(ClipType type) {
    final preferred = switch (type) {
      ClipType.video => 'track_video_1',
      ClipType.audio => 'track_audio_1',
      ClipType.image ||
      ClipType.text ||
      ClipType.overlay ||
      ClipType.sticker => 'track_overlay_1',
    };
    if (project.tracks.any((t) => t.id == preferred)) return preferred;
    if (project.tracks.isNotEmpty) return project.tracks.first.id;
    return null;
  }

  int _getNextAvailablePosition(String trackId) {
    final track = project.tracks.where((t) => t.id == trackId).firstOrNull;
    if (track == null) return 0;
    return track.durationMs;
  }

  void _onCommandHistoryChanged() {
    if (!_disposed) notifyListeners();
  }

  void _startAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
      if (!_disposed && project.allClips.isNotEmpty) {
        final dir = await _autoSaveBaseDir();
        if (!_disposed) {
          try {
            await projectService.autoSave(project, dir);
          } catch (e) {
            debugPrint('[EditorController] Auto-save failed: $e');
          }
        }
      }
    });
  }

  /// Resolve a writable directory for autosaves.
  /// Uses app support dir (works in Release/Program Files); falls back to temp.
  Future<String> _autoSaveBaseDir() async {
    try {
      final dir = await getApplicationSupportDirectory();
      return dir.path;
    } catch (_) {
      return Directory.systemTemp.path;
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _autoSaveTimer?.cancel();
    _engine.removeListener(_onEngineTick);
    commandHistory.removeListener(_onCommandHistoryChanged);
    commandHistory.dispose();
    super.dispose();
    _engine.dispose();
  }
}

