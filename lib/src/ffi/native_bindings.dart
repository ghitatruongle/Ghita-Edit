import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// Opaque struct pointer
base class GhitaEngineContext extends Opaque {}

// ========== C Function Signatures & Dart Types ==========

// Lifecycle
typedef CGhitaEngineCreate = Pointer<GhitaEngineContext> Function();
typedef DartGhitaEngineCreate = Pointer<GhitaEngineContext> Function();

typedef CGhitaEngineDestroy = Void Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineDestroy = void Function(Pointer<GhitaEngineContext> ctx);

typedef CGhitaEngineInit = Int32 Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineInit = int Function(Pointer<GhitaEngineContext> ctx);

// Media
typedef CGhitaEngineLoadMedia = Int32 Function(Pointer<GhitaEngineContext> ctx, Pointer<Utf8> filePath);
typedef DartGhitaEngineLoadMedia = int Function(Pointer<GhitaEngineContext> ctx, Pointer<Utf8> filePath);

typedef CGhitaEngineGetDurationMs = Int64 Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineGetDurationMs = int Function(Pointer<GhitaEngineContext> ctx);

typedef CGhitaEngineGetMediaWidth = Int32 Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineGetMediaWidth = int Function(Pointer<GhitaEngineContext> ctx);

typedef CGhitaEngineGetMediaHeight = Int32 Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineGetMediaHeight = int Function(Pointer<GhitaEngineContext> ctx);

// Playback
typedef CGhitaEnginePlay = Void Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEnginePlay = void Function(Pointer<GhitaEngineContext> ctx);

typedef CGhitaEnginePause = Void Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEnginePause = void Function(Pointer<GhitaEngineContext> ctx);

typedef CGhitaEngineIsPlaying = Bool Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineIsPlaying = bool Function(Pointer<GhitaEngineContext> ctx);

typedef CGhitaEngineSeek = Void Function(Pointer<GhitaEngineContext> ctx, Int64 positionMs);
typedef DartGhitaEngineSeek = void Function(Pointer<GhitaEngineContext> ctx, int positionMs);

typedef CGhitaEngineGetPositionMs = Int64 Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineGetPositionMs = int Function(Pointer<GhitaEngineContext> ctx);

// Audio & FX
typedef CGhitaEngineSetVolume = Void Function(Pointer<GhitaEngineContext> ctx, Float volume);
typedef DartGhitaEngineSetVolume = void Function(Pointer<GhitaEngineContext> ctx, double volume);

typedef CGhitaEngineApplyFilter = Void Function(Pointer<GhitaEngineContext> ctx, Int32 filterType, Float intensity);
typedef DartGhitaEngineApplyFilter = void Function(Pointer<GhitaEngineContext> ctx, int filterType, double intensity);

// Rendering
typedef CGhitaEngineRenderFrameRgba = Bool Function(Pointer<GhitaEngineContext> ctx, Pointer<Uint8> outBuffer, Int32 width, Int32 height);
typedef DartGhitaEngineRenderFrameRgba = bool Function(Pointer<GhitaEngineContext> ctx, Pointer<Uint8> outBuffer, int width, int height);

// Version
typedef CGhitaEngineGetVersion = Pointer<Utf8> Function();
typedef DartGhitaEngineGetVersion = Pointer<Utf8> Function();

// ========== Timeline / Clip (v0.2.0) ==========
typedef CGhitaEngineAddClip = Int32 Function(Pointer<GhitaEngineContext> ctx, Pointer<Utf8> filePath, Int64 startMs, Int64 durationMs, Int32 trackIndex);
typedef DartGhitaEngineAddClip = int Function(Pointer<GhitaEngineContext> ctx, Pointer<Utf8> filePath, int startMs, int durationMs, int trackIndex);

typedef CGhitaEngineRemoveClip = Int32 Function(Pointer<GhitaEngineContext> ctx, Int32 clipId);
typedef DartGhitaEngineRemoveClip = int Function(Pointer<GhitaEngineContext> ctx, int clipId);

typedef CGhitaEngineGetClipCount = Int32 Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineGetClipCount = int Function(Pointer<GhitaEngineContext> ctx);

typedef CGhitaEngineSetClipPosition = Int32 Function(Pointer<GhitaEngineContext> ctx, Int32 clipId, Int64 startMs);
typedef DartGhitaEngineSetClipPosition = int Function(Pointer<GhitaEngineContext> ctx, int clipId, int startMs);

