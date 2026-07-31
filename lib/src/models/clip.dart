import 'dart:ui';

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

  /// v0.7.0: Color correction properties (mapped to C++ applyColorCorrection)
  double colorExposure;      // -1.0 to 1.0
  double colorContrast;      // -1.0 to 1.0
  double colorHighlights;    // -1.0 to 1.0
  double colorShadows;       // -1.0 to 1.0
  double colorTemperature;   // -1.0 to 1.0
  double colorTint;          // -1.0 to 1.0
  double colorVibrance;      // -1.0 to 1.0
  double colorSaturation;    // -1.0 to 1.0

  /// Volume for this clip (0.0 - 2.0).
  double volume;

  /// Whether this clip is currently selected.
  bool isSelected;

  /// Clip type for visual differentiation.
  ClipType type;

  /// Playback speed multiplier (0.25x - 4.0x).
  double speed;

  /// Opacity (0.0 - 1.0).
  double opacity;

  /// v0.7.0: Text overlay properties (only used when type == text)
  String textContent;
  String textFont;
  double textFontSize;
  int textColorValue;
  bool textBold;
  bool textItalic;
  bool textUnderline;
  double textStrokeWidth;
  int textStrokeColorValue;
  bool textShadow;
  int textBackgroundColorValue;
  int textAlignment; // 0=left, 1=center, 2=right
  bool textGradient;

  /// v0.7.0: Sticker properties (only used when type == sticker)
  double stickerScale;
  double stickerRotation; // degrees

  /// v0.7.0: Group/lock
  String? groupId;
  bool isLocked;

  // v0.7.0: Color getter/setter helpers (convert from int ARGB)
  Color get textColor => Color(textColorValue);
  set textColor(Color c) => textColorValue = c.toARGB32();

  Color get textStrokeColor => Color(textStrokeColorValue);
  set textStrokeColor(Color c) => textStrokeColorValue = c.toARGB32();

  Color get textBackgroundColor => Color(textBackgroundColorValue);
  set textBackgroundColor(Color c) => textBackgroundColorValue = c.toARGB32();

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
    this.colorExposure = 0.0,
    this.colorContrast = 0.0,
    this.colorHighlights = 0.0,
    this.colorShadows = 0.0,
    this.colorTemperature = 0.0,
    this.colorTint = 0.0,
    this.colorVibrance = 0.0,
    this.colorSaturation = 0.0,
    this.volume = 1.0,
    this.isSelected = false,
    this.type = ClipType.video,
    this.speed = 1.0,
    this.opacity = 1.0,
    this.textContent = '',
    this.textFont = 'Segoe UI',
    this.textFontSize = 48.0,
    this.textColorValue = 0xFFFFFFFF,
    bool? textBold,
    bool? textItalic,
    bool? textUnderline,
    this.textStrokeWidth = 0.0,
    this.textStrokeColorValue = 0xFF000000,
    this.textShadow = false,
    this.textBackgroundColorValue = 0x00000000,
    this.textAlignment = 1,
    this.textGradient = false,
    this.stickerScale = 1.0,
    this.stickerRotation = 0.0,
    this.groupId,
    this.isLocked = false,
  })  : sourceOutMs = sourceOutMs ?? durationMs,
        textBold = textBold ?? false,
        textItalic = textItalic ?? false,
        textUnderline = textUnderline ?? false;

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
    double? speed,
    double? opacity,
    String? textContent,
    String? textFont,
    double? textFontSize,
    Color? textColor,
    bool? textBold,
    bool? textItalic,
    bool? textUnderline,
    double? textStrokeWidth,
    Color? textStrokeColor,
    bool? textShadow,
    Color? textBackgroundColor,
    int? textAlignment,
    bool? textGradient,
    double? stickerScale,
    double? stickerRotation,
    String? groupId,
    bool? isLocked,
    // v0.7.0: color correction
    double? colorExposure,
    double? colorContrast,
    double? colorHighlights,
    double? colorShadows,
    double? colorTemperature,
    double? colorTint,
    double? colorVibrance,
    double? colorSaturation,
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
      speed: speed ?? this.speed,
      opacity: opacity ?? this.opacity,
      textContent: textContent ?? this.textContent,
      textFont: textFont ?? this.textFont,
      textFontSize: textFontSize ?? this.textFontSize,
      textColorValue: textColor?.toARGB32() ?? textColorValue,
      textBold: textBold ?? this.textBold,
      textItalic: textItalic ?? this.textItalic,
      textUnderline: textUnderline ?? this.textUnderline,
      textStrokeWidth: textStrokeWidth ?? this.textStrokeWidth,
      textStrokeColorValue: textStrokeColor?.toARGB32() ?? textStrokeColorValue,
      textShadow: textShadow ?? this.textShadow,
      textBackgroundColorValue: textBackgroundColor?.toARGB32() ?? textBackgroundColorValue,
      textAlignment: textAlignment ?? this.textAlignment,
      textGradient: textGradient ?? this.textGradient,
      stickerScale: stickerScale ?? this.stickerScale,
      stickerRotation: stickerRotation ?? this.stickerRotation,
      groupId: groupId ?? this.groupId,
      isLocked: isLocked ?? this.isLocked,
      colorExposure: colorExposure ?? this.colorExposure,
      colorContrast: colorContrast ?? this.colorContrast,
      colorHighlights: colorHighlights ?? this.colorHighlights,
      colorShadows: colorShadows ?? this.colorShadows,
      colorTemperature: colorTemperature ?? this.colorTemperature,
      colorTint: colorTint ?? this.colorTint,
      colorVibrance: colorVibrance ?? this.colorVibrance,
      colorSaturation: colorSaturation ?? this.colorSaturation,
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
        'speed': speed,
        'opacity': opacity,
        'textContent': textContent,
        'textFont': textFont,
        'textFontSize': textFontSize,
        'textColorValue': textColor.toARGB32(),
        'textBold': textBold,
        'textItalic': textItalic,
        'textUnderline': textUnderline,
        'textStrokeWidth': textStrokeWidth,
        'textStrokeColorValue': textStrokeColor.toARGB32(),
        'textShadow': textShadow,
        'textBackgroundColorValue': textBackgroundColor.toARGB32(),
        'textAlignment': textAlignment,
        'textGradient': textGradient,
        'stickerScale': stickerScale,
        'stickerRotation': stickerRotation,
        'groupId': groupId,
        'isLocked': isLocked,
        // v0.7.0: color correction
        'colorExposure': colorExposure,
        'colorContrast': colorContrast,
        'colorHighlights': colorHighlights,
        'colorShadows': colorShadows,
        'colorTemperature': colorTemperature,
        'colorTint': colorTint,
        'colorVibrance': colorVibrance,
        'colorSaturation': colorSaturation,
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
        type: ClipType.values[(json['type'] as int?)?.clamp(0, ClipType.values.length - 1) ?? 0],
        speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
        opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
        textContent: json['textContent'] as String? ?? '',
        textFont: json['textFont'] as String? ?? 'Segoe UI',
        textFontSize: (json['textFontSize'] as num?)?.toDouble() ?? 48.0,
        textColorValue: (json['textColorValue'] as int?) ?? 0xFFFFFFFF,
        textBold: json['textBold'] as bool? ?? false,
        textItalic: json['textItalic'] as bool? ?? false,
        textUnderline: json['textUnderline'] as bool? ?? false,
        textStrokeWidth: (json['textStrokeWidth'] as num?)?.toDouble() ?? 0.0,
        textStrokeColorValue: (json['textStrokeColorValue'] as int?) ?? 0xFF000000,
        textShadow: json['textShadow'] as bool? ?? false,
        textBackgroundColorValue: (json['textBackgroundColorValue'] as int?) ?? 0x00000000,
        textAlignment: json['textAlignment'] as int? ?? 1,
        textGradient: json['textGradient'] as bool? ?? false,
        stickerScale: (json['stickerScale'] as num?)?.toDouble() ?? 1.0,
        stickerRotation: (json['stickerRotation'] as num?)?.toDouble() ?? 0.0,
        groupId: json['groupId'] as String?,
        isLocked: json['isLocked'] as bool? ?? false,
        // v0.7.0: color correction
        colorExposure: (json['colorExposure'] as num?)?.toDouble() ?? 0.0,
        colorContrast: (json['colorContrast'] as num?)?.toDouble() ?? 0.0,
        colorHighlights: (json['colorHighlights'] as num?)?.toDouble() ?? 0.0,
        colorShadows: (json['colorShadows'] as num?)?.toDouble() ?? 0.0,
        colorTemperature: (json['colorTemperature'] as num?)?.toDouble() ?? 0.0,
        colorTint: (json['colorTint'] as num?)?.toDouble() ?? 0.0,
        colorVibrance: (json['colorVibrance'] as num?)?.toDouble() ?? 0.0,
        colorSaturation: (json['colorSaturation'] as num?)?.toDouble() ?? 0.0,
      );

  @override
  String toString() => 'Clip($displayName, track=$trackIndex, '
      '${timelineStartMs}ms-${timelineEndMs}ms)';
}

enum ClipType { video, audio, image, text, overlay, sticker }
