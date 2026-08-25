import 'dart:convert';
import 'track.dart';
import 'clip.dart';
import '../core/version.dart';

/// Represents an entire Ghita Edit project — serializable to/from JSON.
class Project {
  String name;
  String filePath;
  String version;
  DateTime createdAt;
  DateTime modifiedAt;

  List<Track> tracks;

  /// Project-level settings.
  int outputWidth;
  int outputHeight;
  int outputFps;
  String outputFormat;

  /// Global playback position (not saved, runtime only).
  int playheadMs;

  /// v0.5.5: Multi-select support via Set of clip IDs
  final Set<String> _selectedClipIds = <String>{};

  /// v1.5.0-T3 (P4): LIVE selected ids (clips that still exist) maintained by
  /// [_syncClipSelectionFlags] so hot UI paths get O(1) membership/count —
  /// the old selectedClips scan ran per-clip per-build at ~30fps playback.
  final Set<String> _liveSelectedIds = <String>{};

  /// O(1) membership test for the timeline build loop.
  bool isClipSelected(String clipId) => _liveSelectedIds.contains(clipId);

  Project({
    required this.name,
    this.filePath = '',
    String? version,
    DateTime? createdAt,
    DateTime? modifiedAt,
    List<Track>? tracks,
    this.outputWidth = 1920,
    this.outputHeight = 1080,
    this.outputFps = 60,
    this.outputFormat = 'mp4',
    this.playheadMs = 0,
  })  : version = version ?? flutterVersion,
        createdAt = createdAt ?? DateTime.now(),
        modifiedAt = modifiedAt ?? DateTime.now(),
        tracks = tracks ?? _defaultTracks();

  /// Total project duration = longest track.
  int get totalDurationMs {
    if (tracks.isEmpty) return 60000;
    final maxTrackDuration = tracks
        .map((t) => t.durationMs)
        .reduce((a, b) => a > b ? a : b);
    return maxTrackDuration > 0 ? maxTrackDuration : 60000;
  }

  /// Get all clips across all tracks.
  List<Clip> get allClips => tracks.expand((t) => t.clips).toList();

  /// Get the currently selected clip (first in selection set).
  Clip? get selectedClip {
    for (final id in _selectedClipIds) {
      for (final track in tracks) {
        for (final clip in track.clips) {
          if (clip.id == id) return clip;
        }
      }
    }
    return null;
  }

  /// All currently selected clips, in selection order.
  List<Clip> get selectedClips {
    final result = <Clip>[];
    for (final id in _selectedClipIds) {
      for (final track in tracks) {
        for (final clip in track.clips) {
          if (clip.id == id) result.add(clip);
        }
      }
    }
    return result;
  }

  /// Number of currently selected clips.
  // v0.7.8: Count only LIVE selections — stale ids of deleted/split clips no
  // longer inflate the count (previously: count>0 with nothing selectable).
  // v1.5.0-T3 (P4): O(1) via the live-id set instead of materializing the
  // full selectedClips list on every status-bar/timeline read.
  int get selectedClipCount => _liveSelectedIds.length;

  /// v0.7.8: Drop ids of clips that no longer exist (deleted or split), and
  /// resync the per-clip isSelected flags.
  void pruneSelection() {
    final existing = <String>{};
    for (final track in tracks) {
      for (final clip in track.clips) {
        existing.add(clip.id);
      }
    }
    final before = _selectedClipIds.length;
    _selectedClipIds.removeWhere((id) => !existing.contains(id));
    if (_selectedClipIds.length != before) {
      _syncClipSelectionFlags();
    }
  }

  /// Deselect all clips.
  void deselectAll() {
    _selectedClipIds.clear();
    _liveSelectedIds.clear();
    for (final track in tracks) {
      for (final clip in track.clips) {
        clip.isSelected = false;
      }
    }
  }

  /// Select all clips across all tracks.
  void selectAll() {
    _selectedClipIds.clear();
    for (final track in tracks) {
      for (final clip in track.clips) {
        _selectedClipIds.add(clip.id);
      }
    }
    _syncClipSelectionFlags();
  }

  /// Select a clip by ID, clearing previous selection (single-select mode).
  void selectClip(String clipId) {
    _selectedClipIds.clear();
    _selectedClipIds.add(clipId);
    _syncClipSelectionFlags();
  }

  /// Toggle a clip in/out of the current selection (multi-select).
  void toggleClipSelection(String clipId) {
    if (_selectedClipIds.contains(clipId)) {
      _selectedClipIds.remove(clipId);
    } else {
      _selectedClipIds.add(clipId);
    }
    _syncClipSelectionFlags();
  }