typedef CGhitaEngineSetClipFilter = Int32 Function(Pointer<GhitaEngineContext> ctx, Int32 clipId, Int32 filterType, Float intensity);
typedef DartGhitaEngineSetClipFilter = int Function(Pointer<GhitaEngineContext> ctx, int clipId, int filterType, double intensity);

typedef CGhitaEngineSetClipTransition = Bool Function(Pointer<GhitaEngineContext> ctx, Int32 clipId, Int32 transitionType, Int32 durationMs);
typedef DartGhitaEngineSetClipTransition = bool Function(Pointer<GhitaEngineContext> ctx, int clipId, int transitionType, int durationMs);

// ========== Export Pipeline (v0.2.0) ==========
typedef CGhitaEngineStartExport = Int32 Function(Pointer<GhitaEngineContext> ctx, Pointer<Utf8> outputPath, Int32 width, Int32 height, Int32 fps);
typedef DartGhitaEngineStartExport = int Function(Pointer<GhitaEngineContext> ctx, Pointer<Utf8> outputPath, int width, int height, int fps);

typedef CGhitaEngineGetExportProgress = Float Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineGetExportProgress = double Function(Pointer<GhitaEngineContext> ctx);

typedef CGhitaEngineIsExporting = Bool Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineIsExporting = bool Function(Pointer<GhitaEngineContext> ctx);

typedef CGhitaEngineCancelExport = Void Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineCancelExport = void Function(Pointer<GhitaEngineContext> ctx);

// Audio Waveform (v0.3.0)
typedef CGhitaEngineGetAudioWaveform = Bool Function(Pointer<GhitaEngineContext> ctx, Pointer<Float> outSamples, Int32 sampleCount);
typedef DartGhitaEngineGetAudioWaveform = bool Function(Pointer<GhitaEngineContext> ctx, Pointer<Float> outSamples, int sampleCount);

// ========== v0.4.5 New API ==========

// Media info
typedef CGhitaEngineGetMediaInfo = Pointer<Utf8> Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineGetMediaInfo = Pointer<Utf8> Function(Pointer<GhitaEngineContext> ctx);

// Available filters
typedef CGhitaEngineGetAvailableFilters = Pointer<Utf8> Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineGetAvailableFilters = Pointer<Utf8> Function(Pointer<GhitaEngineContext> ctx);

// Extended export
typedef CGhitaEngineStartExportEx = Int32 Function(
  Pointer<GhitaEngineContext> ctx,
  Pointer<Utf8> outputPath,
  Int32 width, Int32 height, Int32 fps,
  Pointer<Utf8> codec, Int64 bitrate, Bool includeAudio,
);
typedef DartGhitaEngineStartExportEx = int Function(
  Pointer<GhitaEngineContext> ctx,
  Pointer<Utf8> outputPath,
  int width, int height, int fps,
  Pointer<Utf8> codec, int bitrate, bool includeAudio,
);

// Export file size
typedef CGhitaEngineGetExportFileSize = Int64 Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineGetExportFileSize = int Function(Pointer<GhitaEngineContext> ctx);

// Keyframes
typedef CGhitaEngineAddClipKeyframe = Int32 Function(Pointer<GhitaEngineContext> ctx, Int32 clipId, Int64 timeMs, Float value);
typedef DartGhitaEngineAddClipKeyframe = int Function(Pointer<GhitaEngineContext> ctx, int clipId, int timeMs, double value);

typedef CGhitaEngineClearClipKeyframes = Int32 Function(Pointer<GhitaEngineContext> ctx, Int32 clipId);
typedef DartGhitaEngineClearClipKeyframes = int Function(Pointer<GhitaEngineContext> ctx, int clipId);

// FFmpeg availability
typedef CGhitaEngineHasFFmpeg = Bool Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineHasFFmpeg = bool Function(Pointer<GhitaEngineContext> ctx);

// ========== v0.5.5 New API ==========

// Playback rate
typedef CGhitaEngineSetPlaybackRate = Void Function(Pointer<GhitaEngineContext> ctx, Float rate);
typedef DartGhitaEngineSetPlaybackRate = void Function(Pointer<GhitaEngineContext> ctx, double rate);

typedef CGhitaEngineGetPlaybackRate = Float Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineGetPlaybackRate = double Function(Pointer<GhitaEngineContext> ctx);

// Keyframe interpolation
typedef CGhitaEngineSetClipKeyframeInterpolation = Int32 Function(Pointer<GhitaEngineContext> ctx, Int32 clipId, Int32 interpolationType);
typedef DartGhitaEngineSetClipKeyframeInterpolation = int Function(Pointer<GhitaEngineContext> ctx, int clipId, int interpolationType);

