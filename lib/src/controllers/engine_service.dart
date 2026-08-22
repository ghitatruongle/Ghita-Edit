import 'dart:async';
import 'dart:ffi';
import 'dart:convert';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import '../ffi/native_bindings.dart';
import 'package:flutter/foundation.dart';

/// Manages the raw C++ engine lifecycle and native memory.
/// This class owns the FFI boundary — the controller should never call
/// native bindings directly for engine operations.
// v0.7.8: ChangeNotifier — the preview tick notifies listeners so the UI
// (playhead, timecode, frame) actually moves during playback. Previously
// nothing observed the engine and the preview stayed frozen while playing.
class EngineService extends ChangeNotifier {
  final GhitaNativeBindings? _bindings;
  Pointer<GhitaEngineContext>? _ctx;

  // Render frame buffer allocated via calloc.
  Pointer<Uint8>? _framePointer;
  Uint8List? _frameBytes;

  Timer? _renderTimer;
  bool _isRunning = false;
  bool _initializing = false;

  bool get isReady => _ctx != null && _ctx != nullptr;
  bool get isRunning => _isRunning;
  bool get isNativeLibraryLoaded => _nativeLibraryLoaded; // For fallback detection
  String engineVersion = '';

  // Public accessors for export dialog
  Pointer<GhitaEngineContext> get ctx => _ctx ?? nullptr;
  GhitaNativeBindings? get bindings => _bindings;

  // Properties sourced from native engine
  int _positionMs = 0;
  int get positionMs => _positionMs;

  int _durationMs = 60000;
  int get durationMs => _durationMs;

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  int _activeFilterType = 0;
  int get activeFilterType => _activeFilterType;

  double _filterIntensity = 1.0;
  double get filterIntensity => _filterIntensity;

  double _volume = 1.0;
  double get volume => _volume;

  // v0.4.5: FFmpeg availability
  bool _ffmpegAvailable = false;
  bool get ffmpegAvailable => _ffmpegAvailable;

  // v0.5.8: Export state tracking
  bool get isExporting {
    final bindings = _bindings;
    if (!isReady || bindings == null) return false;
    try {
      return bindings.isExporting(_ctx!);
    } catch (e) {
      debugPrint('[EngineService] Error checking export status: $e');
      return false;
    }
  }

  // v0.4.5: Cached media info
  Map<String, dynamic> _mediaInfo = {};
  Map<String, dynamic> get mediaInfo => _mediaInfo;

  // v0.4.5: Cached available filters
  List<Map<String, dynamic>> _availableFilters = [];
  List<Map<String, dynamic>> get availableFilters => _availableFilters;

  static const int renderWidth = 640;
  static const int renderHeight = 360;

  Uint8List? get frameBytes => _frameBytes;

  // v1.0.2: Monotonic frame generation — incremented every time a NEW frame
  // is rendered into _frameBytes (cache hits keep the previous frame and do
  // NOT bump it). Consumers (PreviewPlayer) use it to skip redundant
  // ui.decodeImageFromPixels calls when the frame content did not change.
  int _frameGeneration = 0;
  int get frameGeneration => _frameGeneration;

  EngineService({GhitaNativeBindings? bindings, bool skipNativeInit = false})
      : _bindings = bindings ?? (skipNativeInit ? null : _tryLoadBindings());

  bool _disposed = false;
  bool _nativeLibraryLoaded = false; // Track if native library was successfully loaded

  static GhitaNativeBindings? _tryLoadBindings() {
    try {
      return GhitaNativeBindings.instance;
    } catch (_) {
      return null;
    }
  }

  void _checkDisposed() {
    if (_disposed) {
      throw StateError('EngineService has been disposed');
    }
  }

  /// Initialize the native engine asynchronously and start the preview tick loop.
  Future<void> initialize() async {
    _checkDisposed();
    if (isReady) return;
    // v1.0.1: Guard against concurrent initialize() calls — if two callers
    // pass the `isReady` check before _ctx is set, both would create engine
    // contexts and the first would leak.
    if (_initializing) return;
    _initializing = true;
    try {
      await _doInitialize();
    } finally {
      _initializing = false;
    }
  }

  Future<void> _doInitialize() async {
    final bindings = _bindings;
    if (bindings == null) {
      debugPrint('[EngineService] No FFI bindings available — cannot initialize');
      // Set _nativeLibraryLoaded to false to indicate failure
      _nativeLibraryLoaded = false;
      return;
    }

    try {
      final ctx = bindings.createEngine();
      if (ctx == nullptr) {
        debugPrint('[EngineService] Failed to create native engine context');
        _ctx = null;
        // Fallback to demo mode
        _nativeLibraryLoaded = false;
        return;
      }

      final initResult = bindings.initEngine(ctx);
      if (initResult != 0) {
        bindings.destroyEngine(ctx);
        debugPrint('[EngineService] Engine initialization failed with code: $initResult');
        _ctx = null;
        return;
      }

      _ctx = ctx;

      // v0.4.5: Check FFmpeg availability
      try {
        _ffmpegAvailable = bindings.hasFFmpeg(ctx);
      } catch (_) {
        _ffmpegAvailable = false;
      }

      // v0.4.5: Load available filters
      try {
        _refreshAvailableFilters();
      } catch (_) {
        _availableFilters = [];
      }

      final verPtr = bindings.getVersion();
      if (verPtr != nullptr) {
        engineVersion = verPtr.toDartString();
      } else {
        engineVersion = 'Unknown';
      }

      // Mark as successfully loaded
      _nativeLibraryLoaded = true;

      // Allocate native buffer for preview frames
      // v1.0.1: calloc can return nullptr on OOM — don't start the tick
      // loop with a null buffer, the preview would silently die.
      _framePointer = calloc<Uint8>(renderWidth * renderHeight * 4);
      if (_framePointer == nullptr) {
        debugPrint('[EngineService] Failed to allocate frame buffer — preview disabled');
        // Engine is "ready" but preview won't run. This is a degraded mode.
        return;
      }
      _frameBytes = Uint8List(renderWidth * renderHeight * 4);

      _startTickLoop();
    } catch (e, st) {
      debugPrint('[EngineService] Initialization failed: $e\n$st');
      _ctx = null;
      // Fallback to demo mode
      _nativeLibraryLoaded = false;
      rethrow;
    }
  }

