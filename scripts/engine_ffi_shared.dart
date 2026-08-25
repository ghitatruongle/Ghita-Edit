// Single source of truth for the hand-rolled engine FFI signatures used by
// the maintenance scripts under scripts/.
//
// lib/src/ffi/native_bindings.dart cannot be imported here (it pulls in
// Flutter), which is why these declarations exist — but the SIGNATURES must
// be defined exactly once so the T6-selection-style arity drift can never
// reappear. Scripts import this file and, at most, add `typedef _X = X;`
// ALIASES for their local shorthand names. Never redeclare a
// `... Function(...)` signature locally.
//
// Arity/type parity against the Rust exports is enforced for the app
// bindings by test/ffi_arity_contract_test.dart.
library;

import 'dart:ffi';
import 'package:ffi/ffi.dart' show Utf8;

/// Opaque engine context handle.
final class GhitaCtx extends Opaque {}

// Lifecycle -------------------------------------------------------------------

typedef CCreate = Pointer<GhitaCtx> Function();
typedef DCreate = Pointer<GhitaCtx> Function();

typedef CInit = Int32 Function(Pointer<GhitaCtx>);
typedef DInit = int Function(Pointer<GhitaCtx>);

typedef CDestroy = Void Function(Pointer<GhitaCtx>);
typedef DDestroy = void Function(Pointer<GhitaCtx>);

// Media -----------------------------------------------------------------------

typedef CLoadMedia = Int32 Function(Pointer<GhitaCtx>, Pointer<Utf8>);
typedef DLoadMedia = int Function(Pointer<GhitaCtx>, Pointer<Utf8>);

typedef CGetDurationMs = Int64 Function(Pointer<GhitaCtx>);
typedef DGetDurationMs = int Function(Pointer<GhitaCtx>);

typedef CGetPositionMs = Int64 Function(Pointer<GhitaCtx>);
typedef DGetPositionMs = int Function(Pointer<GhitaCtx>);

typedef CGetMediaInfo = Pointer<Utf8> Function(Pointer<GhitaCtx>);
typedef DGetMediaInfo = Pointer<Utf8> Function(Pointer<GhitaCtx>);

// Playback --------------------------------------------------------------------

typedef CPlay = Void Function(Pointer<GhitaCtx>);
typedef DPlay = void Function(Pointer<GhitaCtx>);

typedef CPause = Void Function(Pointer<GhitaCtx>);
typedef DPause = void Function(Pointer<GhitaCtx>);

typedef CSeek = Void Function(Pointer<GhitaCtx>, Int64);
typedef DSeek = void Function(Pointer<GhitaCtx>, int);

typedef CSetPlaybackRate = Void Function(Pointer<GhitaCtx>, Float);
typedef DSetPlaybackRate = void Function(Pointer<GhitaCtx>, double);

typedef CIsPlaying = Bool Function(Pointer<GhitaCtx>);
typedef DIsPlaying = bool Function(Pointer<GhitaCtx>);

/// Generic `void f(ctx)` shape for misc one-arg commands.
typedef CVoidCtx = Void Function(Pointer<GhitaCtx>);
typedef DVoidCtx = void Function(Pointer<GhitaCtx>);

// Rendering -------------------------------------------------------------------

typedef CRenderFrame = Bool Function(
    Pointer<GhitaCtx>, Pointer<Uint8>, Int32, Int32);
typedef DRenderFrame = bool Function(
    Pointer<GhitaCtx>, Pointer<Uint8>, int, int);

typedef CRenderFrameAt = Bool Function(
    Pointer<GhitaCtx>, Pointer<Uint8>, Int32, Int32, Int64);
typedef DRenderFrameAt = bool Function(
    Pointer<GhitaCtx>, Pointer<Uint8>, int, int, int);

// Timeline / mixer ------------------------------------------------------------

typedef CUpsertClip = Int32 Function(Pointer<GhitaCtx>, Int32, Pointer<Utf8>,
    Int64, Int64, Int64, Int32, Int32, Float, Float, Float);
