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

  /// Get the currently selected clip (if any).
  Clip? get selectedClip {
    for (final track in tracks) {
      for (final clip in track.clips) {
        if (clip.isSelected) return clip;
      }
    }
    return null;
  }

  /// Deselect all clips.
  void deselectAll() {
    for (final track in tracks) {
      for (final clip in track.clips) {
        clip.isSelected = false;
      }
    }
  }

  /// Select a clip by ID.
  void selectClip(String clipId) {
    deselectAll();
    for (final track in tracks) {
      for (final clip in track.clips) {
        if (clip.id == clipId) {
          clip.isSelected = true;
          return;
        }
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
        version: json['version'] as String? ?? '0.3.0',
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'] as String)
            : null,
        modifiedAt: json['modifiedAt'] != null
            ? DateTime.parse(json['modifiedAt'] as String)
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