  // v0.4.5: Refresh available filters from native engine
  void _refreshAvailableFilters() {
    final bindings = _bindings;
    if (!isReady || bindings == null) return;
    try {
      final filterPtr = bindings.getAvailableFilters(_ctx!);
      if (filterPtr != nullptr) {
        final jsonStr = filterPtr.toDartString();
        final decoded = jsonDecode(jsonStr);
        if (decoded is List) {
          _availableFilters = decoded.cast<Map<String, dynamic>>();
        }
      }
    } catch (_) {
      // ignore — use cached default list
    }
  }

  // v0.4.5: Get media info JSON from native engine
  Map<String, dynamic> fetchMediaInfo() {
    final bindings = _bindings;
    if (!isReady || bindings == null) return {};
    try {
      final infoPtr = bindings.getMediaInfo(_ctx!);
      if (infoPtr != nullptr) {
        final jsonStr = infoPtr.toDartString();
        final decoded = jsonDecode(jsonStr);
        if (decoded is Map<String, dynamic>) {
          _mediaInfo = decoded;
          return _mediaInfo;
        }
      }
    } catch (_) {
      // ignore
    }
    return {};
  }

  void startPreview() {
    _checkDisposed();
    if (_isRunning || !isReady) return;
    _isRunning = true;
    _startTickLoop();
  }

  void stopPreview() {
    _isRunning = false;
    if (_renderTimer != null) {
      _renderTimer!.cancel();
      _renderTimer = null;
    }
    // v0.7.8: Do NOT free _framePointer here — it is allocated once by
    // initialize() and owned until dispose(). Freeing it on every stop meant
    // the preview tick loop died permanently (first tick saw a null pointer
    // and cancelled itself). dispose() below still frees it.
  }

  void play() {
    _checkDisposed();
    final bindings = _bindings;
    if (!isReady || bindings == null) return;
    // v1.0.3: Self-heal the preview tick loop. If a previous tick threw once,
    // the old code called stopPreview() and the loop was DEAD FOREVER — the
    // engine kept "playing" but the position only advanced inside
    // renderFrameRGBA, so nothing moved until the user manually seeked
    // (complaint: "bấm Play không chạy, kéo timeline mới chạy").
    if (!_isRunning) {
      debugPrint('[EngineService] play(): restarting preview tick loop');
      startPreview();
    }
    _isPlaying = true;
    bindings.play(_ctx!);
  }

  void pause() {
    _checkDisposed();
    final bindings = _bindings;
    if (!isReady || bindings == null) return;
    _isPlaying = false;
    bindings.pause(_ctx!);
  }

  void seek(int positionMs) {
    _checkDisposed();
    final bindings = _bindings;
    if (!isReady || bindings == null) return;
    // v1.0.3: Same self-heal as play() — one transient tick failure must not
    // leave the preview unresponsive until a resurrecting call.
    if (!_isRunning) {
      startPreview();
    }
    bindings.seek(_ctx!, positionMs);
    _positionMs = positionMs;

  }

  void setVolume(double val) {
    _checkDisposed();
    final clamped = val.clamp(0.0, 2.0);
    _volume = clamped;
    final bindings = _bindings;
    if (isReady && bindings != null) {
      bindings.setVolume(_ctx!, clamped);
    }
  }

  // v1.0.3: Noise suppression ("làm rõ âm thanh") — mirrors the DAW toggle to
  // the native mixer (DC blocker / low-cut on the preview mix). No-op on
  // engines that don't export the symbol.
  void setNoiseSuppress(bool enabled) {
    _checkDisposed();
    final bindings = _bindings;
    final fn = bindings?.setNoiseSuppress;
    if (!isReady || fn == null) return;
    try {
      fn(_ctx!, enabled ? 1 : 0);
    } catch (e) {
      debugPrint('[EngineService] setNoiseSuppress failed: $e');
    }
  }

  // ========== v1.1.0 (PLAN 3): Accuracy features ==========

  /// v1.1.0 (PLAN 3.1): Keyframe-aware insertion (property/interpolation/
  /// bezier). No-op (false) on engines without the symbol.
  bool addClipKeyframeEx(int clipId, int timeMs, double value, int property,
      int interpolation, double cp1x, double cp1y, double cp2x, double cp2y) {
    _checkDisposed();
    final bindings = _bindings;
    final fn = bindings?.addKeyframeEx;
    if (!isReady || fn == null || clipId <= 0) return false;
    try {
      return fn(_ctx!, clipId, timeMs, value, property, interpolation,
              cp1x, cp1y, cp2x, cp2y) == 0;
    } catch (e) {
      debugPrint('[EngineService] addClipKeyframeEx failed: $e');
      return false;
    }
  }

  /// v1.1.0 (PLAN 3.4): Picture-in-picture geometry (frame fractions).
  bool setClipPip(int clipId, double x, double y, double w, double h,
      double rotation) {
    _checkDisposed();
    final bindings = _bindings;
    final fn = bindings?.setClipPip;
    if (!isReady || fn == null || clipId <= 0) return false;
    try {
      return fn(_ctx!, clipId, x, y, w, h, rotation) == 0;
    } catch (e) {
      debugPrint('[EngineService] setClipPip failed: $e');
      return false;
    }
  }

  /// v1.1.0 (PLAN 3.11): Append a speed-ramp point (t normalized 0..1).
  bool addSpeedRampPoint(int clipId, double t, double speed) {
    _checkDisposed();
    final bindings = _bindings;
    final fn = bindings?.addSpeedRampPoint;
    if (!isReady || fn == null || clipId <= 0) return false;
    try {
      return fn(_ctx!, clipId, t, speed) == 0;
    } catch (e) {
      debugPrint('[EngineService] addSpeedRampPoint failed: $e');
      return false;
    }
  }

  // ========== v1.5.0 T3: Video Features ==========

  /// v1.5.0 T3 (#4): blend mode (0 Normal, 1 Multiply, 2 Screen, 3 Overlay, 4 Add).
  bool setClipBlendMode(int clipId, int blendMode) {
    _checkDisposed();
    final bindings = _bindings;
    final fn = bindings?.setClipBlendMode;
    if (!isReady || fn == null || clipId <= 0) return false;
    try {
      return fn(_ctx!, clipId, blendMode) == 0;
    } catch (e) {
      debugPrint('[EngineService] setClipBlendMode failed: $e');
      return false;
    }
  }

  /// v1.5.0 T3 (#5): geometric mask (0 none, 1 rect, 2 ellipse, 3 diamond,
  /// 4 star, 5 heart, 6 cinematic bars) with feather/stroke.
  bool setClipMask(int clipId, int maskType, double feather, double stroke) {
    _checkDisposed();
    final bindings = _bindings;
    final fn = bindings?.setClipMask;
    if (!isReady || fn == null || clipId <= 0) return false;
    try {
      return fn(_ctx!, clipId, maskType, feather, stroke) == 0;
    } catch (e) {
      debugPrint('[EngineService] setClipMask failed: $e');
      return false;
    }
  }

