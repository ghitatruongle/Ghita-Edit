// v1.5.5-beta1: exact replication of engine_compare's "real media" scenario,
// step by step, so the real_timeline flake can be bisected instead of guessed.
//
//   dart run tool/flake_repro.dart [runs] [--no-export] [--no-mix] [--no-legacy]
//
// Any FAIL line names the step that first diverged.
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

// ignore_for_file: avoid_print

typedef CCreate = Pointer<Void> Function();
typedef DCreate = Pointer<Void> Function();
typedef CInt = Int32 Function(Pointer<Void>);
typedef DInt = int Function(Pointer<Void>);
typedef CLoad = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef DLoad = int Function(Pointer<Void>, Pointer<Utf8>);
typedef CUpsert = Int32 Function(Pointer<Void>, Int32, Pointer<Utf8>, Int64, Int64,
    Int64, Int32, Int32, Double, Double, Double);
typedef DUpsert = int Function(Pointer<Void>, int, Pointer<Utf8>, int, int, int, int, int,
    double, double, double);
typedef CRender = Bool Function(Pointer<Void>, Pointer<Uint8>, Int32, Int32, Int64);
typedef DRender = bool Function(Pointer<Void>, Pointer<Uint8>, int, int, int);
typedef CExport = Int32 Function(Pointer<Void>, Pointer<Utf8>, Int32, Int32, Int32);
typedef DExport = int Function(Pointer<Void>, Pointer<Utf8>, int, int, int);
typedef CBool = Bool Function(Pointer<Void>);
typedef DBool = bool Function(Pointer<Void>);
typedef CWave = Bool Function(Pointer<Void>, Pointer<Float>, Int32);
typedef DWave = bool Function(Pointer<Void>, Pointer<Float>, int);
typedef CMix = Bool Function(Pointer<Void>, Int64, Int64, Pointer<Float>, Int32);
typedef DMix = bool Function(Pointer<Void>, int, int, Pointer<Float>, int);

class Eng {
  final String tag;
  final DynamicLibrary lib;
  late Pointer<Void> ctx;
  late DCreate create;
  late DInt init;
  late DInt destroy;
  late DLoad load;
  late DUpsert upsert;
  late DRender render;
  late DExport startExport;
  late DBool isExporting;
  late DWave waveform;
  late DMix mix;

  Eng(this.tag, String path) : lib = DynamicLibrary.open(path) {
    create = lib.lookupFunction<CCreate, DCreate>('ghita_engine_create');
    init = lib.lookupFunction<CInt, DInt>('ghita_engine_init');
    destroy = lib.lookupFunction<CInt, DInt>('ghita_engine_destroy');
    load = lib.lookupFunction<CLoad, DLoad>('ghita_engine_load_media');
    upsert = lib.lookupFunction<CUpsert, DUpsert>('ghita_engine_upsert_clip');
    render = lib.lookupFunction<CRender, DRender>('ghita_engine_render_frame_at');
    startExport = lib.lookupFunction<CExport, DExport>('ghita_engine_start_export_ex');
    isExporting = lib.lookupFunction<CBool, DBool>('ghita_engine_is_exporting');
    waveform = lib.lookupFunction<CWave, DWave>('ghita_engine_get_audio_waveform');
    mix = lib.lookupFunction<CMix, DMix>('ghita_engine_mix_audio_window');
  }
}

const w = 64, h = 36;
const n = w * h * 4;

int hashOf(Pointer<Uint8> b) {
  var v = 0;
  for (var i = 0; i < n; i++) {
    v = (v * 31 + b[i]) & 0x7fffffff;
  }
  return v;
}

