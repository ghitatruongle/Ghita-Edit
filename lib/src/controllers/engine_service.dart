import 'dart:async';
import 'dart:ffi';
import 'dart:convert';

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

  // v0.4.5: Extended filter range (0-10 instead of 0-4)
  // v0.8.0: Range extended to 0-20 (VHS/Glitch/Vignette/Grain/...).
  // v1.0.2: Range extended to 0-22 (Skin Retouch 21, Chroma Key 22).
  void applyFilter(int filterType, double intensity) {
    _checkDisposed();
    if (filterType < 0 || filterType > 22) return;
    if (intensity < 0.0) intensity = 0.0;
    if (intensity > 1.0) intensity = 1.0;
    _activeFilterType = filterType;
    _filterIntensity = intensity;
    final bindings = _bindings;
    if (isReady && bindings != null) {
      bindings.applyFilter(_ctx!, filterType, intensity);
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
      return bindings.removeClip(_ctx!, clipId) != 0;
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
      return bindings.setClipFilter(_ctx!, clipId, filterType, intensity) != 0;
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

  double getPlaybackRate() {
    _checkDisposed();
    final bindings = _bindings;
    if (!isReady || bindings == null) return 1.0;
    return bindings.getPlaybackRate(_ctx!);
  }

  // v0.5.8: Frame caching for improved performance
  // v0.7.9: True LRU — getCachedFrame re-inserts the entry so the least
  // recently used frame is always evicted first (was FIFO, which kept frames
  // that were never revisited and evicted hot scrub frames).
  final Map<String, Uint8List> _frameCache = {};
  final int _maxCacheSize = 50; // Max cached frames

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

  void clearCache() {
    _frameCache.clear();
  }

  // v0.7.9: PERF-03 — thumbnail cache (path-keyed, LRU, bounded). Native
  // thumbnail extraction is currently unavailable in the DLL (missing
  // symbol), but the cache stays ready for when the engine ships it —
  // Media Bin can switch from icons to thumbnails without re-fetching.
  final Map<String, Uint8List> _thumbnailCache = {};
  final int _maxThumbnailCacheSize = 100;

  Uint8List? getCachedThumbnail(String path) => _thumbnailCache[path];

  void cacheThumbnail(String path, Uint8List bytes) {
    if (_thumbnailCache.length >= _maxThumbnailCacheSize) {
      _thumbnailCache.remove(_thumbnailCache.keys.first);
    }
    _thumbnailCache[path] = bytes;
  }

  void clearThumbnailCache() => _thumbnailCache.clear();

  // v0.5.5: Text overlay rendering (basic rasterizer stub)
  bool renderTextOverlay(Uint8List buffer, int width, int height,
                         String text, int fontSize, double r, double g, double b, double a) {
    _checkDisposed();
    final bindings = _bindings;
    if (!isReady || bindings == null) return false;

    final bufferPtr = calloc<Uint8>(buffer.length);
    final textPtr = text.toNativeUtf8();
    try {
      bufferPtr.asTypedList(buffer.length).setAll(0, buffer);
      return bindings.renderTextOverlay(
        _ctx!, bufferPtr, width, height,
        textPtr, fontSize, r, g, b, a
      );
    } finally {
      calloc.free(bufferPtr);
      calloc.free(textPtr);
    }
  }

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

  // v0.7.0: Audio waveform peaks for timeline
  Float32List getAudioWaveformPeaks(int count) {
    _checkDisposed();
    final bindings = _bindings;
    final fn = bindings?.getAudioWaveformPeaks;
    if (!isReady || fn == null || count <= 0) return Float32List(0);
    final ptr = calloc<Float>(count);
    try {
      final ok = fn(_ctx!, ptr, count);
      if (ok) {
        return Float32List.fromList(ptr.asTypedList(count));
      }
      return Float32List(0);
    } finally {
      calloc.free(ptr);
    }
  }

  bool _tickFrame() {
    if (_disposed || !_isRunning || !isReady || _framePointer == null) return false;
    final bindings = _bindings;
    if (bindings == null) return false;

    try {
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
      if (cachedFrame != null) {
        _frameBytes!.setAll(0, cachedFrame);
        _isPlaying = bindings.isPlaying(_ctx!); // Keep playing state updated
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
      // v0.7.8: Push state (position/duration/frame) to the UI every tick.
      notifyListeners();
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
