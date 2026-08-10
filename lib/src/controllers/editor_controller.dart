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
import '../models/studio_mode.dart';
import '../core/version.dart';

/// Orchestrates UI state, project model, undo/redo, and native engine.
/// This is the central state manager for the entire editor.
class EditorController extends ChangeNotifier {
  final EngineService _engine;
  final CommandHistory commandHistory = CommandHistory();
  final ProjectService projectService = ProjectService();

  bool _disposed = false;
  bool _initComplete = false;
  bool _autoSaveInProgress = false;
  String _statusMessage = 'Initializing...';
  Timer? _autoSaveTimer;

  // --- Triple-Studio Mode State ---
  StudioMode _activeStudioMode = StudioMode.video;
  StudioMode get activeStudioMode => _activeStudioMode;
  set activeStudioMode(StudioMode mode) => setStudioMode(mode);

  void setStudioMode(StudioMode mode) {
    if (_activeStudioMode == mode) return;
    _activeStudioMode = mode;
    notifyListeners();
  }

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
  bool get isInitComplete => _initComplete;

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
    if (_disposed) return;
    // v1.0.2: Sync the controller playhead from the engine tick. Previously
    // this only forwarded the notification — _positionMs stayed 0 until the
    // user manually seeked, so the timeline playhead appeared frozen while
    // the engine position advanced (verified: engine reached 9907ms while
    // controller.positionMs remained 0).
    _positionMs = _engine.positionMs;
    notifyListeners();
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
        _initComplete = true;
        notifyListeners();
        return;
      }
      _statusMessage = 'Engine ready • v$flutterVersion';
      _startAutoSave();
      _initComplete = true;
      notifyListeners();
    } catch (e, st) {
      if (!_disposed) {
        _statusMessage = 'Error: $e\n$st';
        _initComplete = true;
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

  // v1.0.3: Noise suppression / "làm rõ âm thanh" — wires the DAW toggle to
  // the native mixer.
  void setNoiseSuppress(bool enabled) {
    if (_disposed) return;
    if (_engine.isReady) _engine.setNoiseSuppress(enabled);
    notifyListeners();
  }

  void setFilter(int filterType, double intensity) {
    if (_disposed) return;
    // v0.4.5: Extended filter range 0-10 (was 0-4)
    // v0.8.0: Extended to 0-20 (VHS/Glitch/Vignette/Grain/...).
    // v1.0.2: Extended to 0-22 (Skin Retouch 21, Chroma Key 22).
    final safeType = filterType.clamp(0, 22);
    final safeIntensity = intensity.clamp(0.0, 1.0);
    _activeFilterType = safeType;
    _filterIntensity = safeIntensity;
    if (_engine.isReady) {
      _engine.applyFilter(safeType, safeIntensity);
    }
    notifyListeners();
  }

  // v0.4.5: Maps Dart clip IDs (String) → native engine clip IDs (int)
  // v0.8.0: Owned and maintained by syncTimelineToEngine — stable ids keep
  // the engine's per-clip decoder cache alive across syncs.
  final Map<String, int> _nativeClipIdMap = {};
  int _nextNativeClipId = 1;

  // v0.8.0: Deferred engine sync — commands fire it once per event-loop turn
  // (a slider drag executing 60 commands/s results in one sync per frame).
  bool _engineSyncDirty = false;

  /// v1.1.0 (PLAN 3.6): Native (engine) clip id for a Dart clip id — null
  /// until the deferred timeline sync has assigned one.
  int? nativeClipIdFor(String dartClipId) => _nativeClipIdMap[dartClipId];

  void _markEngineSync() {
    if (_engineSyncDirty || _disposed) return;
    _engineSyncDirty = true;
    scheduleMicrotask(() {
      _engineSyncDirty = false;
      syncTimelineToEngine();
    });
  }

  /// v0.8.0: Public entry for UI code that mutates a clip directly (rich-text
  /// editor, sticker props) — schedules an engine timeline sync so preview
  /// reflects the change.
  void markEngineSync() => _markEngineSync();

  /// v0.8.0: Differential resync of the Dart timeline into the native engine.
  /// Unchanged clips keep their native id (and thus their decoder cache);
  /// changed clips are upserted in place; deleted clips are removed. This is
  /// what makes preview render the ACTUAL timeline (trim/split/move/filter/
  /// opacity/speed) instead of the last loaded media.
  void syncTimelineToEngine() {
    final engine = _engine;
    if (!engine.isReady || engine.bindings == null) return;
    try {
      final wantedDartIds = <String>{};
      var trackIndex = 0;
      for (final track in project.tracks) {
        engine.setTrackState(
          trackIndex,
          muted: track.isMuted,
          visible: track.isVisible,
          volume: track.volume,
        );
        for (final clip in track.clips) {
          wantedDartIds.add(clip.id);
          final nativeId =
              _nativeClipIdMap.putIfAbsent(clip.id, () => _nextNativeClipId++);
          final kind = switch (clip.type) {
            ClipType.video => 0,
            ClipType.audio => 1,
            ClipType.image => 2,
            ClipType.text => 3,
            ClipType.sticker => 4,
            // Overlay clips render as video (track index provides the layer).
            ClipType.overlay => 0,
          };
          engine.upsertClip(
            clipId: nativeId,
            filePath: clip.sourceFilePath,
            startMs: clip.timelineStartMs,
            durationMs: clip.durationMs,
            sourceInMs: clip.sourceInMs,
            trackIndex: trackIndex,
            kind: kind,
            volume: clip.volume,
            opacity: clip.opacity,
            speed: clip.speed,
          );
          engine.setClipFilter(nativeId, clip.filterType, clip.filterIntensity);
          engine.setClipTransition(
              nativeId, clip.transitionType, clip.transitionDurationMs);
          engine.setClipColorCorrection(
            clipId: nativeId,
            exposure: clip.colorExposure,
            contrast: clip.colorContrast,
            saturation: clip.colorSaturation,
            temperature: clip.colorTemperature,
            tint: clip.colorTint,
            vibrance: clip.colorVibrance,
            highlights: clip.colorHighlights,
            shadows: clip.colorShadows,
          );
          if (clip.type == ClipType.text || clip.type == ClipType.sticker) {
            engine.setClipText(
              clipId: nativeId,
              text: clip.textContent,
              fontSize: clip.textFontSize,
              colorArgb: clip.textColorValue,
            );
          }
          // v1.1.0 (PLAN 3.1/3.4/3.11): Sync keyframes, PiP geometry and the
          // speed-ramp curve. Replaces the whole set (clear then add) so a
          // removed keyframe/point cannot linger in the engine.
          engine.clearClipKeyframes(nativeId);
          for (final kf in clip.keyframes) {
            engine.addClipKeyframeEx(
              nativeId,
              kf.timeMs,
              kf.value,
              kf.property,
              kf.interpolation,
              kf.cp1x,
              kf.cp1y,
              kf.cp2x,
              kf.cp2y,
            );
          }
          if (clip.pipW < 1.0 || clip.pipH < 1.0 || clip.pipX != 0.0 ||
              clip.pipY != 0.0 || clip.pipRotation != 0.0) {
            engine.setClipPip(nativeId, clip.pipX, clip.pipY, clip.pipW,
                clip.pipH, clip.pipRotation);
          } else {
            engine.setClipPip(nativeId, 0.0, 0.0, 1.0, 1.0, 0.0);
          }
          engine.clearSpeedCurve(nativeId);
          for (final p in clip.speedCurve) {
            engine.addSpeedRampPoint(nativeId, p.t, p.speed);
          }
        }
        trackIndex++;
      }

      // Remove engine clips whose Dart clip no longer exists (delete/undo).
      for (final dartId in _nativeClipIdMap.keys.toList()) {
        if (!wantedDartIds.contains(dartId)) {
          final nativeId = _nativeClipIdMap.remove(dartId);
          if (nativeId != null) engine.removeClip(nativeId);
        }
      }
    } catch (e, st) {
      debugPrint('[EditorController] syncTimelineToEngine failed: $e\n$st');
    }
  }

  // v0.8.0: Legacy helper removed — the inline engine calls it performed are
  // superseded by syncTimelineToEngine (single code path, no drift).

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
    // v0.8.0: Engine mirroring happens in syncTimelineToEngine (via the
    // command-history listener) — no separate inline call to avoid drift.
    notifyListeners();
  }

  // ========== CLIP & TIMELINE OPERATIONS ==========

  /// Import a media file asynchronously and add it as a clip to the matching track (non-blocking).
  Future<void> importMedia(String path) async {
    if (_disposed || path.isEmpty) return;

    try {
      _statusMessage = 'Loading media: ${basename(path)}...';
      notifyListeners();

      final fileName = basename(path);
      final fileExtension = extension(fileName).toLowerCase().replaceFirst('.', '');

      // v1.0.2: Surface a clear warning when the file is gone (deleted or
      // moved between picking and import) instead of silently importing a
      // placeholder that cannot decode. The clip is still added so the
      // timeline stays usable — the engine probe below degrades gracefully.
      final fileExists = File(path).existsSync();
      if (!fileExists) {
        _statusMessage = 'Warning: file not found — $fileName (placeholder)';
        notifyListeners();
      }

      // Determine clip type from fileExtension
      ClipType clipType;
      if (['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(fileExtension)) {
        clipType = ClipType.video;
      } else if (['mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a'].contains(fileExtension)) {
        clipType = ClipType.audio;
      } else if (['png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp'].contains(fileExtension)) {
        clipType = ClipType.image;
      } else {
        clipType = ClipType.video;
      }

      final targetTrackId = trackIdForClipType(clipType);
      if (targetTrackId == null) {
        _statusMessage = 'No track available for media type: $fileExtension';
        notifyListeners();
        return;
      }

      final clip = Clip(
        id: Clip.nextId(),
        sourceFilePath: path,
        displayName: fileName,
        timelineStartMs: 0,
        durationMs: 10000, // Provisional 10s default
        type: clipType,
      );

      // Add clip to timeline command history
      final cmd = AddClipCommand(
        trackId: targetTrackId,
        clip: clip,
        positionMs: _getNextAvailablePosition(targetTrackId),
      );
      commandHistory.execute(cmd, project);
      project.selectClip(clip.id);

      // Asynchronously probe real media metadata — v1.1.0 (PLAN_REVIEW fix
      // #1): the probe now runs in a SEPARATE ISOLATE with a throwaway engine
      // context, so FFmpeg scan time (100ms-2s on slow media) no longer
      // freezes the UI. The old path called engine.loadMedia() on the UI
      // isolate (blocking FFI) and updated the waveform caches for nothing.
      if (_engine.isReady) {
        final mediaDur = await _engine.probeDurationAsync(path);
        if (mediaDur > 0) {
          clip.durationMs = mediaDur;
          clip.sourceOutMs = clip.sourceInMs + mediaDur;
        }
        // v1.1.0 (PLAN 1.1/B7): The provisional 10s clip was already synced
        // to the native timeline by the AddClipCommand microtask BEFORE this
        // probe ran, so the engine kept durationMs=10000 and preview wrapped
        // / export produced exactly 10s regardless of the real media length.
        // Re-sync now that the real duration is known (deferred, one per
        // event-loop turn — same pattern as every other command).
        _markEngineSync();
      }

      _statusMessage = 'Imported: $fileName';
    } catch (e) {
      _statusMessage = 'Error importing media: $e';
    } finally {
      if (!_disposed) notifyListeners();
    }
  }

  /// Specialized audio import for Audio DAW Studio.
  Future<void> importAudioToDaw(String path) async {
    await importMedia(path);
    activeStudioMode = StudioMode.audioDaw;
  }

  /// Specialized photo layer import for Photo Editor Studio.
  Future<void> importPhotoToStudio(String path) async {
    await importMedia(path);
    activeStudioMode = StudioMode.photo;
  }

  /// Legacy loadMedia compatibility.
  Future<void> loadMedia(String path) => importMedia(path);

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
    final track = project.tracks.where((t) => t.id == trackId).firstOrNull;
    if (track == null) return;
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
    final clip = track.clips.where((c) => c.id == clipId).firstOrNull;
    if (clip == null) return;
    final cmd = TrimClipCommand(trackId: track.id, clipId: clipId, trimStart: true, newBoundaryMs: newStartMs);
    commandHistory.execute(cmd, project);
    notifyListeners();
  }

  /// Trim the end of a clip at a new position (undoable).
  void trimClipEnd(String clipId, int newEndMs) {
    if (_disposed) return;
    final track = project.trackForClip(clipId);
    if (track == null) return;
    final clip = track.clips.where((c) => c.id == clipId).firstOrNull;
    if (clip == null) return;
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
    final track = project.tracks.where((t) => t.id == trackId).firstOrNull;
    if (track == null) return;
    track.isMuted = muted;
    // v0.8.0: Mirror to the native mixer (silences the track in preview/export).
    _syncTrackStateToEngine(track);
    _statusMessage = muted ? 'Track muted' : 'Track unmuted';
    notifyListeners();
  }

  /// Set track visibility.
  void setTrackVisible(String trackId, bool visible) {
    if (_disposed) return;
    final track = project.tracks.where((t) => t.id == trackId).firstOrNull;
    if (track == null) return;
    track.isVisible = visible;
    // v0.8.0: Mirror to the native renderer (hides the track in preview).
    _syncTrackStateToEngine(track);
    notifyListeners();
  }

  /// Set track lock state.
  void setTrackLock(String trackId, bool locked) {
    if (_disposed) return;
    final track = project.tracks.where((t) => t.id == trackId).firstOrNull;
    if (track == null) return;
    track.isLocked = locked;
    notifyListeners();
  }

  /// Set track volume.
  void setTrackVolume(String trackId, double volume) {
    if (_disposed) return;
    final track = project.tracks.where((t) => t.id == trackId).firstOrNull;
    if (track == null) return;
    track.volume = volume.clamp(0.0, 2.0);
    // v0.8.0: Mirror to the native mixer.
    _syncTrackStateToEngine(track);
    notifyListeners();
  }

  // v0.8.0: Push one track's mute/visible/volume to the native engine. The
  // engine indexes tracks by their position in the project track list.
  void _syncTrackStateToEngine(Track track) {
    final engine = _engine;
    if (!engine.isReady) return;
    final idx = project.tracks.indexOf(track);
    if (idx < 0) return;
    engine.setTrackState(idx, muted: track.isMuted, visible: track.isVisible, volume: track.volume);
  }

  /// v0.8.0 → v1.0.0: Update per-clip color correction.
  /// All values are -1.0..1.0; the engine applies them after the filter.
  /// v1.0.0: Now UNDOABLE — routes through ChangeClipColorCorrectionCommand
  /// (one undo entry per drag gesture via _propertyGestureCounter). Previously
  /// this mutated the clip directly, bypassing the command history, so color
  /// edits could never be undone. Unspecified fields keep the clip's current
  /// value so the command always carries the full 8-tuple.
  void setClipColorCorrection(
    String clipId, {
    double? exposure,
    double? contrast,
    double? saturation,
    double? temperature,
    double? tint,
    double? vibrance,
    double? highlights,
    double? shadows,
  }) {
    if (_disposed) return;
    final clip = project.allClips.where((c) => c.id == clipId).firstOrNull;
    if (clip == null) return;
    commandHistory.execute(
      ChangeClipColorCorrectionCommand(
        clipId: clipId,
        newExposure: exposure ?? clip.colorExposure,
        newContrast: contrast ?? clip.colorContrast,
        newHighlights: highlights ?? clip.colorHighlights,
        newShadows: shadows ?? clip.colorShadows,
        newTemperature: temperature ?? clip.colorTemperature,
        newTint: tint ?? clip.colorTint,
        newVibrance: vibrance ?? clip.colorVibrance,
        newSaturation: saturation ?? clip.colorSaturation,
        gestureId: _propertyGestureCounter,
      ),
      project,
    );
    notifyListeners();
  }

  /// v1.0.0: Update per-clip text-overlay properties — UNDOABLE via
  /// ChangeClipTextCommand. A whole typing session coalesces into one undo
  /// entry. The inspector rich-text editor previously mutated clip fields
  /// directly (not undoable). Unspecified fields keep the clip's current value.
  void setClipText(
    String clipId, {
    String? content,
    String? font,
    double? fontSize,
    int? colorValue,
    bool? bold,
    bool? italic,
    bool? underline,
    double? strokeWidth,
    int? strokeColorValue,
    bool? shadow,
    int? bgColorValue,
    int? alignment,
    bool? gradient,
  }) {
    if (_disposed) return;
    final clip = project.allClips.where((c) => c.id == clipId).firstOrNull;
    if (clip == null) return;
    commandHistory.execute(
      ChangeClipTextCommand(
        clipId: clipId,
        newContent: content ?? clip.textContent,
        newFont: font ?? clip.textFont,
        newFontSize: fontSize ?? clip.textFontSize,
        newColorValue: colorValue ?? clip.textColorValue,
        newBold: bold ?? clip.textBold,
        newItalic: italic ?? clip.textItalic,
        newUnderline: underline ?? clip.textUnderline,
        newStrokeWidth: strokeWidth ?? clip.textStrokeWidth,
        newStrokeColorValue: strokeColorValue ?? clip.textStrokeColorValue,
        newShadow: shadow ?? clip.textShadow,
        newBgColorValue: bgColorValue ?? clip.textBackgroundColorValue,
        newAlignment: alignment ?? clip.textAlignment,
        newGradient: gradient ?? clip.textGradient,
      ),
      project,
    );
    notifyListeners();
  }

  // v1.0.0: Clip grouping (Ctrl+G / Ctrl+Shift+G). The Clip model already
  // carries a groupId field; these methods give it real behavior — grouped
  // clips share an id so the UI can move/delete them together.
  /// Group the currently selected clips (requires 2+).
  void groupSelectedClips() {
    if (_disposed) return;
    final selected = project.selectedClips;
    if (selected.length < 2) {
      _statusMessage = 'Select 2+ clips to group';
      notifyListeners();
      return;
    }
    final gid = 'group_${DateTime.now().millisecondsSinceEpoch}';
    for (final clip in selected) {
      clip.groupId = gid;
    }
    _statusMessage = 'Grouped ${selected.length} clips';
    notifyListeners();
  }

  /// Ungroup every group touched by the current selection.
  void ungroupSelectedClips() {
    if (_disposed) return;
    final selected = project.selectedClips;
    final groupIds =
        selected.where((c) => c.groupId != null).map((c) => c.groupId!).toSet();
    if (groupIds.isEmpty) {
      _statusMessage = 'No grouped clips selected';
      notifyListeners();
      return;
    }
    var count = 0;
    for (final clip in project.allClips) {
      if (clip.groupId != null && groupIds.contains(clip.groupId)) {
        clip.groupId = null;
        count++;
      }
    }
    _statusMessage = 'Ungrouped $count clips';
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
  // v0.8.0: Engine mirroring happens in syncTimelineToEngine (single path).
  void setClipFilter(String clipId, int filterType, double intensity) {
    if (_disposed) return;
    // v0.8.0: Range extended to 0-20 (was 0-10).
    // v1.0.2: Extended to 0-22 (Skin Retouch 21, Chroma Key 22).
    final safeType = filterType.clamp(0, 22);
    final safeIntensity = intensity.clamp(0.0, 1.0);
    commandHistory.execute(
      ChangeFilterCommand(
        clipId: clipId,
        newFilterType: safeType,
        newIntensity: safeIntensity,
      ),
      project,
    );
    notifyListeners();
  }

  // ========== UNDO / REDO ==========

  // v1.1.0 (PLAN 3.11): Set a clip's speed-ramp curve — undoable via
  // ChangeSpeedCurveCommand; the command listener re-syncs the engine.
  void setClipSpeedCurve(String clipId, List<SpeedRampPoint> curve) {
    if (_disposed) return;
    commandHistory.execute(
      ChangeSpeedCurveCommand(clipId: clipId, newCurve: curve),
      project,
    );
    notifyListeners();
  }

  // v1.1.0 (PLAN 3.4): Set a clip's picture-in-picture geometry — undoable
  // (one entry per drag gesture via coalescing).
  void setClipPip(String clipId,
      {double x = 0.0,
      double y = 0.0,
      double w = 1.0,
      double h = 1.0,
      double rotation = 0.0}) {
    if (_disposed) return;
    commandHistory.execute(
      ChangePipCommand(
        clipId: clipId,
        newX: x.clamp(0.0, 1.0),
        newY: y.clamp(0.0, 1.0),
        newW: w.clamp(0.01, 1.0),
        newH: h.clamp(0.01, 1.0),
        newRotation: rotation,
        gestureId: _propertyGestureCounter,
      ),
      project,
    );
    notifyListeners();
  }

  void undo() {
    if (_disposed) return;
    // v1.0.1: Capture the description BEFORE undoing — after undo the
    // stack top changes and lastUndoDescription would report the wrong item.
    final undoneDesc = commandHistory.lastUndoDescription;
    if (commandHistory.undo(project)) {
      _statusMessage = 'Undo: ${undoneDesc ?? ""}';
      notifyListeners();
    }
  }

  void redo() {
    if (_disposed) return;
    // v1.0.1: Capture the description BEFORE redoing — after redo the
    // stack top changes and lastRedoDescription would report the wrong item.
    final redoneDesc = commandHistory.lastRedoDescription;
    if (commandHistory.redo(project)) {
      _statusMessage = 'Redo: ${redoneDesc ?? ""}';
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
    _engineSyncDirty = false;
    // v1.1.0 (PLAN 3.7): Waveform peaks are timeline-specific.
    _engine.clearTimelineWaveformCache();
    // v0.8.0: Drop all native clips — the new project starts empty.
    if (_engine.isReady) _engine.clearClips();
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
      _engineSyncDirty = false;
      // v1.1.0 (PLAN 3.7): Waveform peaks are timeline-specific.
      _engine.clearTimelineWaveformCache();
      // v0.8.0: Drop ALL native clips first — ids are reassigned from 1 on
      // load, so clips of the previous project beyond the new project's clip
      // count would otherwise survive as invisible ghost clips on the engine
      // timeline (they are never removed by the differential sync).
      if (_engine.isReady) _engine.clearClips();
      // v0.8.0: Rebuild the native timeline from the loaded project.
      syncTimelineToEngine();
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

    // Ctrl+G = Group selected clips — v1.0.0: advertised but never handled.
    if (ctrl && key == LogicalKeyboardKey.keyG) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        ungroupSelectedClips();
      } else {
        groupSelectedClips();
      }
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
    // v0.8.0: Keep the native timeline in sync with every command (add/remove/
    // move/trim/split/filter/property) — deferred once per event-loop turn.
    _markEngineSync();
    // v1.1.0 (PLAN 3.7): The timeline waveform reflects the actual timeline —
    // any timeline mutation invalidates the cached peaks.
    _engine.clearTimelineWaveformCache();
  }

  void _startAutoSave() {
    _autoSaveTimer?.cancel();
    // v1.0.1: Track in-flight state so a slow auto-save (>60s) doesn't
    // overlap with the next tick — two concurrent saves could race on
    // _cleanOldAutoSaves and produce more than the 5-file cap.
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
      if (_autoSaveInProgress) return; // Skip this tick, previous still running
      _autoSaveInProgress = true;
      try {
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
      } finally {
        _autoSaveInProgress = false;
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
    // v1.0.1: Dispose the engine BEFORE calling super.dispose() so any
    // final notifications from the engine are still delivered to listeners.
    _engine.dispose();
    super.dispose();
  }
}

