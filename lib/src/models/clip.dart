import 'dart:ui';

/// v1.1.0 (PLAN 3.1): One keyframe of a clip animation. Mirrors the native
/// struct: property 0=opacity, 1=position offset (fraction of frame),
/// 2=scale, 3=rotation (stored; render support limited), 4=filter intensity.
/// interpolation 0=linear, 1=step, 2=bezier (control points normalized to
/// the segment toward the next keyframe).
class KeyframeData {
  final int timeMs;
  final double value;
  final int property;
  final int interpolation;
  final double cp1x;
  final double cp1y;
  final double cp2x;
  final double cp2y;

  const KeyframeData({
    required this.timeMs,
    required this.value,
    this.property = 0,
    this.interpolation = 0,
    this.cp1x = 0,
    this.cp1y = 0,
    this.cp2x = 0,
    this.cp2y = 0,
  });

  Map<String, dynamic> toJson() => {
        't': timeMs,
        'v': value,
        'p': property,
        'i': interpolation,
        'c1x': cp1x,
        'c1y': cp1y,
        'c2x': cp2x,
        'c2y': cp2y,
      };

  factory KeyframeData.fromJson(Map<String, dynamic> json) => KeyframeData(
        timeMs: json['t'] as int? ?? 0,
        value: (json['v'] as num?)?.toDouble() ?? 0.0,
        property: json['p'] as int? ?? 0,
        interpolation: json['i'] as int? ?? 0,
        cp1x: (json['c1x'] as num?)?.toDouble() ?? 0.0,
        cp1y: (json['c1y'] as num?)?.toDouble() ?? 0.0,
        cp2x: (json['c2x'] as num?)?.toDouble() ?? 0.0,
        cp2y: (json['c2y'] as num?)?.toDouble() ?? 0.0,
      );
}

/// v1.1.0 (PLAN 3.11): One speed-ramp point — normalized timeline position
/// [t] in 0..1 mapped to a playback speed multiplier.
class SpeedRampPoint {
  final double t;
  final double speed;

  const SpeedRampPoint(this.t, this.speed);

  Map<String, dynamic> toJson() => {'t': t, 's': speed};