typedef CGhitaEngineGetClipKeyframeInterpolation = Int32 Function(Pointer<GhitaEngineContext> ctx, Int32 clipId);
typedef DartGhitaEngineGetClipKeyframeInterpolation = int Function(Pointer<GhitaEngineContext> ctx, int clipId);

// Text overlay rendering
typedef CGhitaEngineRenderTextOverlay = Bool Function(
  Pointer<GhitaEngineContext> ctx,
  Pointer<Uint8> outBuffer, Int32 width, Int32 height,
  Pointer<Utf8> text, Int32 fontSize, Float r, Float g, Float b, Float a
);
typedef DartGhitaEngineRenderTextOverlay = bool Function(
  Pointer<GhitaEngineContext> ctx,
  Pointer<Uint8> outBuffer, int width, int height,
  Pointer<Utf8> text, int fontSize, double r, double g, double b, double a
);

// ========== v0.7.0 New API ==========

// Color correction
typedef CGhitaEngineApplyColorCorrection = Void Function(
  Pointer<GhitaEngineContext> ctx, Int32 clipId,
  Float exposure, Float contrast, Float highlights, Float shadows,
  Float temperature, Float tint, Float vibrance, Float saturation
);
typedef DartGhitaEngineApplyColorCorrection = void Function(
  Pointer<GhitaEngineContext> ctx, int clipId,
  double exposure, double contrast, double highlights, double shadows,
  double temperature, double tint, double vibrance, double saturation
);

// Keyframe bezier
typedef CGhitaEngineSetKeyframeBezier = Int32 Function(
  Pointer<GhitaEngineContext> ctx, Int32 clipId, Int32 keyframeIndex,
  Float cp1x, Float cp1y, Float cp2x, Float cp2y
);
typedef DartGhitaEngineSetKeyframeBezier = int Function(
  Pointer<GhitaEngineContext> ctx, int clipId, int keyframeIndex,
  double cp1x, double cp1y, double cp2x, double cp2y
);

// PIP rendering
typedef CGhitaEngineRenderPip = Bool Function(
  Pointer<GhitaEngineContext> ctx, Int32 overlayClipId,
  Float x, Float y, Float width, Float height, Float rotation
);
typedef DartGhitaEngineRenderPip = bool Function(
  Pointer<GhitaEngineContext> ctx, int overlayClipId,
  double x, double y, double width, double height, double rotation
);

// Thumbnail extraction
typedef CGhitaEngineGetThumbnail = Pointer<Uint8> Function(
  Pointer<GhitaEngineContext> ctx, Int32 clipId, Int32 timeMs, Int32 width, Int32 height
);
typedef DartGhitaEngineGetThumbnail = Pointer<Uint8> Function(
  Pointer<GhitaEngineContext> ctx, int clipId, int timeMs, int width, int height
);

// New filter types (v0.7.0)
typedef CGhitaEngineSetFilterPreset = Void Function(
  Pointer<GhitaEngineContext> ctx, Int32 clipId, Int32 filterType, Float intensity
);
typedef DartGhitaEngineSetFilterPreset = void Function(
  Pointer<GhitaEngineContext> ctx, int clipId, int filterType, double intensity
);

// Audio waveform peaks for timeline
typedef CGhitaEngineGetAudioWaveformPeaks = Bool Function(
  Pointer<GhitaEngineContext> ctx, Pointer<Float> outSamples, Int32 sampleCount
);
typedef DartGhitaEngineGetAudioWaveformPeaks = bool Function(
  Pointer<GhitaEngineContext> ctx, Pointer<Float> outSamples, int sampleCount
);

// ========== Bindings Class ==========

class GhitaNativeBindings {
  static final GhitaNativeBindings instance = GhitaNativeBindings._internal();
  late DynamicLibrary _lib;
  bool _initialized = false;

  // Lifecycle
  late DartGhitaEngineCreate createEngine;
  late DartGhitaEngineDestroy destroyEngine;
  late DartGhitaEngineInit initEngine;

  // Media
  late DartGhitaEngineLoadMedia loadMedia;
  late DartGhitaEngineGetDurationMs getDurationMs;
  late DartGhitaEngineGetMediaWidth getMediaWidth;
  late DartGhitaEngineGetMediaHeight getMediaHeight;