  /// v1.5.0 T3 (#7): pitch-preserving speed.
  bool setClipMaintainPitch(int clipId, bool enabled) {
    _checkDisposed();
    final bindings = _bindings;
    final fn = bindings?.setClipMaintainPitch;
    if (!isReady || fn == null || clipId <= 0) return false;
    try {
      return fn(_ctx!, clipId, enabled ? 1 : 0) == 0;
    } catch (e) {
      debugPrint('[EngineService] setClipMaintainPitch failed: $e');
      return false;
    }
  }

  /// v1.5.0 T3 (#8): text clip font family (GDI).
  bool setClipFont(int clipId, String family) {
    _checkDisposed();
    final bindings = _bindings;
    final fn = bindings?.setClipFont;
    if (!isReady || fn == null || clipId <= 0) return false;
    try {
      final ptr = family.toNativeUtf8();
      try {
        return fn(_ctx!, clipId, ptr) == 0;
      } finally {
        calloc.free(ptr);
      }
    } catch (e) {
      debugPrint('[EngineService] setClipFont failed: $e');
      return false;
    }
  }

  /// v1.5.0 T3 (#9): canvas background (0 solid, 1 gradient, 2 blur).
  void setCanvasBackground(int kind, int color, int color2) {
    _checkDisposed();
    final bindings = _bindings;
    final fn = bindings?.setCanvasBackground;
    if (!isReady || fn == null) return;
    try {
      fn(_ctx!, kind, color, color2);
    } catch (e) {
      debugPrint('[EngineService] setCanvasBackground failed: $e');
    }
  }

  /// v1.5.0 T3 (#10): bookmark markers on the ruler.
  int addBookmark(int timeMs, int color, String note) {
    _checkDisposed();
    final bindings = _bindings;
    final fn = bindings?.addBookmark;
    if (!isReady || fn == null) return -1;
    try {
      final ptr = note.toNativeUtf8();
      try {
        return fn(_ctx!, timeMs, color, ptr);
      } finally {
        calloc.free(ptr);
      }
    } catch (e) {
      debugPrint('[EngineService] addBookmark failed: $e');
      return -1;
    }
  }

  bool removeBookmark(int id) {
    _checkDisposed();
    final bindings = _bindings;
    final fn = bindings?.removeBookmark;
    if (!isReady || fn == null) return false;
    try {
      return fn(_ctx!, id) == 0;
    } catch (e) {
      debugPrint('[EngineService] removeBookmark failed: $e');
      return false;
    }
  }

  /// v1.5.0 T3 (#2): clone all keyframes of [srcClip] onto [dstClip].
  bool copyKeyframes(int srcClip, int dstClip) {
    _checkDisposed();
    final bindings = _bindings;
    final fn = bindings?.copyKeyframes;
    if (!isReady || fn == null || srcClip <= 0 || dstClip <= 0) return false;
    try {
      return fn(_ctx!, srcClip, dstClip) == 0;
    } catch (e) {
      debugPrint('[EngineService] copyKeyframes failed: $e');
      return false;
    }
  }

  /// v1.5.0 T3 (#11): parse an .srt/.vtt transcript into text clips.
  int importTranscript(String path, int trackIndex) {
    _checkDisposed();
    final bindings = _bindings;
    final fn = bindings?.importTranscript;
    if (!isReady || fn == null) return 0;
    try {
      final ptr = path.toNativeUtf8();
      try {
        return fn(_ctx!, ptr, trackIndex);
      } finally {
        calloc.free(ptr);
      }
    } catch (e) {
      debugPrint('[EngineService] importTranscript failed: $e');
      return 0;
    }
  }

  // ========== v1.5.0 T4: Audio Features ==========

  int addAudioEffect(int effectType, double p0, double p1, double p2, double p3) {
    _checkDisposed();
    final fn = _bindings?.addAudioEffect;
    if (!isReady || fn == null) return -1;
    try { return fn(_ctx!, effectType, p0, p1, p2, p3); } catch (e) { return -1; }
  }

  int removeAudioEffect(int index) {
    _checkDisposed();
    final fn = _bindings?.removeAudioEffect;
    if (!isReady || fn == null) return -1;
    try { return fn(_ctx!, index); } catch (e) { return -1; }
  }

  void clearAudioEffects() {
    _checkDisposed();
    final fn = _bindings?.clearAudioEffects;
    if (!isReady || fn == null) return;
    try { fn(_ctx!); } catch (_) {}
  }

  double getGainReductionDb() {
    _checkDisposed();
    final fn = _bindings?.getGainReductionDb;
    if (!isReady || fn == null) return 0.0;
    try { return fn(_ctx!); } catch (_) { return 0.0; }
  }

  List<double> getSpectrogram(int columns, int bins, int trackIndex) {
    _checkDisposed();
    final fn = _bindings?.getSpectrogram;
    if (!isReady || fn == null || columns <= 0 || bins <= 0) return const [];
    final count = columns * bins;
    final buf = calloc<Float>(count);
    try {
      if (fn(_ctx!, buf, columns, bins, trackIndex)) {
        return List.generate(count, (i) => buf[i]);
      }
      return const [];
    } catch (_) { return const []; } finally { calloc.free(buf); }
  }

  int addSpectralEdit(int startMs, int endMs, double loHz, double hiHz, double gainDb) {
    _checkDisposed();
    final fn = _bindings?.addSpectralEdit;
    if (!isReady || fn == null) return -1;
    try { return fn(_ctx!, startMs, endMs, loHz, hiHz, gainDb); } catch (e) { return -1; }
  }

  void clearSpectralEdits() {
    _checkDisposed();
    final fn = _bindings?.clearSpectralEdits;
    if (!isReady || fn == null) return;
    try { fn(_ctx!); } catch (_) {}
  }

  List<double> getTimelineRms(int count, int trackIndex) {
    _checkDisposed();
    final fn = _bindings?.getTimelineRms;
    if (!isReady || fn == null || count <= 0) return const [];
    final buf = calloc<Float>(count);
    try {
      if (fn(_ctx!, buf, count, trackIndex)) {
        return List.generate(count, (i) => buf[i]);
      }
      return const [];
    } catch (_) { return const []; } finally { calloc.free(buf); }
  }