  factory SpeedRampPoint.fromJson(Map<String, dynamic> json) => SpeedRampPoint(
        (json['t'] as num?)?.toDouble() ?? 0.0,
        (json['s'] as num?)?.toDouble() ?? 1.0,
      );
}

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

  /// v1.1.0 (PLAN 3.1): Keyframe animation (property-aware, bezier capable).
  List<KeyframeData> keyframes;

  /// v1.1.0 (PLAN 3.4): Picture-in-picture geometry — fractions of the
  /// output frame. The default (w=1, h=1, x=0, y=0) fills the frame.
  double pipX;
  double pipY;
  double pipW;
  double pipH;
  double pipRotation;

  /// v1.1.0 (PLAN 3.11): Speed-ramp curve — normalized positions 0..1 to
  /// playback multipliers. Empty = constant [speed].
  List<SpeedRampPoint> speedCurve;

  /// v0.7.0: Group/lock
  String? groupId;
  bool isLocked;

  /// v0.7.8: Transition applied to this clip (0 = none; engine enum order:
  /// None, FadeIn, FadeOut, Crossfade, Slide, Wipe, Zoom, Dissolve, Radial).
  int transitionType;
  int transitionDurationMs;

  /// v1.5.0 T3 (#4): blend mode — 0 Normal, 1 Multiply, 2 Screen, 3 Overlay, 4 Add.
  int blendMode;

  /// v1.5.0 T3 (#5): geometric mask — 0 none, 1 rect, 2 ellipse, 3 diamond,
  /// 4 star, 5 heart, 6 cinematic bars (with feather/stroke).
  int maskType;
  double maskFeather;
  double maskStroke;

  /// v1.5.0 T3 (#7): pitch-preserving playback when speed != 1.
  bool maintainPitch;

  // v0.7.0: Color getter/setter helpers (convert from int ARGB)
  Color get textColor => Color(textColorValue);
  set textColor(Color c) => textColorValue = _clipColorArgb(c);

  Color get textStrokeColor => Color(textStrokeColorValue);
  set textStrokeColor(Color c) => textStrokeColorValue = _clipColorArgb(c);

  Color get textBackgroundColor => Color(textBackgroundColorValue);
  set textBackgroundColor(Color c) => textBackgroundColorValue = _clipColorArgb(c);

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
    this.transitionType = 0,
    this.transitionDurationMs = 500,
    this.blendMode = 0,
    this.maskType = 0,
    this.maskFeather = 0.0,
    this.maskStroke = 0.0,
    this.maintainPitch = false,
    this.keyframes = const [],
    this.speedCurve = const [],
    this.pipX = 0.0,
    this.pipY = 0.0,
    this.pipW = 1.0,
    this.pipH = 1.0,
    this.pipRotation = 0.0,
  })  : sourceOutMs = sourceOutMs ?? (sourceInMs + durationMs),
        textBold = textBold ?? false,
        textItalic = textItalic ?? false,
        textUnderline = textUnderline ?? false;

  /// Timeline end position in milliseconds.
  int get timelineEndMs => timelineStartMs + durationMs;

  // v0.7.8: Monotonic counter — timestamp-only IDs collided when multiple
  // clips were created within the same millisecond, breaking selection,
  // undo and delete targeting (they all match clips by id).
  static int _idCounter = 0;

  static String nextId() =>
      'clip_${DateTime.now().millisecondsSinceEpoch}_${_idCounter++}';

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
    // v0.7.8: transition
    int? transitionType,
    int? transitionDurationMs,
    // v1.5.0 T3: blend mode / mask / maintain-pitch
    int? blendMode,
    int? maskType,
    double? maskFeather,
    double? maskStroke,
    bool? maintainPitch,
    // v1.1.0 (PLAN 3): keyframes / pip / speed curve
    List<KeyframeData>? keyframes,
    List<SpeedRampPoint>? speedCurve,
    double? pipX,
    double? pipY,
    double? pipW,
    double? pipH,
    double? pipRotation,
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
      textColorValue: _clipColorArgb(textColor ?? const Color(0x00000000)),
      textBold: textBold ?? this.textBold,
      textItalic: textItalic ?? this.textItalic,
      textUnderline: textUnderline ?? this.textUnderline,
      textStrokeWidth: textStrokeWidth ?? this.textStrokeWidth,
      textStrokeColorValue: _clipColorArgb(textStrokeColor ?? const Color(0x00000000)),
      textShadow: textShadow ?? this.textShadow,
      textBackgroundColorValue: _clipColorArgb(textBackgroundColor ?? const Color(0x00000000)),
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
      transitionType: transitionType ?? this.transitionType,
      transitionDurationMs: transitionDurationMs ?? this.transitionDurationMs,
      blendMode: blendMode ?? this.blendMode,
      maskType: maskType ?? this.maskType,
      maskFeather: maskFeather ?? this.maskFeather,
      maskStroke: maskStroke ?? this.maskStroke,
      maintainPitch: maintainPitch ?? this.maintainPitch,
      keyframes: keyframes ?? this.keyframes,
      speedCurve: speedCurve ?? this.speedCurve,
      pipX: pipX ?? this.pipX,
      pipY: pipY ?? this.pipY,
      pipW: pipW ?? this.pipW,
      pipH: pipH ?? this.pipH,
      pipRotation: pipRotation ?? this.pipRotation,
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

    // v0.7.9: Defensive guard — a boundary position (or degenerate clip)
    // must never produce a zero-duration half, which cannot render and
    // crashes export.
    if (leftDuration <= 0 || rightDuration <= 0) {
      return null;
    }

    // v1.0.1: Account for playback speed when mapping timeline positions
    // to source positions. With speed != 1.0, the source range covered by
    // a timeline segment is speed * duration (e.g., 2x speed covers 2x the
    // source material in the same timeline duration) — matches the engine's
    // own mapping (offset = (pos - start) * speed, window = duration * speed).
    // The right half keeps the parent's source OUT-POINT so the two halves
    // always partition the parent's source window exactly — independently
    // recomputing each half's span from duration * speed drifts by ±1ms per
    // split (round(333*1.5) + round(667*1.5) = 500 + 1001 ≠ 1500) and the
    // halves can extend past the media end on repeated splits.
    final safeSpeed = speed <= 0 ? 1.0 : speed;
    final availableSource = sourceOutMs - sourceInMs;
    // Clamp to the available source so a degenerate parent model (stale
    // sourceOutMs vs speed) never produces a right half that starts past
    // the parent's source end.
    final leftSourceSpan = (leftDuration * safeSpeed)
        .round()
        .clamp(0, availableSource < 0 ? 0 : availableSource);

    final left = copyWith(
      id: '${id}_L',
      durationMs: leftDuration,
      sourceOutMs: sourceInMs + leftSourceSpan,
    );

    final right = copyWith(
      id: '${id}_R',
      timelineStartMs: positionMs,
      durationMs: rightDuration,
      sourceInMs: sourceInMs + leftSourceSpan,
      sourceOutMs: sourceOutMs,
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
        'textColorValue': _clipColorArgb(textColor),
        'textBold': textBold,
        'textItalic': textItalic,
        'textUnderline': textUnderline,
        'textStrokeWidth': textStrokeWidth,
        'textStrokeColorValue': _clipColorArgb(textStrokeColor),
        'textShadow': textShadow,
        'textBackgroundColorValue': _clipColorArgb(textBackgroundColor),
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
        // v0.7.8: transition
        'transitionType': transitionType,
        'transitionDurationMs': transitionDurationMs,
        'blendMode': blendMode,
        'maskType': maskType,
        'maskFeather': maskFeather,
        'maskStroke': maskStroke,
        'maintainPitch': maintainPitch,
        // v1.1.0 (PLAN 3): keyframes / pip / speed curve (optional fields)
        'keyframes': keyframes.map((k) => k.toJson()).toList(),
        'speedCurve': speedCurve.map((p) => p.toJson()).toList(),
        'pipX': pipX,
        'pipY': pipY,
        'pipW': pipW,
        'pipH': pipH,
        'pipRotation': pipRotation,
      };

  factory Clip.fromJson(Map<String, dynamic> json) => Clip(
        id: json['id'] as String,
        sourceFilePath: json['sourceFilePath'] as String,
        displayName: json['displayName'] as String,
        // v0.7.9: Defensive — missing timelineStartMs used to throw TypeError.
        timelineStartMs: json['timelineStartMs'] as int? ?? 0,
        // v0.7.9: Null-safe — a corrupt/very old file missing durationMs
        // used to throw TypeError here (hard cast of null).
        durationMs: json['durationMs'] as int? ?? 0,
        sourceInMs: json['sourceInMs'] as int? ?? 0,
        // v0.7.8: Legacy files without sourceOutMs defaulted to durationMs,
        // ignoring a trimmed in-point — use sourceInMs + durationMs instead.
        // v0.7.9: The `durationMs` cast could throw TypeError when the key was
        // missing entirely (corrupt/very old files) — both operands are now
        // null-safe so loading can never crash on a missing duration.
        sourceOutMs: json['sourceOutMs'] as int? ??
            ((json['sourceInMs'] as int? ?? 0) + (json['durationMs'] as int? ?? 0)),
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
        // v0.7.8: transition
        transitionType: json['transitionType'] as int? ?? 0,
        transitionDurationMs: json['transitionDurationMs'] as int? ?? 500,
        blendMode: json['blendMode'] as int? ?? 0,
        maskType: json['maskType'] as int? ?? 0,
        maskFeather: (json['maskFeather'] as num?)?.toDouble() ?? 0.0,
        maskStroke: (json['maskStroke'] as num?)?.toDouble() ?? 0.0,
        maintainPitch: json['maintainPitch'] as bool? ?? false,
        // v1.1.0 (PLAN 3): optional fields with safe defaults — old project
        // files without them load unchanged.
        keyframes: (json['keyframes'] as List<dynamic>?)
                ?.map((k) => KeyframeData.fromJson(k as Map<String, dynamic>))
                .toList() ??
            const [],
        speedCurve: (json['speedCurve'] as List<dynamic>?)
                ?.map((p) => SpeedRampPoint.fromJson(p as Map<String, dynamic>))
                .toList() ??
            const [],
        pipX: (json['pipX'] as num?)?.toDouble() ?? 0.0,
        pipY: (json['pipY'] as num?)?.toDouble() ?? 0.0,
        pipW: (json['pipW'] as num?)?.toDouble() ?? 1.0,
        pipH: (json['pipH'] as num?)?.toDouble() ?? 1.0,
        pipRotation: (json['pipRotation'] as num?)?.toDouble() ?? 0.0,
      );

  @override
  String toString() => 'Clip($displayName, track=$trackIndex, '
      '${timelineStartMs}ms-${timelineEndMs}ms)';
}

/// v1.0.0b (CI fix): Color.toARGB32() only exists on Flutter ≥ 3.29 — the CI
/// toolchain (Flutter 3.27, Dart 3.6) lacks it and `.value` is deprecated on
/// newer SDKs. Convert via the 0-1 channel components so this compiles and
/// analyzes cleanly on BOTH the CI and the local (3.44) toolchain.
int _clipColorArgb(Color c) =>
    (((c.a * 255).round() & 0xFF) << 24) |
    (((c.r * 255).round() & 0xFF) << 16) |
    (((c.g * 255).round() & 0xFF) << 8) |
    ((c.b * 255).round() & 0xFF);

enum ClipType { video, audio, image, text, overlay, sticker }
