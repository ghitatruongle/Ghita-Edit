// Diagnostic CLI (not app code): prints are the whole point of this probe.
// ignore_for_file: avoid_print

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

// v1.5.5-beta1: isolate the engine_compare flake.
//   mode "solo"  → render one engine alone, N times, hash the frames
//   mode "inter" → alternate the two engines in ONE process (like the harness)
// Both DLLs are loaded in the same process, so any mismatch here points at
// cross-engine FFmpeg global state, not at either engine's own logic.
typedef CCreate = Pointer<Void> Function();
typedef DCreate = Pointer<Void> Function();
typedef CInt = Int32 Function(Pointer<Void>);
typedef DInt = int Function(Pointer<Void>);
typedef CUpsert = Int32 Function(
    Pointer<Void>, Int32, Pointer<Utf8>, Int64, Int64, Int64, Int32, Int32, Double, Double, Double);
typedef DUpsert = int Function(Pointer<Void>, int, Pointer<Utf8>, int, int, int, int, int, double,
    double, double);
typedef CRender = Bool Function(Pointer<Void>, Pointer<Uint8>, Int32, Int32, Int64);
typedef DRender = bool Function(Pointer<Void>, Pointer<Uint8>, int, int, int);
typedef CVoid = Void Function(Pointer<Void>, Pointer<Utf8>);
typedef CVoidD = void Function(Pointer<Void>, Pointer<Utf8>);


class Engine {
  final DynamicLibrary lib;
  late final DCreate create;
  late final DInt init;
  late final DUpsert upsert;
  late final DRender render;
  late final DInt destroy;
  late final void Function(Pointer<Void>, Pointer<Utf8>) load;
  Pointer<Void> ctx = nullptr;

  Engine(String path) : lib = DynamicLibrary.open(path) {
    create = lib.lookupFunction<CCreate, DCreate>('ghita_engine_create');
    init = lib.lookupFunction<CInt, DInt>('ghita_engine_init');
    upsert = lib.lookupFunction<CUpsert, DUpsert>('ghita_engine_upsert_clip');
    render = lib.lookupFunction<CRender, DRender>('ghita_engine_render_frame_at');
    destroy = lib.lookupFunction<CInt, DInt>('ghita_engine_destroy');
    load = lib.lookupFunction<CVoid, CVoidD>('ghita_engine_load_media');
  }

  void open(String mp4, String wav, int w, int h) {
    ctx = create();
    init(ctx);
    final p1 = mp4.toNativeUtf8();
    final p2 = wav.toNativeUtf8();
    load(ctx, p2); // the harness loads the WAV last (mirrors its order)
    upsert(ctx, 1, p1, 0, 2000, 0, 0, 0, 1.0, 1.0, 1.0);
    upsert(ctx, 2, p2, 0, 2000, 0, 1, 1, 1.0, 1.0, 1.0);
    calloc.free(p1);
    calloc.free(p2);
  }
}

int frameHash(Pointer<Uint8> buf, int n) {
  var h = 0;
  for (var i = 0; i < n; i++) {
    h = (h * 31 + buf[i]) & 0x7fffffff;
  }
  return h;
}

void main(List<String> args) {
  final mode = args[0];
  final cpp = Engine(args[1]);
  final rust = Engine(args[2]);
  const w = 48, h = 36;
  const n = w * h * 4;
  final mp4 = File('test_video.mp4').absolute.path;
  final wav = File('test_sine.wav').absolute.path;
  final buf = calloc<Uint8>(n);

  if (mode == 'solo') {
    // Same engine alone, opened and rendered 12 times.
    final seen = <String>{};
    var runs = 0;
    for (var i = 0; i < 12; i++) {
      final e = i.isEven ? cpp : rust;
      e.open(mp4, wav, w, h);
      final hashes = <int>[];
      for (final pos in [0, 300, 900, 1800]) {
        e.render(e.ctx, buf, w, h, pos);
        hashes.add(frameHash(buf, n));
      }
      seen.add(hashes.join('|'));
      runs++;
      e.destroy(e.ctx);
    }
    print('solo: $runs runs → ${seen.length} distinct frame-hash sets');
    print(seen.length == 2
        ? 'VERDICT: each engine is deterministic solo (2 expected sets)'
        : 'VERDICT: an engine is NON-deterministic on its own');
  } else {
    // Both engines alive at once, alternating renders (the harness's shape).
    cpp.open(mp4, wav, w, h);
    rust.open(mp4, wav, w, h);
    var mismatches = 0;
    final total = 20;
    for (var i = 0; i < total; i++) {
      final pos = [0, 300, 900, 1800][i % 4];
      final a = <int>[];
      final b = <int>[];
      cpp.render(cpp.ctx, buf, w, h, pos);
      a.add(frameHash(buf, n));
      rust.render(rust.ctx, buf, w, h, pos);
      b.add(frameHash(buf, n));
      if (a.first != b.first) mismatches++;
    }
    print('interleaved: $mismatches/$total renders differ between the two engines');
    print(mismatches == 0
        ? 'VERDICT: engines agree when interleaved'
        : 'VERDICT: engines DISAGREE when interleaved → cross-engine state, not either engine alone');
  }
  calloc.free(buf);
}