  int detectTempo() {
    _checkDisposed();
    final fn = _bindings?.detectTempo;
    if (!isReady || fn == null) return 0;
    try { return fn(_ctx!); } catch (_) { return 0; }
  }

  void setTimeSignature(int num, int den) {
    _checkDisposed();
    final fn = _bindings?.setTimeSignature;
    if (!isReady || fn == null) return;
    try { fn(_ctx!, num, den); } catch (_) {}
  }

  List<int> getBeatTimes(int maxCount) {
    _checkDisposed();
    final fn = _bindings?.getBeatTimes;
    if (!isReady || fn == null || maxCount <= 0) return const [];
    final buf = calloc<Int64>(maxCount);
    try {
      final n = fn(_ctx!, buf, maxCount);
      if (n > 0) return List.generate(n, (i) => buf[i].toInt());
      return const [];
    } catch (_) { return const []; } finally { calloc.free(buf); }
  }

  void setLoopRegion(int startMs, int endMs, bool enabled) {
    _checkDisposed();
    final fn = _bindings?.setLoopRegion;
    if (!isReady || fn == null) return;
    try { fn(_ctx!, startMs, endMs, enabled ? 1 : 0); } catch (_) {}
  }

  int setClipPitch(int clipId, double semitones) {
    _checkDisposed();
    final fn = _bindings?.setClipPitch;
    if (!isReady || fn == null) return -1;
    try { return fn(_ctx!, clipId, semitones); } catch (e) { return -1; }
  }

  void setPreviewPitchPreserve(bool enabled) {
    _checkDisposed();
    final fn = _bindings?.setPreviewPitchPreserve;
    if (!isReady || fn == null) return;
    try { fn(_ctx!, enabled ? 1 : 0); } catch (_) {}
  }

  int startRecording(String outPath, int mode, int preRollMs, int delayMs, int durationMs) {
    _checkDisposed();
    final fn = _bindings?.startRecording;
    if (!isReady || fn == null) return -1;
    final ptr = outPath.toNativeUtf8();
    try { return fn(_ctx!, ptr, mode, preRollMs, delayMs, durationMs); } catch (e) { return -1; } finally { calloc.free(ptr); }
  }

  int stopRecording() {
    _checkDisposed();
    final fn = _bindings?.stopRecording;
    if (!isReady || fn == null) return 0;
    try { return fn(_ctx!).toInt(); } catch (_) { return 0; }
  }

  bool isRecording() {
    _checkDisposed();
    final fn = _bindings?.isRecording;
    if (!isReady || fn == null) return false;
    try { return fn(_ctx!); } catch (_) { return false; }
  }

  int exportLabels(String path, int format) {
    _checkDisposed();
    final fn = _bindings?.exportLabels;
    if (!isReady || fn == null) return -1;
    final ptr = path.toNativeUtf8();
    try { return fn(_ctx!, ptr, format); } catch (e) { return -1; } finally { calloc.free(ptr); }
  }

  /// v1.1.0 (PLAN 3.11): Clear the speed-ramp curve of a clip.
  void clearSpeedCurve(int clipId) {
    _checkDisposed();
    final bindings = _bindings;
    final fn = bindings?.clearSpeedCurve;
    if (!isReady || fn == null || clipId <= 0) return;
    try {
      fn(_ctx!, clipId);
    } catch (e) {
      debugPrint('[EngineService] clearSpeedCurve failed: $e');
    }
  }

  /// v1.1.0 (PLAN 3.5): Render at an explicit position WITHOUT the effects
  /// (per-clip filter/cc + global filter) — the "before" side of split view.
  Uint8List? renderRawFrameAt(int positionMs,
      {int width = renderWidth, int height = renderHeight}) {
    _checkDisposed();
    final bindings = _bindings;
    final fn = bindings?.renderFrameAtEx;
    if (!isReady || fn == null) return null;
    final ptr = calloc<Uint8>(width * height * 4);
    try {
      if (!fn(_ctx!, ptr, width, height, positionMs, 0)) return null;
      return Uint8List.fromList(ptr.asTypedList(width * height * 4));
    } catch (e) {
      debugPrint('[EngineService] renderRawFrameAt failed: $e');
      return null;
    } finally {
      calloc.free(ptr);
    }
  }

  // v1.1.0 (PLAN 3.7): Real timeline waveform cache — the timeline fetches
  // per (trackIndex, sampleCount); invalidated whenever the timeline changes
  // (see EditorController._onCommandHistoryChanged / load / new).
  final Map<String, Float32List> _timelineWaveformCache = {};
  static const int _maxTimelineWaveformCacheEntries = 16;

  void clearTimelineWaveformCache() {
    _timelineWaveformCache.clear();
  }

  /// v1.1.0 (PLAN 3.7): REAL timeline waveform — peak per bucket from the
  /// engine's mix pipeline (the old getAudioWaveform reads the legacy single
  /// loadMedia() decoder and ignores trims/moves/multi-clip timelines).
  Float32List getTimelineWaveform(int count, int trackIndex) {
    _checkDisposed();
    final bindings = _bindings;
    final fn = bindings?.getTimelineWaveform;
    if (!isReady || fn == null || count <= 0) return Float32List(0);
    final key = '$trackIndex:$count';
    final cached = _timelineWaveformCache[key];
    if (cached != null) return Float32List.fromList(cached);

    final ptr = calloc<Float>(count);
    try {
      final ok = fn(_ctx!, ptr, count, trackIndex);
      if (!ok) return Float32List(0);
      final result = Float32List.fromList(ptr.asTypedList(count));
      if (_timelineWaveformCache.length >= _maxTimelineWaveformCacheEntries &&
          !_timelineWaveformCache.containsKey(key)) {
        _timelineWaveformCache.remove(_timelineWaveformCache.keys.first);
      }
      _timelineWaveformCache[key] = result;
      return Float32List.fromList(result);
    } finally {
      calloc.free(ptr);
    }
  }

  // v0.4.5: Extended filter range (0-10 instead of 0-4)
  // v0.8.0: Range extended to 0-20 (VHS/Glitch/Vignette/Grain/...).
  // v1.0.2: Range extended to 0-22 (Skin Retouch 21, Chroma Key 22).
  // v1.1.0 (PLAN_REVIEW A.1): OUT-OF-RANGE filter ids are now CLAMPED to
  // 0..22 instead of silently rejected — the old reject (early return) kept
  // a stale value while EditorController.setFilter clamps; the two layers
  // disagreed.
  void applyFilter(int filterType, double intensity) {
    _checkDisposed();
    final safeType = filterType.clamp(0, 22);
    final safeIntensity = intensity.clamp(0.0, 1.0);
    _activeFilterType = safeType;
    _filterIntensity = safeIntensity;
    final bindings = _bindings;
    if (isReady && bindings != null) {
      bindings.applyFilter(_ctx!, safeType, safeIntensity);
    }
  }