void main(List<String> args) {
  final runs = int.tryParse(args.isNotEmpty ? args[0] : '10') ?? 10;
  final noExport = args.contains('--no-export');
  final noMix = args.contains('--no-mix');
  final noLegacy = args.contains('--no-legacy');

  final cpp = Eng('cpp', args.length > 1 && args[1].endsWith('.dll')
      ? args[1]
      : 'E:/Ghita Edit/native_engine/build/libghita_engine.dll');
  final rust = Eng('rust', 'E:/Ghita Edit/native_engine_rust/target/release/ghita_engine.dll');

  final mp4 = File('test_video.mp4').absolute.path;
  final wav = File('test_sine.wav').absolute.path;
  final buf = calloc<Uint8>(n);
  final wa = calloc<Float>(400);
  final wb = calloc<Float>(400);
  final mp4p = mp4.toNativeUtf8();
  final wap = wav.toNativeUtf8();

  var fails = 0;
  var firstCpp = 0, firstRust = 0;
  for (var run = 0; run < runs; run++) {
    if (args.contains('--stress')) {
      // Mirror engine_compare's SYNTHETIC scenario: renders + start/cancel
      // export + a 4-thread render stress on throwaway contexts. If the media
      // scenario only flakes AFTER this, the culprit is leftover
      // process/FFmpeg state, not the media path itself.
      for (final e in [cpp, rust]) {
        final c0 = e.create();
        e.init(c0);
        for (var i = 0; i < 10; i++) {
          e.render(c0, buf, w, h, i * 37);
        }
        final op = 'flake_stress.raw'.toNativeUtf8();
        e.startExport(c0, op, w, h, 10);
        var waited = 0;
        while (e.isExporting(c0) && waited < 500) {
          sleep(const Duration(milliseconds: 10));
          waited++;
        }
        calloc.free(op);
        e.destroy(c0);
      }
      // NOTE: the harness also runs a 4-thread render stress before the
      // media scenario; Dart isolates can't share FFI pointers safely, so
      // that step is not replicated here (documented gap).
    }
    cpp.ctx = cpp.create();
    rust.ctx = rust.create();
    cpp.init(cpp.ctx);
    rust.init(rust.ctx);
    cpp.load(cpp.ctx, mp4p);
    rust.load(rust.ctx, mp4p);

    if (!noLegacy) {
      // legacy decode renders (real_decode@*)
      for (final pos in [0, 200, 700, 1500, 3000]) {
        cpp.render(cpp.ctx, buf, w, h, pos);
        final a = hashOf(buf);
        rust.render(rust.ctx, buf, w, h, pos);
        final b = hashOf(buf);
        if (a != b) print('run $run: legacy@$pos MISMATCH $a vs $b');
      }
    }
    cpp.load(cpp.ctx, wap);
    rust.load(rust.ctx, wap);
    cpp.waveform(cpp.ctx, wa, 400);
    rust.waveform(rust.ctx, wb, 400);
    cpp.upsert(cpp.ctx, 1, mp4p, 0, 2000, 0, 0, 0, 1.0, 1.0, 1.0);
    rust.upsert(rust.ctx, 1, mp4p, 0, 2000, 0, 0, 0, 1.0, 1.0, 1.0);
    cpp.upsert(cpp.ctx, 2, wap, 0, 2000, 0, 1, 1, 1.0, 1.0, 1.0);
    rust.upsert(rust.ctx, 2, wap, 0, 2000, 0, 1, 1, 1.0, 1.0, 1.0);

    var bad = false;
    for (final pos in [0, 300, 900, 1800]) {
      cpp.render(cpp.ctx, buf, w, h, pos);
      final a = hashOf(buf);
      rust.render(rust.ctx, buf, w, h, pos);
      final b = hashOf(buf);
      // Self-consistency: is EITHER engine varying run-to-run?
      if (pos == 0) {
        if (firstCpp == 0) firstCpp = a;
        if (firstRust == 0) firstRust = b;
        if (a != firstCpp) print('run $run: CPP self-differs @$pos $firstCpp -> $a');
        if (b != firstRust) print('run $run: RUST self-differs @$pos $firstRust -> $b');
      }
      if (a != b) {
        print('run $run: real_timeline@$pos MISMATCH cpp=$a rust=$b');
        bad = true;
      }
    }
    if (!noMix) {
      cpp.mix(cpp.ctx, 0, 100, wa, 400);
      rust.mix(rust.ctx, 0, 100, wb, 400);
    }
    if (!noExport) {
      final op = 'flake_exp_${cpp.tag}_$run.mp4'.toNativeUtf8();
      cpp.startExport(cpp.ctx, op, w, h, 10);
      rust.startExport(rust.ctx, op, w, h, 10);
      calloc.free(op);
      var waited = 0;
      while ((cpp.isExporting(cpp.ctx) || rust.isExporting(rust.ctx)) &&
          waited < 2000) {
        sleep(const Duration(milliseconds: 10));
        waited++;
      }
    }
    if (bad) fails++;
    cpp.destroy(cpp.ctx);
    rust.destroy(rust.ctx);
  }
  calloc.free(buf);
  calloc.free(wa);
  calloc.free(wb);
  calloc.free(mp4p);
  calloc.free(wap);
  print('=== $fails/$runs runs had a real_timeline mismatch '
      '(flags: export=${!noExport} mix=${!noMix} legacy=${!noLegacy}) ===');
}