  /// Select a range of clips between two clip IDs (Shift+click range select).
  void selectRange(String fromClipId, String toClipId) {
    // v1.0.1: Validate IDs BEFORE deselecting — previously a bad ID
    // silently cleared the existing selection and left nothing selected.
    final allClips = _allClipsSortedByTime;
    final fromIdx = allClips.indexWhere((c) => c.id == fromClipId);
    final toIdx = allClips.indexWhere((c) => c.id == toClipId);
    if (fromIdx == -1 || toIdx == -1) return;
    deselectAll();
    final start = fromIdx < toIdx ? fromIdx : toIdx;
    final end = fromIdx < toIdx ? toIdx : fromIdx;
    for (int i = start; i <= end; i++) {
      _selectedClipIds.add(allClips[i].id);
    }
    _syncClipSelectionFlags();
  }

  /// Add clip IDs to selection (for marquee selection).
  void addToSelection(Set<String> clipIds) {
    _selectedClipIds.addAll(clipIds);
    _syncClipSelectionFlags();
  }

  List<Clip> get _allClipsSortedByTime {
    final all = allClips;
    all.sort((a, b) => a.timelineStartMs.compareTo(b.timelineStartMs));
    return all;
  }

  /// Sync _selectedClipIds → clip.isSelected for UI widgets that read isSelected.
  void _syncClipSelectionFlags() {
    _liveSelectedIds.clear();
    for (final track in tracks) {
      for (final clip in track.clips) {
        final sel = _selectedClipIds.contains(clip.id);
        clip.isSelected = sel;
        if (sel) _liveSelectedIds.add(clip.id);
      }
    }
  }

  /// Find the track containing a clip.
  Track? trackForClip(String clipId) {
    for (final track in tracks) {
      if (track.clips.any((c) => c.id == clipId)) {
        return track;
      }
    }
    return null;
  }

  /// Dynamically add a new track to the project (v0.3.5).
  void addTrack(Track track) {
    if (!tracks.any((t) => t.id == track.id)) {
      tracks.add(track);
      markModified();
    }
  }

  /// Dynamically remove a track by ID (v0.3.5).
  bool removeTrack(String trackId) {
    final index = tracks.indexWhere((t) => t.id == trackId);
    if (index != -1) {
      tracks.removeAt(index);
      // v1.0.1: Prune selection IDs of clips that were on the removed track
      // — otherwise stale IDs linger and selection state becomes inconsistent.
      pruneSelection();
      markModified();
      return true;
    }
    return false;
  }

  /// Delete the selected clip(s).
  List<Clip> deleteSelected() {
    final deleted = <Clip>[];
    for (final track in tracks) {
      final selected = track.clips.where((c) => c.isSelected).toList();
      for (final clip in selected) {
        track.clips.remove(clip);
        deleted.add(clip);
      }
    }
    // v1.0.1: Prune stale selection IDs — after deletion the IDs still
    // linger in _selectedClipIds, making hasClipboard/multi-select state
    // inconsistent (count returns 0 but set is non-empty).
    pruneSelection();
    return deleted;
  }

  /// Mark project as modified.
  void markModified() {
    modifiedAt = DateTime.now();
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'version': version,
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt.toIso8601String(),
        'tracks': tracks.map((t) => t.toJson()).toList(),
        'outputWidth': outputWidth,
        'outputHeight': outputHeight,
        'outputFps': outputFps,
        'outputFormat': outputFormat,
      };

  factory Project.fromJson(Map<String, dynamic> json) => Project(
        name: json['name'] as String? ?? 'Untitled',
        // v1.0.0: legacy project files without a version field used to be
        // stamped '0.3.0' (stale). Stamp the current app version instead so
        // the project's version reflects when it was loaded, not 0.3.0.
        version: json['version'] as String? ?? flutterVersion,
        // v1.0.1: Defensive parsing — a corrupt date string would throw
        // TypeError here and fail the whole load. Fall back to null.
        createdAt: json['createdAt'] is String
            ? DateTime.tryParse(json['createdAt'] as String)
            : null,
        modifiedAt: json['modifiedAt'] is String
            ? DateTime.tryParse(json['modifiedAt'] as String)
            : null,
        tracks: json['tracks'] != null
            ? (json['tracks'] as List)
                .map((t) => Track.fromJson(t as Map<String, dynamic>))
                .toList()
            : null,
        outputWidth: json['outputWidth'] as int? ?? 1920,
        outputHeight: json['outputHeight'] as int? ?? 1080,
        outputFps: json['outputFps'] as int? ?? 60,
        outputFormat: json['outputFormat'] as String? ?? 'mp4',
      );

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory Project.fromJsonString(String jsonStr) =>
      Project.fromJson(json.decode(jsonStr) as Map<String, dynamic>);

  static List<Track> _defaultTracks() => [
        Track(id: 'track_video_1', name: 'Video Track 1', type: TrackType.video),
        Track(id: 'track_overlay_1', name: 'Text / Overlay', type: TrackType.overlay),
        Track(id: 'track_audio_1', name: 'Audio Track 1', type: TrackType.audio),
      ];
}