  // Playback
  late DartGhitaEnginePlay play;
  late DartGhitaEnginePause pause;
  late DartGhitaEngineIsPlaying isPlaying;
  late DartGhitaEngineSeek seek;
  late DartGhitaEngineGetPositionMs getPositionMs;

  // Audio & FX
  late DartGhitaEngineSetVolume setVolume;
  late DartGhitaEngineApplyFilter applyFilter;

  // Rendering
  late DartGhitaEngineRenderFrameRgba renderFrameRgba;

  // Version
  late DartGhitaEngineGetVersion getVersion;

  // Timeline / Clip (v0.2.0)
  late DartGhitaEngineAddClip addClip;
  late DartGhitaEngineRemoveClip removeClip;
  late DartGhitaEngineGetClipCount getClipCount;
  late DartGhitaEngineSetClipPosition setClipPosition;
  late DartGhitaEngineSetClipFilter setClipFilter;

  // Timeline / Clip — Transitions (v0.4.0)
  late DartGhitaEngineSetClipTransition setClipTransition;

  // Export (v0.2.0)
  late DartGhitaEngineStartExport startExport;
  late DartGhitaEngineGetExportProgress getExportProgress;
  late DartGhitaEngineIsExporting isExporting;
  late DartGhitaEngineCancelExport cancelExport;

  // Audio Waveform (v0.3.0)
  late DartGhitaEngineGetAudioWaveform getAudioWaveform;

  // v0.4.5 New bindings
  late DartGhitaEngineGetMediaInfo getMediaInfo;
  late DartGhitaEngineGetAvailableFilters getAvailableFilters;
  late DartGhitaEngineStartExportEx startExportEx;
  late DartGhitaEngineGetExportFileSize getExportFileSize;
  late DartGhitaEngineAddClipKeyframe addClipKeyframe;
  late DartGhitaEngineClearClipKeyframes clearClipKeyframes;
  late DartGhitaEngineHasFFmpeg hasFFmpeg;

  // v0.5.5 New bindings
  late DartGhitaEngineSetPlaybackRate setPlaybackRate;
  late DartGhitaEngineGetPlaybackRate getPlaybackRate;
  late DartGhitaEngineSetClipKeyframeInterpolation setClipKeyframeInterpolation;
  late DartGhitaEngineGetClipKeyframeInterpolation getClipKeyframeInterpolation;
  late DartGhitaEngineRenderTextOverlay renderTextOverlay;

  // v0.7.0 New bindings
  late DartGhitaEngineApplyColorCorrection applyColorCorrection;
  late DartGhitaEngineSetKeyframeBezier setKeyframeBezier;
  late DartGhitaEngineRenderPip renderPip;
  late DartGhitaEngineGetThumbnail getThumbnail;
  late DartGhitaEngineSetFilterPreset setFilterPreset;
  late DartGhitaEngineGetAudioWaveformPeaks getAudioWaveformPeaks;

  GhitaNativeBindings._internal() {
    _loadLibrary();
  }

  void _loadLibrary() {
    if (_initialized) return;

    try {
      _lib = _resolveLibraryPath();
    } catch (_) {
      try {
        _lib = DynamicLibrary.process();
      } catch (e) {
        throw StateError('Cannot open ghita_engine native library: $e');
      }
    }

    _bindFunctions();
    _initialized = true;
  }

  DynamicLibrary _resolveLibraryPath() {
    if (Platform.isWindows) {
      final candidates = <String>[
        'ghita_engine.dll',
        'libghita_engine.dll',
        '${Directory.current.path}\\native_engine\\build\\libghita_engine.dll',
        '${Directory.current.path}\\build\\windows\\x64\\runner\\Debug\\ghita_engine.dll',
        '${Directory.current.path}\\build\\windows\\x64\\runner\\Release\\ghita_engine.dll',
        '${Directory(Platform.resolvedExecutable).parent.path}\\ghita_engine.dll',
        '${Directory(Platform.resolvedExecutable).parent.path}\\libghita_engine.dll',
      ];
      for (final path in candidates) {
        try {
          return DynamicLibrary.open(path);
        } catch (_) {
          continue;
        }
      }
      throw StateError('ghita_engine.dll not found in any expected location');
    } else if (Platform.isAndroid) {
      return DynamicLibrary.open('libghita_engine.so');
    } else if (Platform.isMacOS) {
      final candidates = <String>[
        'libghita_engine.dylib',
        '${Directory.current.path}/native_engine/build/libghita_engine.dylib',
        '${Directory(Platform.resolvedExecutable).parent.path}/libghita_engine.dylib',
        '/usr/local/lib/libghita_engine.dylib',
      ];
      for (final path in candidates) {
        try {
          return DynamicLibrary.open(path);
        } catch (_) {
          continue;
        }
      }
      throw StateError('libghita_engine.dylib not found in any expected location');
    } else if (Platform.isLinux) {
      final candidates = <String>[
        'libghita_engine.so',
        '${Directory.current.path}/native_engine/build/libghita_engine.so',
        '${Directory(Platform.resolvedExecutable).parent.path}/libghita_engine.so',
        '/usr/local/lib/libghita_engine.so',
      ];
      for (final path in candidates) {
        try {
          return DynamicLibrary.open(path);
        } catch (_) {
          continue;
        }
      }
      throw StateError('libghita_engine.so not found in any expected location');
    }
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }

  void _bindFunctions() {
    // Lifecycle
    createEngine = _lib.lookupFunction<CGhitaEngineCreate, DartGhitaEngineCreate>('ghita_engine_create');
    destroyEngine = _lib.lookupFunction<CGhitaEngineDestroy, DartGhitaEngineDestroy>('ghita_engine_destroy');
    initEngine = _lib.lookupFunction<CGhitaEngineInit, DartGhitaEngineInit>('ghita_engine_init');

    // Media
    loadMedia = _lib.lookupFunction<CGhitaEngineLoadMedia, DartGhitaEngineLoadMedia>('ghita_engine_load_media');
    getDurationMs = _lib.lookupFunction<CGhitaEngineGetDurationMs, DartGhitaEngineGetDurationMs>('ghita_engine_get_duration_ms');
    getMediaWidth = _lib.lookupFunction<CGhitaEngineGetMediaWidth, DartGhitaEngineGetMediaWidth>('ghita_engine_get_media_width');
    getMediaHeight = _lib.lookupFunction<CGhitaEngineGetMediaHeight, DartGhitaEngineGetMediaHeight>('ghita_engine_get_media_height');

    // Playback
    play = _lib.lookupFunction<CGhitaEnginePlay, DartGhitaEnginePlay>('ghita_engine_play');
    pause = _lib.lookupFunction<CGhitaEnginePause, DartGhitaEnginePause>('ghita_engine_pause');
    isPlaying = _lib.lookupFunction<CGhitaEngineIsPlaying, DartGhitaEngineIsPlaying>('ghita_engine_is_playing');
    seek = _lib.lookupFunction<CGhitaEngineSeek, DartGhitaEngineSeek>('ghita_engine_seek');
    getPositionMs = _lib.lookupFunction<CGhitaEngineGetPositionMs, DartGhitaEngineGetPositionMs>('ghita_engine_get_position_ms');

    // Audio & FX
    setVolume = _lib.lookupFunction<CGhitaEngineSetVolume, DartGhitaEngineSetVolume>('ghita_engine_set_volume');
    applyFilter = _lib.lookupFunction<CGhitaEngineApplyFilter, DartGhitaEngineApplyFilter>('ghita_engine_apply_filter');

    // Rendering
    renderFrameRgba = _lib.lookupFunction<CGhitaEngineRenderFrameRgba, DartGhitaEngineRenderFrameRgba>('ghita_engine_render_frame_rgba');

    // Version
    getVersion = _lib.lookupFunction<CGhitaEngineGetVersion, DartGhitaEngineGetVersion>('ghita_engine_get_version');

    // Timeline / Clip (v0.2.0)
    addClip = _lib.lookupFunction<CGhitaEngineAddClip, DartGhitaEngineAddClip>('ghita_engine_add_clip');
    removeClip = _lib.lookupFunction<CGhitaEngineRemoveClip, DartGhitaEngineRemoveClip>('ghita_engine_remove_clip');
    getClipCount = _lib.lookupFunction<CGhitaEngineGetClipCount, DartGhitaEngineGetClipCount>('ghita_engine_get_clip_count');
    setClipPosition = _lib.lookupFunction<CGhitaEngineSetClipPosition, DartGhitaEngineSetClipPosition>('ghita_engine_set_clip_position');
    setClipFilter = _lib.lookupFunction<CGhitaEngineSetClipFilter, DartGhitaEngineSetClipFilter>('ghita_engine_set_clip_filter');

    // Timeline / Clip — Transitions (v0.4.0)
    setClipTransition = _lib.lookupFunction<CGhitaEngineSetClipTransition, DartGhitaEngineSetClipTransition>('ghita_engine_set_clip_transition');

    // Export (v0.2.0)
    startExport = _lib.lookupFunction<CGhitaEngineStartExport, DartGhitaEngineStartExport>('ghita_engine_start_export');
    getExportProgress = _lib.lookupFunction<CGhitaEngineGetExportProgress, DartGhitaEngineGetExportProgress>('ghita_engine_get_export_progress');
    isExporting = _lib.lookupFunction<CGhitaEngineIsExporting, DartGhitaEngineIsExporting>('ghita_engine_is_exporting');
    cancelExport = _lib.lookupFunction<CGhitaEngineCancelExport, DartGhitaEngineCancelExport>('ghita_engine_cancel_export');

    // Audio Waveform (v0.3.0)
    getAudioWaveform = _lib.lookupFunction<CGhitaEngineGetAudioWaveform, DartGhitaEngineGetAudioWaveform>('ghita_engine_get_audio_waveform');

    // v0.4.5 New bindings
    getMediaInfo = _lib.lookupFunction<CGhitaEngineGetMediaInfo, DartGhitaEngineGetMediaInfo>('ghita_engine_get_media_info');
    getAvailableFilters = _lib.lookupFunction<CGhitaEngineGetAvailableFilters, DartGhitaEngineGetAvailableFilters>('ghita_engine_get_available_filters');
    startExportEx = _lib.lookupFunction<CGhitaEngineStartExportEx, DartGhitaEngineStartExportEx>('ghita_engine_start_export_ex');
    getExportFileSize = _lib.lookupFunction<CGhitaEngineGetExportFileSize, DartGhitaEngineGetExportFileSize>('ghita_engine_get_export_file_size');
    addClipKeyframe = _lib.lookupFunction<CGhitaEngineAddClipKeyframe, DartGhitaEngineAddClipKeyframe>('ghita_engine_add_clip_keyframe');
    clearClipKeyframes = _lib.lookupFunction<CGhitaEngineClearClipKeyframes, DartGhitaEngineClearClipKeyframes>('ghita_engine_clear_clip_keyframes');
    hasFFmpeg = _lib.lookupFunction<CGhitaEngineHasFFmpeg, DartGhitaEngineHasFFmpeg>('ghita_engine_has_ffmpeg');

    // v0.5.5 New bindings
    setPlaybackRate = _lib.lookupFunction<CGhitaEngineSetPlaybackRate, DartGhitaEngineSetPlaybackRate>('ghita_engine_set_playback_rate');
    getPlaybackRate = _lib.lookupFunction<CGhitaEngineGetPlaybackRate, DartGhitaEngineGetPlaybackRate>('ghita_engine_get_playback_rate');
    setClipKeyframeInterpolation = _lib.lookupFunction<CGhitaEngineSetClipKeyframeInterpolation, DartGhitaEngineSetClipKeyframeInterpolation>('ghita_engine_set_clip_keyframe_interpolation');
    getClipKeyframeInterpolation = _lib.lookupFunction<CGhitaEngineGetClipKeyframeInterpolation, DartGhitaEngineGetClipKeyframeInterpolation>('ghita_engine_get_clip_keyframe_interpolation');
    renderTextOverlay = _lib.lookupFunction<CGhitaEngineRenderTextOverlay, DartGhitaEngineRenderTextOverlay>('ghita_engine_render_text_overlay');

    // v0.7.0 New bindings
    applyColorCorrection = _lib.lookupFunction<CGhitaEngineApplyColorCorrection, DartGhitaEngineApplyColorCorrection>('ghita_engine_apply_color_correction');
    setKeyframeBezier = _lib.lookupFunction<CGhitaEngineSetKeyframeBezier, DartGhitaEngineSetKeyframeBezier>('ghita_engine_set_keyframe_bezier');
    renderPip = _lib.lookupFunction<CGhitaEngineRenderPip, DartGhitaEngineRenderPip>('ghita_engine_render_pip');
    getThumbnail = _lib.lookupFunction<CGhitaEngineGetThumbnail, DartGhitaEngineGetThumbnail>('ghita_engine_get_thumbnail');
    setFilterPreset = _lib.lookupFunction<CGhitaEngineSetFilterPreset, DartGhitaEngineSetFilterPreset>('ghita_engine_set_filter_preset');
    getAudioWaveformPeaks = _lib.lookupFunction<CGhitaEngineGetAudioWaveformPeaks, DartGhitaEngineGetAudioWaveformPeaks>('ghita_engine_get_audio_waveform_peaks');
  }
}
