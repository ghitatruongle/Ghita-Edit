/// Triple-Studio mode active in Ghita Edit v1.0.0.
enum StudioMode {
  /// 🎬 Pro Video Studio (CapCut & WinK level video editing)
  video,

  /// 🎙️ Pro Audio DAW Studio (Audacity & Audition level multi-track DAW sound editor)
  audioDaw,

  /// 🎨 Pro Photo Photoshop Studio (Photoshop level image & photo editor)
  photo,
}

extension StudioModeExtension on StudioMode {
  String get displayName {
    switch (this) {
      case StudioMode.video:
        return '🎬 Video Studio';
      case StudioMode.audioDaw:
        return '🎙️ Audio DAW Studio';
      case StudioMode.photo:
        return '🎨 Photo Editor Studio';
    }
  }

  String get description {
    switch (this) {
      case StudioMode.video:
        return 'Pro CapCut & WinK video timeline editor';
      case StudioMode.audioDaw:
        return 'Audacity & Audition multi-track sound DAW & FX';
      case StudioMode.photo:
        return 'Photoshop layer & color photo editing studio';
    }
  }
}
