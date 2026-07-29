import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import '../ffi/native_bindings.dart';
import 'package:flutter/foundation.dart'; // 🔒 FIX: Add for debugPrint

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

  bool get isReady => _ctx != null && _ctx != nullptr;
  bool get isRunning => _isRunning;
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

  static const int renderWidth = 640;
  static const int renderHeight = 360;

  Uint8List? get frameBytes => _frameBytes;

  EngineService({GhitaNativeBindings? bindings, bool skipNativeInit = false})
      : _bindings = bindings ?? (skipNativeInit ? null : _tryLoadBindings());

  // 🔒 FIX: Prevent double dispose — critical for memory safety
  bool _disposed = false;

  static GhitaNativeBindings? _tryLoadBindings() {
    try {
      return GhitaNativeBindings.instance;
    } catch (_) {
      return null;
    }
  }

  // Guard method — throws if already disposed
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
      return;
    }

    try {
      final ctx = bindings.createEngine();
      if (ctx == nullptr) {
        debugPrint('[EngineService] Failed to create native engine context');
        _ctx = null;
        return;
      }

      final initResult = bindings.initEngine(ctx);
      if (initResult != 0) {
        // Clean up the context if init failed to prevent memory leak
        bindings.destroyEngine(ctx);
        debugPrint('[EngineService] Engine initialization failed with code: $initResult');
        _ctx = null;
        return;
      }

      _ctx = ctx;

      final verPtr = bindings.getVersion();
      if (verPtr != nullptr) {
        engineVersion = verPtr.toDartString();
      } else {
        engineVersion = 'Unknown';
      }

      // Allocate native buffer for preview frames
      _framePointer = calloc<Uint8>(renderWidth * renderHeight * 4);
      _frameBytes = Uint8List(renderWidth * renderHeight * 4);

      _startTickLoop();
    } catch (e, st) {
      // 🔒 FIX: Log errors instead of silently swallowing them
      debugPrint('[EngineService] Initialization failed: $e\n$st');
      _ctx = null;
      rethrow; // Let caller know
    }
  }

  void startPreview() {
    _checkDisposed();
    if (_isRunning || !isReady) return;
    _isRunning = true;
    _startTickLoop();
  }

  void stopPreview() {
    _isRunning = false;
    _renderTimer?.cancel();
    _renderTimer = null;
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

  void applyFilter(int filterType, double intensity) {
    _checkDisposed();
    if (filterType < 0 || filterType > 4) return;
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
    // Refresh duration immediately so callers can read it right after load
    _durationMs = bindings.getDurationMs(_ctx!);
    _positionMs = 0;
  }

  /// Retrieve audio waveform samples from the native engine (v0.3.0).
  Float32List getAudioWaveform(int count) {
    _checkDisposed();
    final bindings = _bindings;
    if (!isReady || bindings == null || count <= 0) return Float32List(0);
    final ptr = calloc<Float>(count);
    try {
      final ok = bindings.getAudioWaveform(_ctx!, ptr, count);
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

      final success = bindings.renderFrameRgba(
        _ctx!,
        _framePointer!,
        renderWidth,
        renderHeight,
      );
      if (success) {
        final nativeList = _framePointer!.asTypedList(renderWidth * renderHeight * 4);
        _frameBytes!.setAll(0, nativeList);
      }
      return success;
    } catch (e, st) {
      // 🔒 FIX: Log errors instead of silently failing
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
    // 🔒 FIX: Idempotent — multiple dispose calls are safe
    if (_disposed) return;
    _disposed = true;

    stopPreview();
    if (_framePointer != null) {
      calloc.free(_framePointer!);
      _framePointer = null;
    }
    _frameBytes = null;
    final bindings = _bindings;
    // Only call destroyEngine if we have a valid context
    if (isReady && bindings != null && _ctx != null && _ctx != nullptr) {
      try {
        bindings.destroyEngine(_ctx!);
      } catch (e, st) {
        debugPrint('[EngineService] Error during destroyEngine: $e\n$st');
      }
    }
    _ctx = null;
    engineVersion = '';
  }
}
