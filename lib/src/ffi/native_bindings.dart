import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// Opaque struct pointer
base class GhitaEngineContext extends Opaque {}

// C Function Signatures & Dart Types
typedef CGhitaEngineCreate = Pointer<GhitaEngineContext> Function();
typedef DartGhitaEngineCreate = Pointer<GhitaEngineContext> Function();

typedef CGhitaEngineDestroy = Void Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineDestroy = void Function(Pointer<GhitaEngineContext> ctx);

typedef CGhitaEngineInit = Int32 Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineInit = int Function(Pointer<GhitaEngineContext> ctx);

typedef CGhitaEngineLoadMedia = Int32 Function(Pointer<GhitaEngineContext> ctx, Pointer<Utf8> filePath);
typedef DartGhitaEngineLoadMedia = int Function(Pointer<GhitaEngineContext> ctx, Pointer<Utf8> filePath);

typedef CGhitaEngineGetDurationMs = Int64 Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineGetDurationMs = int Function(Pointer<GhitaEngineContext> ctx);

typedef CGhitaEngineGetMediaWidth = Int32 Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineGetMediaWidth = int Function(Pointer<GhitaEngineContext> ctx);

typedef CGhitaEngineGetMediaHeight = Int32 Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineGetMediaHeight = int Function(Pointer<GhitaEngineContext> ctx);

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

typedef CGhitaEngineSetVolume = Void Function(Pointer<GhitaEngineContext> ctx, Float volume);
typedef DartGhitaEngineSetVolume = void Function(Pointer<GhitaEngineContext> ctx, double volume);

typedef CGhitaEngineApplyFilter = Void Function(Pointer<GhitaEngineContext> ctx, Int32 filterType, Float intensity);
typedef DartGhitaEngineApplyFilter = void Function(Pointer<GhitaEngineContext> ctx, int filterType, double intensity);

typedef CGhitaEngineRenderFrameRgba = Bool Function(Pointer<GhitaEngineContext> ctx, Pointer<Uint8> outBuffer, Int32 width, Int32 height);
typedef DartGhitaEngineRenderFrameRgba = bool Function(Pointer<GhitaEngineContext> ctx, Pointer<Uint8> outBuffer, int width, int height);

// getVersion returns static char* valid for process lifetime (no free needed)
typedef CGhitaEngineGetVersion = Pointer<Utf8> Function();
typedef DartGhitaEngineGetVersion = Pointer<Utf8> Function();

class GhitaNativeBindings {
  static final GhitaNativeBindings instance = GhitaNativeBindings._internal();
  late DynamicLibrary _lib;
  bool _initialized = false;

  late DartGhitaEngineCreate createEngine;
  late DartGhitaEngineDestroy destroyEngine;
  late DartGhitaEngineInit initEngine;
  late DartGhitaEngineLoadMedia loadMedia;
  late DartGhitaEngineGetDurationMs getDurationMs;
  late DartGhitaEngineGetMediaWidth getMediaWidth;
  late DartGhitaEngineGetMediaHeight getMediaHeight;
  late DartGhitaEnginePlay play;
  late DartGhitaEnginePause pause;
  late DartGhitaEngineIsPlaying isPlaying;
  late DartGhitaEngineSeek seek;
  late DartGhitaEngineGetPositionMs getPositionMs;
  late DartGhitaEngineSetVolume setVolume;
  late DartGhitaEngineApplyFilter applyFilter;
  late DartGhitaEngineRenderFrameRgba renderFrameRgba;
  late DartGhitaEngineGetVersion getVersion;

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
    } else if (Platform.isMacOS || Platform.isLinux) {
      final candidates = <String>[
        'libghita_engine.dylib',
        'libghita_engine.so',
        '${Directory.current.path}\\native_engine\\build\\libghita_engine.so',
        '${Directory(Platform.resolvedExecutable).parent.path}\\libghita_engine.dylib',
      ];
      for (final path in candidates) {
        try {
          return DynamicLibrary.open(path);
        } catch (_) {
          continue;
        }
      }
      throw StateError('libghita_engine shared library not found in any expected location');
    }
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }

  void _bindFunctions() {
    // Use typed lookupFunction<T, U>() — compatible with Dart SDK >= 3.12
    createEngine = _lib.lookupFunction<CGhitaEngineCreate, DartGhitaEngineCreate>('ghita_engine_create');
    destroyEngine = _lib.lookupFunction<CGhitaEngineDestroy, DartGhitaEngineDestroy>('ghita_engine_destroy');
    initEngine = _lib.lookupFunction<CGhitaEngineInit, DartGhitaEngineInit>('ghita_engine_init');
    loadMedia = _lib.lookupFunction<CGhitaEngineLoadMedia, DartGhitaEngineLoadMedia>('ghita_engine_load_media');
    getDurationMs = _lib.lookupFunction<CGhitaEngineGetDurationMs, DartGhitaEngineGetDurationMs>('ghita_engine_get_duration_ms');
    getMediaWidth = _lib.lookupFunction<CGhitaEngineGetMediaWidth, DartGhitaEngineGetMediaWidth>('ghita_engine_get_media_width');
    getMediaHeight = _lib.lookupFunction<CGhitaEngineGetMediaHeight, DartGhitaEngineGetMediaHeight>('ghita_engine_get_media_height');
    play = _lib.lookupFunction<CGhitaEnginePlay, DartGhitaEnginePlay>('ghita_engine_play');
    pause = _lib.lookupFunction<CGhitaEnginePause, DartGhitaEnginePause>('ghita_engine_pause');
    isPlaying = _lib.lookupFunction<CGhitaEngineIsPlaying, DartGhitaEngineIsPlaying>('ghita_engine_is_playing');
    seek = _lib.lookupFunction<CGhitaEngineSeek, DartGhitaEngineSeek>('ghita_engine_seek');
    getPositionMs = _lib.lookupFunction<CGhitaEngineGetPositionMs, DartGhitaEngineGetPositionMs>('ghita_engine_get_position_ms');
    setVolume = _lib.lookupFunction<CGhitaEngineSetVolume, DartGhitaEngineSetVolume>('ghita_engine_set_volume');
    applyFilter = _lib.lookupFunction<CGhitaEngineApplyFilter, DartGhitaEngineApplyFilter>('ghita_engine_apply_filter');
    renderFrameRgba = _lib.lookupFunction<CGhitaEngineRenderFrameRgba, DartGhitaEngineRenderFrameRgba>('ghita_engine_render_frame_rgba');
    getVersion = _lib.lookupFunction<CGhitaEngineGetVersion, DartGhitaEngineGetVersion>('ghita_engine_get_version');
  }
}