typedef DUpsertClip = int Function(Pointer<GhitaCtx>, int, Pointer<Utf8>, int,
    int, int, int, int, double, double, double);

typedef CClearClips = Void Function(Pointer<GhitaCtx>);
typedef DClearClips = void Function(Pointer<GhitaCtx>);

typedef CMixAudioWindow = Bool Function(
    Pointer<GhitaCtx>, Int64, Int64, Pointer<Float>, Int32);
typedef DMixAudioWindow = bool Function(
    Pointer<GhitaCtx>, int, int, Pointer<Float>, int);

// Export ----------------------------------------------------------------------

typedef CStartExportEx = Int32 Function(Pointer<GhitaCtx>, Pointer<Utf8>,
    Int32, Int32, Int32, Pointer<Utf8>, Int64, Bool);
typedef DStartExportEx = int Function(Pointer<GhitaCtx>, Pointer<Utf8>, int,
    int, int, Pointer<Utf8>, int, bool);

typedef CIsExporting = Bool Function(Pointer<GhitaCtx>);
typedef DIsExporting = bool Function(Pointer<GhitaCtx>);

typedef CGetExportProgress = Float Function(Pointer<GhitaCtx>);
typedef DGetExportProgress = double Function(Pointer<GhitaCtx>);

typedef CGetExportFileSize = Int64 Function(Pointer<GhitaCtx>);
typedef DGetExportFileSize = int Function(Pointer<GhitaCtx>);

/// v1.5.0-T2 (P3): "stereo" | "5.1" | "7.1" — multichannel export selection.
typedef CSetExportChannelLayout = Int32 Function(Pointer<GhitaCtx>, Pointer<Utf8>);
typedef DSetExportChannelLayout = int Function(Pointer<GhitaCtx>, Pointer<Utf8>);

// Info ------------------------------------------------------------------------

typedef CGetVersion = Pointer<Utf8> Function();
typedef DGetVersion = Pointer<Utf8> Function();

typedef CHasFFmpeg = Bool Function(Pointer<GhitaCtx>);
typedef DHasFFmpeg = bool Function(Pointer<GhitaCtx>);

// Loader ----------------------------------------------------------------------

/// Candidate DLL locations, most-specific first (shared by every script).
List<String> engineDllCandidates() => [
      'native_engine_rust/target/debug/ghita_engine.dll',
      'native_engine_rust/target/release/ghita_engine.dll',
      'build/windows/x64/runner/Release/ghita_engine.dll',
      'build/native_engine/ghita_engine.dll',
      'ghita_engine.dll',
    ];

/// Opens the first available engine DLL (an explicit [dllPath] wins), or
/// returns null when none of the candidates load.
DynamicLibrary? loadEngineLibrary({String? dllPath}) {
  final candidates = [if (dllPath != null) dllPath, ...engineDllCandidates()];
  for (final path in candidates) {
    try {
      return DynamicLibrary.open(path);
    } catch (_) {}
  }
  return null;
}

// v1.5.0-T6 debug: timeline audio analysis (waveform/spectrogram/rms).
typedef CGetTimelineWaveform = Bool Function(
    Pointer<GhitaCtx>, Pointer<Float>, Int32, Int32);
typedef DGetTimelineWaveform = bool Function(
    Pointer<GhitaCtx>, Pointer<Float>, int, int);

typedef CSpectrogram = Bool Function(
    Pointer<GhitaCtx>, Pointer<Float>, Int32, Int32, Int32);
typedef DSpectrogram = bool Function(
    Pointer<GhitaCtx>, Pointer<Float>, int, int, int);

typedef CTimelineRms = Bool Function(
    Pointer<GhitaCtx>, Pointer<Float>, Int32, Int32);
typedef DTimelineRms = bool Function(
    Pointer<GhitaCtx>, Pointer<Float>, int, int);
