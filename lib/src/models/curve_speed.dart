import 'dart:math' as math;

/// CapCut-style Speed Ramping Preset Types.
enum SpeedCurvePreset {
  standard,
  montage,
  hero,
  bulletTime,
  flashIn,
  flashOut,
  custom,
}

extension SpeedCurvePresetExtension on SpeedCurvePreset {
  String get displayName {
    switch (this) {
      case SpeedCurvePreset.standard:
        return 'Standard (Linear)';
      case SpeedCurvePreset.montage:
        return '⚡ Montage';
      case SpeedCurvePreset.hero:
        return '🦸 Hero Moment';
      case SpeedCurvePreset.bulletTime:
        return '🎯 Bullet Time';
      case SpeedCurvePreset.flashIn:
        return '🚀 Flash In';
      case SpeedCurvePreset.flashOut:
        return '💨 Flash Out';
      case SpeedCurvePreset.custom:
        return '✏️ Custom Bezier';
    }
  }

  /// Evaluates normalized speed multiplier at position [t] in [0..1].
  double evaluateSpeedAt(double t, {List<double>? customPoints}) {
    final clampedT = t.clamp(0.0, 1.0);
    switch (this) {
      case SpeedCurvePreset.standard:
        return 1.0;
      case SpeedCurvePreset.montage:
        // Slow -> Fast -> Slow -> Fast
        return 0.5 + 2.5 * math.pow(math.sin(clampedT * math.pi * 2), 2);
      case SpeedCurvePreset.hero:
        // Fast start -> Ultra slow middle -> Fast end
        if (clampedT < 0.3) return 3.0 - clampedT * 8.0;
        if (clampedT < 0.7) return 0.25;
        return 0.25 + (clampedT - 0.7) * 7.0;
      case SpeedCurvePreset.bulletTime:
        // 1x -> 0.1x -> 1x
        final dist = (clampedT - 0.5).abs();
        return 0.1 + 2.0 * math.pow(dist * 2.0, 2);
      case SpeedCurvePreset.flashIn:
        // 4x -> 1x
        return 1.0 + 3.0 * math.pow(1.0 - clampedT, 3);
      case SpeedCurvePreset.flashOut:
        // 1x -> 4x
        return 1.0 + 3.0 * math.pow(clampedT, 3);
      case SpeedCurvePreset.custom:
        if (customPoints != null && customPoints.isNotEmpty) {
          final idx = (clampedT * (customPoints.length - 1)).floor();
          final nextIdx = (idx + 1).clamp(0, customPoints.length - 1);
          final frac = (clampedT * (customPoints.length - 1)) - idx;
          return customPoints[idx] * (1.0 - frac) + customPoints[nextIdx] * frac;
        }
        return 1.0;
    }
  }
}