  // ========== v0.8.0: Full timeline sync ==========

  /// Insert or update a clip in the native timeline. [kind] follows the
  /// engine enum: 0=video, 1=audio, 2=image, 3=text, 4=sticker.
  bool upsertClip({
    required int clipId,
    required String filePath,
    required int startMs,
    required int durationMs,
    required int sourceInMs,
    required int trackIndex,
    required int kind,
    double volume = 1.0,
    double opacity = 1.0,
    double speed = 1.0,
  }) {
    _checkDisposed();
    final bindings = _bindings;
    final fn = bindings?.upsertClip;
    if (!isReady || fn == null || clipId <= 0) return false;
    final pathPtr = filePath.toNativeUtf8();
    try {
      return fn(
        _ctx!,
        clipId,
        pathPtr,
        startMs,
        durationMs,
        sourceInMs,
        trackIndex,
        kind,
        volume,
        opacity,
        speed,
      ) != 0;
    } catch (e) {
      debugPrint('[EngineService] upsertClip failed: $e');
      return false;
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// Remove all clips from the native timeline (new project / project load).
  void clearClips() {
    _checkDisposed();
    final bindings = _bindings;
    final fn = bindings?.clearClips;
    if (!isReady || fn == null) return;
    try {
      fn(_ctx!);
    } catch (e) {
      debugPrint('[EngineService] clearClips failed: $e');
    }
  }

  /// Remove a single clip from the native timeline (differential sync).
  bool removeClip(int clipId) {
    _checkDisposed();
    final bindings = _bindings;
    if (!isReady || bindings == null || clipId <= 0) return false;
    try {
      return bindings.removeClip(_ctx!, clipId) == 0;
    } catch (e) {
      debugPrint('[EngineService] removeClip failed: $e');
      return false;
    }
  }

  /// Mirror track mute/visibility/volume to the native renderer.
  bool setTrackState(int trackIndex, {required bool muted, required bool visible, double volume = 1.0}) {
    _checkDisposed();
    final bindings = _bindings;
    final fn = bindings?.setTrackState;
    if (!isReady || fn == null || trackIndex < 0) return false;
    try {
      return fn(
            _ctx!,
            trackIndex,
            muted ? 1 : 0,
            visible ? 1 : 0,
            volume,
          ) != 0;
    } catch (e) {
      debugPrint('[EngineService] setTrackState failed: $e');
      return false;
    }
  }

  /// Mirror per-clip color correction (all values -1.0..1.0) to the engine.
  bool setClipColorCorrection({
    required int clipId,
    double exposure = 0.0,
    double contrast = 0.0,
    double saturation = 0.0,
    double temperature = 0.0,
    double tint = 0.0,
    double vibrance = 0.0,
    double highlights = 0.0,
    double shadows = 0.0,
  }) {
    _checkDisposed();
    final bindings = _bindings;
    final fn = bindings?.setClipColorCorrection;
    if (!isReady || fn == null || clipId <= 0) return false;
    try {
      return fn(
            _ctx!,
            clipId,
            exposure,
            contrast,
            saturation,
            temperature,
            tint,
            vibrance,
            highlights,
            shadows,
          ) != 0;
    } catch (e) {
      debugPrint('[EngineService] setClipColorCorrection failed: $e');
      return false;
    }
  }

  /// Mirror text/sticker payload to the engine (rendered via GDI).
  bool setClipText({required int clipId, required String text, double fontSize = 48.0, int colorArgb = 0xFFFFFFFF}) {
    _checkDisposed();
    final bindings = _bindings;
    final fn = bindings?.setClipText;
    if (!isReady || fn == null || clipId <= 0) return false;
    final textPtr = text.toNativeUtf8();
    try {
      return fn(_ctx!, clipId, textPtr, fontSize, colorArgb) != 0;
    } catch (e) {
      debugPrint('[EngineService] setClipText failed: $e');
      return false;
    } finally {
      calloc.free(textPtr);
    }
  }

  /// Whether a clip id exists in the native timeline.
  bool hasClip(int clipId) {
    _checkDisposed();
    final bindings = _bindings;
    final fn = bindings?.hasClip;
    if (!isReady || fn == null) return false;
    try {
      return fn(_ctx!, clipId) != 0;
    } catch (_) {
      return false;
    }
  }

  /// Mirror per-clip filter to the engine (used by syncTimelineToEngine).
  bool setClipFilter(int clipId, int filterType, double intensity) {
    _checkDisposed();
    final bindings = _bindings;
    if (!isReady || bindings == null || clipId <= 0) return false;
    try {
      return bindings.setClipFilter(_ctx!, clipId, filterType, intensity) == 0;
    } catch (e) {
      debugPrint('[EngineService] setClipFilter failed: $e');
      return false;
    }
  }

  /// Mirror per-clip transition to the engine (used by syncTimelineToEngine).
  bool setClipTransition(int clipId, int transitionType, int durationMs) {
    _checkDisposed();
    final bindings = _bindings;
    // v1.0.1: Defensive — setClipTransition is a v0.4.0 binding (not v0.8.0)
    // so it's always present if the engine loaded, but be safe anyway.
    final fn = bindings?.setClipTransition;
    if (!isReady || fn == null || clipId <= 0) return false;
    try {
      return fn(_ctx!, clipId, transitionType, durationMs);
    } catch (e) {
      debugPrint('[EngineService] setClipTransition failed: $e');
      return false;
    }
  }

  // v0.7.9: PERF-04 — render a frame at an explicit position without touching
  // playback state (foundation for batch/thumbnail rendering). Uses the shared
  // _framePointer buffer; returns a copy so callers own their bytes.
  Uint8List? renderFrameAt(int positionMs, {int width = renderWidth, int height = renderHeight}) {
    _checkDisposed();
    final bindings = _bindings;
    final fn = bindings?.renderFrameAt;
    if (!isReady || fn == null || _framePointer == null) return null;
    try {
      if (!fn(_ctx!, _framePointer!, width, height, positionMs)) return null;
      final list = _framePointer!.asTypedList(width * height * 4);
      return Uint8List.fromList(list);
    } catch (e, st) {
      debugPrint('[EngineService] renderFrameAt failed: $e\n$st');
      return null;
    }
  }

  // v1.1.0 (PLAN_REVIEW fix #1): Probe media duration OFF the UI thread.
  // FFmpeg stream scanning (avformat_open_input + find_stream_info) can block
  // 100ms-2s on slow/network media and FREEZES the UI because the FFI call
  // runs on the UI isolate. A throwaway engine context in a separate isolate
  // probes the file and reports just the duration; the main engine state is
  // untouched (the C++ engine's own mutexes protect shared codec globals).
  Future<int> probeDurationAsync(String path) {
    final b = _bindings;
    if (!isReady || b == null || path.isEmpty) return Future.value(0);
    return Isolate.run(() {
      final ctx = b.createEngine();
      if (ctx.address == 0) return 0;
      try {
        b.initEngine(ctx);
        final p = path.toNativeUtf8();
        b.loadMedia(ctx, p);
        calloc.free(p);
        final ms = b.getDurationMs(ctx);
        return ms > 0 ? ms : 0;
      } catch (_) {
        return 0;
      } finally {
        b.destroyEngine(ctx);
      }
    });
  }

  void loadMedia(String path) {
    _checkDisposed();
    final bindings = _bindings;
    if (!isReady || path.isEmpty || bindings == null) return;
    final pathPtr = path.toNativeUtf8();
    try {
      bindings.loadMedia(_ctx!, pathPtr);
    } catch (e) {
      debugPrint('[EngineService] loadMedia failed for $path: $e');
      calloc.free(pathPtr);
      return;
    }
    calloc.free(pathPtr);

    // v1.0.2: Validate the probe result — a failed/open-but-empty media could
    // report 0 (or the FFI call could throw). Fall back to the current
    // duration instead of silently treating the media as zero-length.
    try {
      final duration = bindings.getDurationMs(_ctx!);
      if (duration > 0) {
        _durationMs = duration;
      } else {
        debugPrint('[EngineService] Warning: getDurationMs returned $duration for $path');
      }
    } catch (e) {
      debugPrint('[EngineService] getDurationMs failed: $e');
    }
    _positionMs = 0;

    // v0.7.8: Invalidate the waveform cache when the media changes.
    _waveformCacheByCount.clear();

    // v0.4.5: Fetch media info after loading
    fetchMediaInfo();
  }

  // v0.7.8: Waveform cache — the timeline calls getAudioWaveform during
  // build(); with per-tick UI rebuilds during playback this used to hit FFI
  // every frame. Invalidate on loadMedia instead.
  // v0.7.9: Multi-level cache — one native fetch per sample count, then
  // cheap interpolation serves every other zoom level.
  // v1.0.2: Bounded — an unbounded map grew forever when many zoom levels
  // requested distinct sample counts over a long session.
  final Map<int, Float32List> _waveformCacheByCount = {};
  static const int _maxWaveformCacheEntries = 12;

  /// Retrieve audio waveform samples from the native engine (v0.3.0).
  Float32List getAudioWaveform(int count, {int? downsamplingFactor}) {
    _checkDisposed();
    final bindings = _bindings;
    if (!isReady || bindings == null || count <= 0) return Float32List(0);

    // v0.5.8: Apply downsampling for lower resolution at small zoom levels
    final effectiveCount = downsamplingFactor != null
        ? (count / downsamplingFactor).round().clamp(1, count)
        : count;

    // v0.7.9: Serve from the cache — a native fetch happens once per
    // effectiveCount; all zoom levels sharing that count reuse it.
    final cached = _waveformCacheByCount[effectiveCount];
    if (cached != null) {
      if (downsamplingFactor != null && effectiveCount < count) {
        return _upsampleWaveform(cached, count);
      }
      return Float32List.fromList(cached);
    }

    final ptr = calloc<Float>(effectiveCount);
    try {
      final ok = bindings.getAudioWaveform(_ctx!, ptr, effectiveCount);
      if (ok) {
        var result = Float32List.fromList(ptr.asTypedList(effectiveCount));
        // v1.0.2: Bound the cache — evict the oldest entry (insertion order)
        // once it exceeds the cap so long sessions cannot grow it forever.
        if (_waveformCacheByCount.length >= _maxWaveformCacheEntries &&
            !_waveformCacheByCount.containsKey(effectiveCount)) {
          _waveformCacheByCount.remove(_waveformCacheByCount.keys.first);
        }
        _waveformCacheByCount[effectiveCount] = result;
        // If downsampling was requested, upsample by interpolating
        if (downsamplingFactor != null && effectiveCount < count) {
          result = _upsampleWaveform(result, count);
        }
        return result;
      }
      return Float32List(0);
    } finally {
      calloc.free(ptr);
    }
  }

  // v0.5.8: Upsample waveform by linear interpolation when downsampling was used
  Float32List _upsampleWaveform(Float32List source, int targetCount) {
    if (source.length >= targetCount) return source.sublist(0, targetCount);
    
    final result = Float32List(targetCount);
    for (int i = 0; i < targetCount; i++) {
      final pos = i * source.length / targetCount;
      final left = pos.floor();
      final right = (left + 1).clamp(0, source.length - 1);
      final fraction = pos - left;
      
      if (right < source.length) {
        result[i] = source[left] * (1 - fraction) + source[right] * fraction;
      } else {
        result[i] = source[left];
      }
    }
    return result;
  }

  // v0.4.5: Extended export with codec/bitrate/audio control
  bool startExportEx(String outputPath, int width, int height, int fps,
                     String codec, int bitrate, bool includeAudio) {
    _checkDisposed();
    final bindings = _bindings;
    if (!isReady || bindings == null) return false;

    final pathPtr = outputPath.toNativeUtf8();
    final codecPtr = codec.toNativeUtf8();
    try {
      return bindings.startExportEx(_ctx!, pathPtr, width, height, fps,
                                     codecPtr, bitrate, includeAudio) == 0;
    } finally {
      calloc.free(pathPtr);
      calloc.free(codecPtr);
    }
  }

  // v0.4.5: Get export output file size
  int getExportFileSize() {
    final bindings = _bindings;
    if (!isReady || bindings == null) return 0;
    return bindings.getExportFileSize(_ctx!);
  }

  // v0.4.5: Keyframe operations
  bool addClipKeyframe(int clipId, int timeMs, double value) {
    _checkDisposed();
    final bindings = _bindings;
    if (!isReady || bindings == null) return false;
    return bindings.addClipKeyframe(_ctx!, clipId, timeMs, value) == 0;
  }

  bool clearClipKeyframes(int clipId) {
    _checkDisposed();
    final bindings = _bindings;
    if (!isReady || bindings == null) return false;
    return bindings.clearClipKeyframes(_ctx!, clipId) == 0;
  }

  // v0.5.5: Keyframe interpolation
  bool setClipKeyframeInterpolation(int clipId, int interpolationType) {
    _checkDisposed();
    final bindings = _bindings;
    if (!isReady || bindings == null) return false;
    return bindings.setClipKeyframeInterpolation(_ctx!, clipId, interpolationType) == 0;
  }

  int getClipKeyframeInterpolation(int clipId) {
    _checkDisposed();
    final bindings = _bindings;
    if (!isReady || bindings == null) return 0;
    return bindings.getClipKeyframeInterpolation(_ctx!, clipId);
  }

  // v0.5.5: Playback rate control
  // v0.7.9: Also cache the rate locally — the cache key below needs it and
  // calling FFI per tick to read it would defeat the purpose.
  double _playbackRate = 1.0;
  double get playbackRate => _playbackRate;

  void setPlaybackRate(double rate) {
    _checkDisposed();
    _playbackRate = rate.clamp(0.25, 4.0).toDouble();
    final bindings = _bindings;
    if (!isReady || bindings == null) return;
    bindings.setPlaybackRate(_ctx!, _playbackRate);
  }

  // v0.5.8: Frame caching for improved performance
  // v0.7.9: True LRU — getCachedFrame re-inserts the entry so the least
  // recently used frame is always evicted first (was FIFO, which kept frames
  // that were never revisited and evicted hot scrub frames).
  // v1.1.0 (PLAN 2.2/C1): 50 entries × 0.88 MB (640×360×4) ≈ 44 MB of RAM —
  // reduced to 24 (≈21 MB) which still covers a full scrub across 24
  // distinct positions. Cache hits now ALIAS the cached bytes instead of
  // memcpy-ing them (see _frameBytesIsCacheRef) — one 0.88 MB copy saved on
  // every hit.
  final Map<String, Uint8List> _frameCache = {};
  final int _maxCacheSize = 24; // Max cached frames (was 50)

  // v1.1.0 (PLAN 2.2/C1): True when _frameBytes aliases an entry of
  // _frameCache (set on a cache hit). A NEW render must NOT write into the
  // aliased entry (it would corrupt the cache) — allocate a fresh buffer
  // first. The render path is the only writer; consumers (PreviewPlayer)
  // snapshot the bytes before decoding, so aliasing is safe.
  bool _frameBytesIsCacheRef = false;

  // v1.1.0 (PLAN_REVIEW fix #2): idle-poll snapshot — compare-only fields so
  // a paused editor tick short-circuits before any FFI call.
  int _lastPolledPosMs = 0;
  int _lastPolledDurMs = 0;
  int _lastPolledGen = -1;

  void cacheFrame(String key, Uint8List frame) {
    if (_disposed || !isReady) return;
    // LRU eviction: drop the least recently used entry when full
    if (_frameCache.length >= _maxCacheSize && !_frameCache.containsKey(key)) {
      _frameCache.remove(_frameCache.keys.first);
    }
    _frameCache[key] = frame;
  }

  Uint8List? getCachedFrame(String key) {
    final frame = _frameCache.remove(key); // touch: promotes entry to newest
    if (frame == null) return null;
    _frameCache[key] = frame;
    return frame;
  }

  // v0.7.9: PERF-03 — thumbnail cache (path-keyed, LRU, bounded). Native
  // thumbnail extraction is currently unavailable in the DLL (missing
  // symbol), but the cache stays ready for when the engine ships it —
  // Media Bin can switch from icons to thumbnails without re-fetching.
  // v1.1.0 (PLAN 2.3/C2): 100 entries × 0.88 MB potential ≈ 88 MB — reduced
  // to 48 and thumbnails are standardized to 240px (≈12.4 MB worst case).
  final Map<String, Uint8List> _thumbnailCache = {};
  final int _maxThumbnailCacheSize = 48; // was 100

  /// Standard thumbnail dimensions (240px wide, 16:9) — used by Media Bin.
  static const int thumbnailWidth = 240;
  static const int thumbnailHeight = 135;

  Uint8List? getCachedThumbnail(String path) => _thumbnailCache[path];

  void cacheThumbnail(String path, Uint8List bytes) {
    if (_thumbnailCache.length >= _maxThumbnailCacheSize) {
      _thumbnailCache.remove(_thumbnailCache.keys.first);
    }
    _thumbnailCache[path] = bytes;
  }

  void clearThumbnailCache() => _thumbnailCache.clear();

  // v0.5.5: Text overlay rendering — v1.1.0 (PLAN 1.1/B16): REMOVED.
  // The standalone wrapper duplicated GhitaEngine::renderTextOverlay, which
  // is a labeled stub (solid-rect placeholder) — real timeline text renders
  // via the GDI path inside the compositor. Nothing called this wrapper.

  // v0.7.0: Color correction
  // v0.7.8: Symbol may be absent from the DLL (defensive FFI) — no-op then.
  void applyColorCorrection(int clipId, {
    double exposure = 0.0,
    double contrast = 1.0,
    double highlights = 0.0,
    double shadows = 0.0,
    double temperature = 0.0,
    double tint = 0.0,
    double vibrance = 1.0,
    double saturation = 1.0,
  }) {
    _checkDisposed();
    final bindings = _bindings;
    final fn = bindings?.applyColorCorrection;
    if (!isReady || fn == null) return;
    fn(
      _ctx!, clipId,
      exposure, contrast, highlights, shadows,
      temperature, tint, vibrance, saturation,
    );
  }

  // v0.7.0: Keyframe bezier curves
  bool setKeyframeBezier(int clipId, int keyframeIndex, double cp1x, double cp1y, double cp2x, double cp2y) {
    _checkDisposed();
    final bindings = _bindings;
    final fn = bindings?.setKeyframeBezier;
    if (!isReady || fn == null) return false;
    return fn(_ctx!, clipId, keyframeIndex, cp1x, cp1y, cp2x, cp2y) == 0;
  }

  // v0.7.0: PIP rendering
  bool renderPip(int overlayClipId, double x, double y, double width, double height, double rotation) {
    _checkDisposed();
    final bindings = _bindings;
    final fn = bindings?.renderPip;
    if (!isReady || fn == null) return false;
    return fn(_ctx!, overlayClipId, x, y, width, height, rotation);
  }

  // v0.7.0: Thumbnail extraction
  Uint8List? getThumbnail(int clipId, int timeMs, int width, int height) {
    _checkDisposed();
    final bindings = _bindings;
    final fn = bindings?.getThumbnail;
    if (!isReady || fn == null) return null;
    final ptr = fn(_ctx!, clipId, timeMs, width, height);
    if (ptr == nullptr) return null;
    // Copy data and return (caller must not free)
    final size = width * height * 4;
    final result = Uint8List.fromList(ptr.asTypedList(size));
    return result;
  }

  // v0.7.0: Filter preset
  void setFilterPreset(int clipId, int filterType, double intensity) {
    _checkDisposed();
    final bindings = _bindings;
    final fn = bindings?.setFilterPreset;
    if (!isReady || fn == null) return;
    fn(_ctx!, clipId, filterType, intensity);
  }

  bool _tickFrame() {
    if (_disposed || !_isRunning || !isReady || _framePointer == null) return false;
    final bindings = _bindings;
    if (bindings == null) return false;

    // v1.1.0 (PLAN_REVIEW fix #2): paused & idle → skip the FFI/state work
    // entirely (the 33ms timer still runs but costs ~0 per tick). A play/
    // seek/filter/volume change mutates the cache key or position first, so
    // the next tick re-enters; the "last polled" values are updated at the
    // end of every real tick.
    if (!_isPlaying && _positionMs == _lastPolledPosMs &&
        _durationMs == _lastPolledDurMs &&
        _frameGeneration == _lastPolledGen) {
      return true;
    }

    try {
      // v1.1.0 (PLAN 2.10): Capture pre-tick state — a paused idle tick used
      // to notifyListeners() 30×/s for nothing (full UI rebuild each time).
      // Notify only when something actually changed: a new frame rendered,
      // or the playhead/duration/playing state moved.
      final oldPos = _positionMs;
      final oldDur = _durationMs;
      final oldPlaying = _isPlaying;

      _isPlaying = bindings.isPlaying(_ctx!);
      _positionMs = bindings.getPositionMs(_ctx!);
      _durationMs = bindings.getDurationMs(_ctx!);

      // v0.7.8: Cache key includes render-affecting state — a frame rendered
      // with one filter/volume must not be reused after the filter changes.
      // v0.7.9: ...and playback rate (frames differ under 2x vs 1x speed).
      // ignore: unnecessary_brace_in_string_interps
      final cacheKey = '${_positionMs}_${renderWidth}x${renderHeight}_f$_activeFilterType'
          '_i${_filterIntensity.toStringAsFixed(3)}_v${_volume.toStringAsFixed(3)}'
          '_r${_playbackRate.toStringAsFixed(3)}';

      // Try to get frame from cache first
      final cachedFrame = getCachedFrame(cacheKey);
      // v1.1.0 (PLAN_REVIEW fix #4): NEVER serve the cache while playing —
      // the engine advances the playhead INSIDE renderFrameRgba, so a cache
      // hit (e.g. frame at 0ms cached during a previous pause) would keep
      // returning without ever advancing: Play at 0ms "didn't run" until the
      // user scrubbed. Playing must always call the native render.
      if (cachedFrame != null && !bindings.isPlaying(_ctx!)) {
        // v1.1.0 (PLAN 2.2/C1): Alias instead of copy — the old setAll()
        // memcpy'd 0.88 MB on every hit. Consumers snapshot the bytes before
        // decoding, so sharing the cached entry is safe.
        _frameBytes = cachedFrame;
        _frameBytesIsCacheRef = true;
        _isPlaying = bindings.isPlaying(_ctx!); // Keep playing state updated
        // v1.1.0 (PLAN 2.10): The frame is unchanged, but a moved playhead /
        // changed duration / playing state still needs a UI wake-up.
        if (_positionMs != oldPos || _durationMs != oldDur || _isPlaying != oldPlaying) {
          notifyListeners();
        }
        return true;
      }

      final success = bindings.renderFrameRgba(
        _ctx!,
        _framePointer!,
        renderWidth,
        renderHeight,
      );
      if (success) {
        final nativeList = _framePointer!.asTypedList(renderWidth * renderHeight * 4);
        // v1.1.0 (PLAN 2.2/C1): Never write into a cache entry — if the
        // previous tick aliased one, allocate a fresh buffer first.
        if (_frameBytesIsCacheRef || _frameBytes == null) {
          _frameBytes = Uint8List(renderWidth * renderHeight * 4);
          _frameBytesIsCacheRef = false;
        }
        _frameBytes!.setAll(0, nativeList);
        // v1.0.2: Bump the generation ONLY for genuinely new frames — a
        // cache hit below reuses the same bytes and must not trigger a
        // redundant decode on the UI side.
        _frameGeneration++;
        // v0.7.8: Cache a COPY — storing the shared mutable buffer meant every
        // cache entry aliased the same bytes (later frames overwrote earlier
        // ones and scrubbing back showed the wrong frame).
        cacheFrame(cacheKey, Uint8List.fromList(_frameBytes!));
      }
      // v1.1.0 (PLAN 2.10): Notify on a genuinely new frame OR moved state —
      // a filter change re-renders (success) even with an unmoved playhead.
      if (success ||
          _positionMs != oldPos ||
          _durationMs != oldDur ||
          _isPlaying != oldPlaying) {
        notifyListeners();
      }
      // v1.1.0 (PLAN_REVIEW fix #2): refresh the idle-poll snapshot — the
      // next paused/idle tick short-circuits on these values.
      _lastPolledPosMs = _positionMs;
      _lastPolledDurMs = _durationMs;
      _lastPolledGen = _frameGeneration;
      return success;
    } catch (e, st) {
      debugPrint('[EngineService] _tickFrame failed: $e\n$st');
      // v1.0.3: Do NOT stop the loop permanently on a transient failure —
      // that killed playback ("play không chạy") after the first hiccup.
      // Skip this tick and keep going; a permanently broken engine still
      // surfaces via isReady/position staying frozen.
      return true;
    }
  }

  void _startTickLoop() {
    stopPreview();
    _isRunning = true;
    _renderTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      _tickFrame();
    });
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    stopPreview();
    // Free frame buffer to prevent memory leaks
    if (_framePointer != null) {
      calloc.free(_framePointer!);
      _framePointer = null;
    }
    _frameBytes = null;
    
    final bindings = _bindings;
    if (isReady && bindings != null && _ctx != null && _ctx != nullptr) {
      try {
        bindings.destroyEngine(_ctx!);
      } catch (e, st) {
        debugPrint('[EngineService] Error during destroyEngine: $e\n$st');
      }
    }
    _ctx = null;
    engineVersion = '';
    _nativeLibraryLoaded = false;
    super.dispose();
  }
}
