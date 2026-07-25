/// Represents a media clip on the timeline.
/// Each clip references a source media file and defines an in/out range.
class Clip {
  final String id;
  String sourceFilePath;
  String displayName;

  /// Position on the timeline in milliseconds.
  int timelineStartMs;

  /// Duration of this clip on the timeline in milliseconds.
  int durationMs;

  /// Source in-point (where to start reading from the source file).
  int sourceInMs;

  /// Source out-point (where to stop reading from the source file).
  int sourceOutMs;

  /// Track index this clip belongs to.
  int trackIndex;

  /// Filter applied to this clip (0 = none).
  int filterType;
  double filterIntensity;

  /// Volume for this clip (0.0 - 2.0).
  double volume;

  /// Whether this clip is currently selected.
  bool isSelected;

  /// Clip type for visual differentiation.
  ClipType type;

  Clip({
    required this.id,
    required this.sourceFilePath,
    required this.displayName,
    required this.timelineStartMs,
    required this.durationMs,
    this.sourceInMs = 0,
    int? sourceOutMs,
    this.trackIndex = 0,
    this.filterType = 0,
    this.filterIntensity = 1.0,
    this.volume = 1.0,
    this.isSelected = false,
    this.type = ClipType.video,
  }) : sourceOutMs = sourceOutMs ?? durationMs;

  /// Timeline end position in milliseconds.
  int get timelineEndMs => timelineStartMs + durationMs;

  /// Create a copy of this clip with optional overrides.
  Clip copyWith({
    String? id,
    String? sourceFilePath,
    String? displayName,
    int? timelineStartMs,
    int? durationMs,
    int? sourceInMs,
    int? sourceOutMs,
    int? trackIndex,
    int? filterType,
    double? filterIntensity,
    double? volume,
    bool? isSelected,
    ClipType? type,
  }) {
    return Clip(
      id: id ?? this.id,
      sourceFilePath: sourceFilePath ?? this.sourceFilePath,
      displayName: displayName ?? this.displayName,
      timelineStartMs: timelineStartMs ?? this.timelineStartMs,
      durationMs: durationMs ?? this.durationMs,
      sourceInMs: sourceInMs ?? this.sourceInMs,
      sourceOutMs: sourceOutMs ?? this.sourceOutMs,
      trackIndex: trackIndex ?? this.trackIndex,
      filterType: filterType ?? this.filterType,
      filterIntensity: filterIntensity ?? this.filterIntensity,
      volume: volume ?? this.volume,
      isSelected: isSelected ?? this.isSelected,
      type: type ?? this.type,
    );
  }

  /// Split this clip at a given position (relative to timeline).
  /// Returns [leftClip, rightClip] or null if position is outside clip bounds.
  List<Clip>? splitAt(int positionMs) {
    if (positionMs <= timelineStartMs || positionMs >= timelineEndMs) {
      return null;
    }

    final splitPoint = positionMs - timelineStartMs;
    final leftDuration = splitPoint;
    final rightDuration = durationMs - splitPoint;

    final left = copyWith(
      id: '${id}_L',
      durationMs: leftDuration,
      sourceOutMs: sourceInMs + leftDuration,
    );

    final right = copyWith(
      id: '${id}_R',
      timelineStartMs: positionMs,
      durationMs: rightDuration,
      sourceInMs: sourceInMs + leftDuration,
    );

    return [left, right];
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sourceFilePath': sourceFilePath,
        'displayName': displayName,
        'timelineStartMs': timelineStartMs,
        'durationMs': durationMs,
        'sourceInMs': sourceInMs,
        'sourceOutMs': sourceOutMs,
        'trackIndex': trackIndex,
        'filterType': filterType,
        'filterIntensity': filterIntensity,
        'volume': volume,
        'type': type.index,
      };

  factory Clip.fromJson(Map<String, dynamic> json) => Clip(
        id: json['id'] as String,
        sourceFilePath: json['sourceFilePath'] as String,
        displayName: json['displayName'] as String,
        timelineStartMs: json['timelineStartMs'] as int,
        durationMs: json['durationMs'] as int,
        sourceInMs: json['sourceInMs'] as int? ?? 0,
        sourceOutMs: json['sourceOutMs'] as int?,
        trackIndex: json['trackIndex'] as int? ?? 0,
        filterType: json['filterType'] as int? ?? 0,
        filterIntensity: (json['filterIntensity'] as num?)?.toDouble() ?? 1.0,
        volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
        type: ClipType.values[(json['type'] as int?) ?? 0],
      );

  @override
  String toString() => 'Clip($displayName, track=$trackIndex, '
      '${timelineStartMs}ms-${timelineEndMs}ms)';
}

enum ClipType { video, audio, image, text, overlay }
