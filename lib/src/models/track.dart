import 'clip.dart';

/// Represents a track on the timeline (video, audio, overlay, etc.)
class Track {
  final String id;
  String name;
  TrackType type;
  List<Clip> clips;
  bool isMuted;
  bool isLocked;
  bool isVisible;
  double volume;

  Track({
    required this.id,
    required this.name,
    required this.type,
    List<Clip>? clips,
    this.isMuted = false,
    this.isLocked = false,
    this.isVisible = true,
    this.volume = 1.0,
  }) : clips = clips ?? [];

  /// Get the total duration of this track (end of last clip).
  int get durationMs {
    if (clips.isEmpty) return 0;
    return clips.map((c) => c.timelineEndMs).reduce((a, b) => a > b ? a : b);
  }

  /// Add a clip at the earliest available position (no overlap).
  void addClipAtEnd(Clip clip) {
    final endOfTrack = durationMs;
    clip.timelineStartMs = endOfTrack;
    clip.trackIndex = _trackIndexFromType(type);
    clips.add(clip);
    _sortClips();
  }

  /// Add a clip at a specific position, shifting others if needed.
  void addClipAt(Clip clip, int positionMs) {
    clip.timelineStartMs = positionMs;
    clip.trackIndex = _trackIndexFromType(type);

    // Resolve overlaps by shifting subsequent clips
    _resolveOverlaps(clip);
    clips.add(clip);
    _sortClips();
  }

  /// Remove a clip by its ID.
  Clip? removeClip(String clipId) {
    final index = clips.indexWhere((c) => c.id == clipId);
    if (index == -1) return null;
    return clips.removeAt(index);
  }

  /// Get clip at a given timeline position.
  Clip? clipAtPosition(int positionMs) {
    for (final clip in clips) {
      if (positionMs >= clip.timelineStartMs && positionMs < clip.timelineEndMs) {
        return clip;
      }
    }
    return null;
  }

  /// Split the clip at the given position.
  bool splitClipAt(int positionMs) {
    final clip = clipAtPosition(positionMs);
    if (clip == null) return false;

    final parts = clip.splitAt(positionMs);
    if (parts == null) return false;

    final index = clips.indexOf(clip);
    clips.removeAt(index);
    clips.insert(index, parts[0]);
    clips.insert(index + 1, parts[1]);
    return true;
  }

  /// Move a clip to a new position.
  void moveClip(String clipId, int newStartMs) {
    final index = clips.indexWhere((c) => c.id == clipId);
    if (index == -1) return; // Clip not found, do nothing
    clips[index].timelineStartMs = newStartMs.clamp(0, 0x7FFFFFFFFFFF);
    _sortClips();
  }

  /// Trim clip start (adjust in-point).
  void trimClipStart(String clipId, int newStartMs) {
    final clip = clips.firstWhere((c) => c.id == clipId);
    final delta = newStartMs - clip.timelineStartMs;
    if (delta >= clip.durationMs) return; // Can't trim past end

    clip.timelineStartMs = newStartMs;
    clip.sourceInMs += delta;
    clip.durationMs -= delta;
  }

  /// Trim clip end (adjust out-point).
  void trimClipEnd(String clipId, int newEndMs) {
    final clip = clips.firstWhere((c) => c.id == clipId);
    final newDuration = newEndMs - clip.timelineStartMs;
    if (newDuration <= 0) return;

    clip.durationMs = newDuration;
    clip.sourceOutMs = clip.sourceInMs + newDuration;
  }

  void _sortClips() {
    clips.sort((a, b) => a.timelineStartMs.compareTo(b.timelineStartMs));
  }

  void _resolveOverlaps(Clip newClip) {
    for (final existing in clips) {
      if (existing.timelineStartMs >= newClip.timelineStartMs &&
          existing.timelineStartMs < newClip.timelineEndMs) {
        // Shift this clip to after the new clip
        existing.timelineStartMs = newClip.timelineEndMs;
      }
    }
  }

  int _trackIndexFromType(TrackType t) {
    switch (t) {
      case TrackType.video:
        return 0;
      case TrackType.overlay:
        return 1;
      case TrackType.audio:
        return 2;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.index,
        'clips': clips.map((c) => c.toJson()).toList(),
        'isMuted': isMuted,
        'isLocked': isLocked,
        'isVisible': isVisible,
        'volume': volume,
      };

  factory Track.fromJson(Map<String, dynamic> json) => Track(
        id: json['id'] as String,
        name: json['name'] as String,
        type: TrackType.values[json['type'] as int],
        clips: (json['clips'] as List)
            .map((c) => Clip.fromJson(c as Map<String, dynamic>))
            .toList(),
        isMuted: json['isMuted'] as bool? ?? false,
        isLocked: json['isLocked'] as bool? ?? false,
        isVisible: json['isVisible'] as bool? ?? true,
        volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
      );
}

enum TrackType { video, overlay, audio }
