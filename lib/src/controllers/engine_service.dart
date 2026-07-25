import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import '../ffi/native_bindings.dart';

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

  static GhitaNativeBindings? _tryLoadBindings() {
    try {
      return GhitaNativeBindings.instance;
    } catch (_) {
      return null;
    }
  }

  /// Initialize the native engine asynchronously and start the preview tick loop.
  Future<void> initialize() async {
    if (isReady) return;
    final bindings = _bindings;
    if (bindings == null) return;

    try {
      final ctx = bindings.createEngine();
      if (ctx == nullptr) return;

      final initResult = bindings.initEngine(ctx);
      if (initResult != 0) return;

      _ctx = ctx;

      final verPtr = bindings.getVersion();
      if (verPtr != nullptr) {
        engineVersion = verPtr.toDartString();
      }

      // Allocate native buffer for preview frames
      _framePointer = calloc<Uint8>(renderWidth * renderHeight * 4);
      _frameBytes = Uint8List(renderWidth * renderHeight * 4);

      _startTickLoop();
    } catch (_) {
      // Keep engine unavailable; caller should not crash
      _ctx = null;
    }
  }

  void startPreview() {
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
    final bindings = _bindings;
    if (!isReady || bindings == null) return;
    _isPlaying = true;
    bindings.play(_ctx!);
  }

  void pause() {
    final bindings = _bindings;
    if (!isReady || bindings == null) return;
    _isPlaying = false;
    bindings.pause(_ctx!);
  }

  void seek(int positionMs) {
    final bindings = _bindings;
    if (!isReady || bindings == null) return;
    bindings.seek(_ctx!, positionMs);
    _positionMs = positionMs;
  }

  void setVolume(double val) {
    if (val < 0.0) val = 0.0;
    if (val > 2.0) val = 2.0;
    _volume = val;
    final bindings = _bindings;
    if (isReady && bindings != null) {
      bindings.setVolume(_ctx!, val);
    }
  }

  void applyFilter(int filterType, double intensity) {
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

  bool _tickFrame() {
    final bindings = _bindings;
    if (!isRunning || !isReady || _framePointer == null || bindings == null) return false;

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
    } catch (_) {
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
    stopPreview();
    if (_framePointer != null) {
      calloc.free(_framePointer!);
      _framePointer = null;
    }
    final bindings = _bindings;
    if (isReady && bindings != null) {
      bindings.destroyEngine(_ctx!);
    }
    _ctx = null;
    _frameBytes = null;
    engineVersion = '';
  }
}
