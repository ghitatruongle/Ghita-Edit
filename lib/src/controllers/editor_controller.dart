import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'engine_service.dart';

/// Orchestrates UI state on top of [EngineService].
/// All native FFI calls go through the engine service — this class only
/// handles business logic and notifies listeners when state changes.
class EditorController extends ChangeNotifier {
  final EngineService _engine;
  bool _disposed = false;
  String _statusMessage = 'Initializing...';

  bool get isEngineReady => _engine.isReady;
  String get engineVersion => _engine.engineVersion;

  bool _isPlaying = false;
  int _positionMs = 0;
  int _durationMs = 60000;
  double _volume = 1.0;
  int _activeFilterType = 0;
  double _filterIntensity = 1.0;

  bool get isPlaying => _isPlaying;
  int get positionMs => _positionMs;
  int get durationMs => _durationMs;
  double get volume => _volume;
  int get activeFilterType => _activeFilterType;
  double get filterIntensity => _filterIntensity;
  Uint8List? get frameBytes => _engine.frameBytes;

  String get statusMessage => _statusMessage;

  String _currentMediaName = '';
  String get currentMediaName =>
      _currentMediaName.isNotEmpty ? _currentMediaName : 'No media loaded';

  EditorController({EngineService? engine}) : _engine = engine ?? EngineService();

  /// Initialize the native engine asynchronously.
  Future<void> init() async {
    if (_disposed) return;
    try {
      await _engine.initialize();
      if (!isEngineReady) {
        _statusMessage = 'Native engine unavailable (Demo Mode)';
        notifyListeners();
        return;
      }
      _statusMessage = 'C++ Engine ready';
      notifyListeners();
    } catch (e) {
      _statusMessage = 'Error: $e';
      notifyListeners();
    }
  }

  void loadMedia(String path) {
    if (_disposed || path.isEmpty) return;
    _engine.loadMedia(path);
    _currentMediaName = path.split(RegExp(r'[/\\]')).last;
    _positionMs = 0;
    _statusMessage = 'Loaded: ${_currentMediaName}';
    notifyListeners();
  }

  void togglePlayPause() {
    if (_disposed) return;
    _isPlaying = !_isPlaying;
    if (_engine.isReady) {
      if (_isPlaying) {
        _engine.play();
      } else {
        _engine.pause();
      }
    }
    notifyListeners();
  }

  void seek(int positionMs) {
    if (_disposed) return;
    final clamped = positionMs.clamp(0, _durationMs);
    _positionMs = clamped;
    if (_engine.isReady) {
      _engine.seek(clamped);
    }
    notifyListeners();
  }

  void setVolume(double val) {
    if (_disposed) return;
    final clamped = val.clamp(0.0, 2.0);
    _volume = clamped;
    if (_engine.isReady) {
      _engine.setVolume(clamped);
    }
    notifyListeners();
  }

  void setFilter(int filterType, double intensity) {
    if (_disposed) return;
    final safeType = filterType.clamp(0, 4);
    final safeIntensity = intensity.clamp(0.0, 1.0);
    _activeFilterType = safeType;
    _filterIntensity = safeIntensity;
    if (_engine.isReady) {
      _engine.applyFilter(safeType, safeIntensity);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
    _engine.dispose();
  }
}
