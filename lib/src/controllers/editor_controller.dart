import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import '../ffi/native_bindings.dart';

class EditorController extends ChangeNotifier {
  Pointer<GhitaEngineContext>? _ctx;
  bool _isEngineReady = false;
  
  bool get isEngineReady => _isEngineReady;
  String _engineVersion = 'Loading...';
  String get engineVersion => _engineVersion;

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  int _positionMs = 0;
  int get positionMs => _positionMs;

  int _durationMs = 60000;
  int get durationMs => _durationMs;

  double _volume = 1.0;
  double get volume => _volume;

  int _activeFilterType = 0; // 0: None, 1: Grayscale, 2: Sepia, 3: Invert
  int get activeFilterType => _activeFilterType;

  double _filterIntensity = 1.0;
  double get filterIntensity => _filterIntensity;

  String _currentMediaName = "Sample_Video_Track.mp4";
  String get currentMediaName => _currentMediaName;

  Timer? _renderTimer;

  // Frame rendering buffers for preview
  static const int renderWidth = 640;
  static const int renderHeight = 360;
  Pointer<Uint8>? _framePointer;
  Uint8List? _frameBytes;
  Uint8List? get frameBytes => _frameBytes;

  EditorController() {
    _initEngine();
  }

  void _initEngine() {
    try {
      final bindings = GhitaNativeBindings.instance;
      _ctx = bindings.createEngine();
      if (_ctx != null && _ctx != nullptr) {
        bindings.initEngine(_ctx!);
        _isEngineReady = true;

        final verPtr = bindings.getVersion();
        if (verPtr != nullptr) {
          _engineVersion = verPtr.toDartString();
        }

        // Allocate native buffer for 640x360 RGBA frames (640 * 360 * 4 bytes = 921,600 bytes)
        _framePointer = calloc<Uint8>(renderWidth * renderHeight * 4);
        _frameBytes = Uint8List(renderWidth * renderHeight * 4);

        // Start 30fps preview ticker loop
        _renderTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
          _tickFrame();
        });
      }
    } catch (e) {
      _engineVersion = "Native C++ Engine initializing (Demo Mode)";
      _isEngineReady = false;
      notifyListeners();
    }
  }

  void _tickFrame() {
    if (!_isEngineReady || _ctx == null || _framePointer == null) return;
    
    final bindings = GhitaNativeBindings.instance;
    _isPlaying = bindings.isPlaying(_ctx!);
    _positionMs = bindings.getPositionMs(_ctx!);
    _durationMs = bindings.getDurationMs(_ctx!);

    bool success = bindings.renderFrameRgba(_ctx!, _framePointer!, renderWidth, renderHeight);
    if (success) {
      final nativeList = _framePointer!.asTypedList(renderWidth * renderHeight * 4);
      _frameBytes!.setAll(0, nativeList);
      notifyListeners();
    }
  }

  void loadMedia(String path) {
    if (!_isEngineReady || _ctx == null) return;
    final pathPtr = path.toNativeUtf8();
    GhitaNativeBindings.instance.loadMedia(_ctx!, pathPtr);
    calloc.free(pathPtr);

    _currentMediaName = path.split(RegExp(r'[/\\]')).last;
    _positionMs = 0;
    notifyListeners();
  }

  void togglePlayPause() {
    if (!_isEngineReady || _ctx == null) return;
    final bindings = GhitaNativeBindings.instance;
    if (_isPlaying) {
      bindings.pause(_ctx!);
    } else {
      bindings.play(_ctx!);
    }
    _isPlaying = !_isPlaying;
    notifyListeners();
  }

  void seek(int positionMs) {
    if (!_isEngineReady || _ctx == null) return;
    GhitaNativeBindings.instance.seek(_ctx!, positionMs);
    _positionMs = positionMs;
    notifyListeners();
  }

  void setVolume(double val) {
    _volume = val;
    if (_isEngineReady && _ctx != null) {
      GhitaNativeBindings.instance.setVolume(_ctx!, val);
    }
    notifyListeners();
  }

  void setFilter(int filterType, double intensity) {
    _activeFilterType = filterType;
    _filterIntensity = intensity;
    if (_isEngineReady && _ctx != null) {
      GhitaNativeBindings.instance.applyFilter(_ctx!, filterType, intensity);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _renderTimer?.cancel();
    if (_framePointer != null) {
      calloc.free(_framePointer!);
    }
    if (_ctx != null && _isEngineReady) {
      GhitaNativeBindings.instance.destroyEngine(_ctx!);
    }
    super.dispose();
  }
}
