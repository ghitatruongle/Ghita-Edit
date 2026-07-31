import 'dart:async';
import 'dart:ffi';
import 'dart:convert';

import 'package:ffi/ffi.dart';
import '../ffi/native_bindings.dart';
import 'package:flutter/foundation.dart';

/// Manages the raw C++ engine lifecycle and native memory.
/// This class owns the FFI boundary — the controller should never call
/// native bindings directly for engine operations.
class EngineService {
  final GhitaNativeBindings? _bindings;
  Pointer<GhitaEngineContext>? _ctx;

  // Render frame buffer allocated via calloc.
  Pointer<Uint8>? _framePointer;
  Uint8List? _frameBytes;

  Timer? _renderTimer;
  bool _isRunning = false;

  // v0.5.8: Frame caching for improved performance during scrubbing
  final Map<String, Uint8List> _frameCache = {};
  final int _maxCacheSize = 50; // Max cached frames

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
      _framePointer = calloc<Uint8>(renderWidth * renderHeight * 4);
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
    // Ensure frame pointers are freed to prevent memory leaks
    if (_framePointer != null) {
      calloc.free(_framePointer!);
      _framePointer = null;
    }
    _frameBytes = null;
  }

  void play() {
    _checkDisposed();
    final bindings = _bindings;
    if (!isReady || bindings == null) return;
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

  // v0.4.5: Extended filter range (0-10 instead of 0-4)
  void applyFilter(int filterType, double intensity) {
    _checkDisposed();
    if (filterType < 0 || filterType > 10) return;
    if (intensity < 0.0) intensity = 0.0;
    if (intensity > 1.0) intensity = 1.0;
    _activeFilterType = filterType;
    _filterIntensity = intensity;
    final bindings = _bindings;
    if (isReady && bindings != null) {
      bindings.applyFilter(_ctx!, filterType, intensity);
    }
  }

  void loadMedia(String path) {
    _checkDisposed();
    final bindings = _bindings;
    if (!isReady || path.isEmpty || bindings == null) return;
    final pathPtr = path.toNativeUtf8();
    try {
      bindings.loadMedia(_ctx!, pathPtr);
    } finally {
      calloc.free(pathPtr);
    }
    _durationMs = bindings.getDurationMs(_ctx!);
    _positionMs = 0;

    // v0.4.5: Fetch media info after loading
    fetchMediaInfo();
  }

  /// Retrieve audio waveform samples from the native engine (v0.3.0).
  Float32List getAudioWaveform(int count, {int? downsamplingFactor}) {
    _checkDisposed();
    final bindings = _bindings;
    if (!isReady || bindings == null || count <= 0) return Float32List(0);
    
    // v0.5.8: Apply downsampling for lower resolution at small zoom levels
    final effectiveCount = downsamplingFactor != null 
        ? (count / downsamplingFactor).round()
        : count;
    
    final ptr = calloc<Float>(effectiveCount);
    try {
      final ok = bindings.getAudioWaveform(_ctx!, ptr, effectiveCount);
      if (ok) {
        final result = Float32List.fromList(ptr.asTypedList(effectiveCount));
        // If downsampling was requested, upsample by interpolating
        if (downsamplingFactor != null && effectiveCount < count) {
          return _upsampleWaveform(result, count);
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
  void setPlaybackRate(double rate) {
    _checkDisposed();
    final bindings = _bindings;
    if (!isReady || bindings == null) return;
    bindings.setPlaybackRate(_ctx!, rate.clamp(0.25, 4.0).toDouble());
  }

  double getPlaybackRate() {
    _checkDisposed();
    final bindings = _bindings;
    if (!isReady || bindings == null) return 1.0;
    return bindings.getPlaybackRate(_ctx!);
  }

  // v0.5.8: Frame caching for improved performance
  void cacheFrame(String key, Uint8List frame) {
    if (_disposed || !isReady) return;
    // Remove oldest if cache is full
    if (_frameCache.length >= _maxCacheSize) {
      // Remove first entry (simple LRU - could be improved)
      final firstKey = _frameCache.keys.first;
      _frameCache.remove(firstKey);
    }
    _frameCache[key] = frame;
  }

  Uint8List? getCachedFrame(String key) {
    return _frameCache[key];
  }

  void clearCache() {
    _frameCache.clear();
  }

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
    if (!isReady || bindings == null) return;
    bindings.applyColorCorrection(
      _ctx!, clipId,
      exposure, contrast, highlights, shadows,
      temperature, tint, vibrance, saturation,
    );
  }

  // v0.7.0: Keyframe bezier curves
  bool setKeyframeBezier(int clipId, int keyframeIndex, double cp1x, double cp1y, double cp2x, double cp2y) {
    _checkDisposed();
    final bindings = _bindings;
    if (!isReady || bindings == null) return false;
    return bindings.setKeyframeBezier(_ctx!, clipId, keyframeIndex, cp1x, cp1y, cp2x, cp2y) == 0;
  }

  // v0.7.0: PIP rendering
  bool renderPip(int overlayClipId, double x, double y, double width, double height, double rotation) {
    _checkDisposed();
    final bindings = _bindings;
    if (!isReady || bindings == null) return false;
    return bindings.renderPip(_ctx!, overlayClipId, x, y, width, height, rotation);
  }

  // v0.7.0: Thumbnail extraction
  Uint8List? getThumbnail(int clipId, int timeMs, int width, int height) {
    _checkDisposed();
    final bindings = _bindings;
    if (!isReady || bindings == null) return null;
    final ptr = bindings.getThumbnail(_ctx!, clipId, timeMs, width, height);
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
    if (!isReady || bindings == null) return;
    bindings.setFilterPreset(_ctx!, clipId, filterType, intensity);
  }

  // v0.7.0: Audio waveform peaks for timeline
  Float32List getAudioWaveformPeaks(int count) {
    _checkDisposed();
    final bindings = _bindings;
    if (!isReady || bindings == null || count <= 0) return Float32List(0);
    final ptr = calloc<Float>(count);
    try {
      final ok = bindings.getAudioWaveformPeaks(_ctx!, ptr, count);
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

      // Create cache key based on position and rendering parameters
      // ignore: unnecessary_brace_in_string_interps
      final cacheKey = '${_positionMs}_${renderWidth}x$renderHeight';
      
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
        // Cache the rendered frame for future use
        cacheFrame(cacheKey, _frameBytes!);
      }
      return success;
    } catch (e, st) {
      debugPrint('[EngineService] _tickFrame failed: $e\n$st');
      stopPreview();
      return false;
    }
  }

  void _startTickLoop() {
    stopPreview();
    _isRunning = true;
    _renderTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (!_tickFrame()) {
        stopPreview();
      }
    });
  }

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
  }
}
