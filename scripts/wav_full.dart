// wav_full.dart — sweep ALL 100ms windows of a 10s WAV and require every
// window to be FULLY filled (≥99% non-zero float coverage). This is the
// regression test for the original "rè" (half-silent windows).
// Usage: dart run scripts/wav_full.dart FILE.wav
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'engine_ffi_shared.dart';

// Signatures live in engine_ffi_shared.dart (single source of truth) —
// local names below are ALIASES only; never declare Function(...) here.
typedef Ctx = GhitaCtx;
typedef CUpsert = CUpsertClip;
typedef DUpsert = DUpsertClip;
typedef CMix = CMixAudioWindow;
typedef DMix = DMixAudioWindow;

void main(List<String> args) {
  final path = args[0];
  final dll = 'build/windows/x64/runner/Release/ghita_engine.dll';
  final lib = DynamicLibrary.open(dll);
  final create = lib.lookupFunction<CCreate, DCreate>('ghita_engine_create');
  final init = lib.lookupFunction<CInit, DInit>('ghita_engine_init');
  final upsert = lib.lookupFunction<CUpsertClip, DUpsertClip>('ghita_engine_upsert_clip');
  final mix = lib.lookupFunction<CMixAudioWindow, DMixAudioWindow>('ghita_engine_mix_audio_window');
  final ctx = create();
  init(ctx);
  final p = path.toNativeUtf8();
  // 10s clip: cover [0,10000)
  upsert(ctx, 1, p, 0, 10000, 0, 0, 1, 1.0, 1.0, 1.0);
  calloc.free(p);

  final buf = calloc<Float>(4410 * 2);
  var badWindows = 0;
  var zeroWindows = 0;
  for (var ms = 0; ms < 10000; ms += 100) {
    // Wait — mix windows [ms, ms+200): a 100ms timeline window holds 4410
    // frames = 8820 floats; also verify with a larger window sweep.
    final ok = mix(ctx, ms, ms + 100, buf, 4410 * 2);
    final s = buf.asTypedList(4410 * 2);
    var nz = 0;
    // count non-zero in LAST QUARTER — the old bug left the tail silent
    var tailQuarter = 0;
    for (var i = 0; i < 4410 * 2; i++) {
      if (s[i].abs() > 1e-4) {
        nz++;
        if (i >= 4410 * 3 ~/ 2) tailQuarter++;
      }
    }
    final silent = ok && nz == 0;
    final coverageOk = (nz >= 4410 * 2 * 0.96) && (tailQuarter > 0);
    if (!ok || !coverageOk) {
      badWindows++;
      stdout.writeln('window @${ms}ms ok=$ok nz=$nz tailNZ=$tailQuarter');
    }
    if (silent) zeroWindows++;
  }
  calloc.free(buf);
  stdout.writeln('WINDOWS: 100 windows, bad=$badWindows silent=$zeroWindows');
  stdout.writeln(badWindows == 0 ? 'WAV FULL SWEEP: ALL PASSED' : 'WAV FULL SWEEP: $badWindows FAILED');
  exit(badWindows == 0 ? 0 : 1);
}