// Track 2 (PLAN_1.1.0) benchmark — measures the engine BEFORE/AFTER each
// optimization so every phase has a before/after number.
//
// Usage:
//   export PATH="/c/msys64/mingw64/bin:$PATH"
//   dart run tool/bench.dart [--dll PATH] [--out build/bench.json]
//
// Metrics:
//   preview_20clips_fps   renderFrameRgba 640x360, 20 clips / 5 tracks
//   skin_retouch_fps      render with global filter 21 (Skin Retouch)
//   text_clips_fps        render timeline of 10 text clips (GDI path)
//   export_640_ms         export 2s 640x360 h264 (wall clock)
//   export_1080_skin_ms   export 1s 1080p with SkinRetouch (wall clock)
//   rss_scrub_mb          process RSS after scrubbing 40 distinct positions
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';


import 'package:ffi/ffi.dart';

final class GhitaEngineContext extends Opaque {}

typedef _CCreate = Pointer<GhitaEngineContext> Function();
typedef _DCreate = Pointer<GhitaEngineContext> Function();
typedef _CInit = Int32 Function(Pointer<GhitaEngineContext>);
typedef _DInit = int Function(Pointer<GhitaEngineContext>);
typedef _CDestroy = Void Function(Pointer<GhitaEngineContext>);
typedef _DDestroy = void Function(Pointer<GhitaEngineContext>);
typedef _CUpsert = Int32 Function(
    Pointer<GhitaEngineContext>, Int32, Pointer<Utf8>, Int64, Int64, Int64,
    Int32, Int32, Float, Float, Float);
typedef _DUpsert = int Function(
    Pointer<GhitaEngineContext>, int, Pointer<Utf8>, int, int, int,
    int, int, double, double, double);
typedef _CRender = Bool Function(
    Pointer<GhitaEngineContext>, Pointer<Uint8>, Int32, Int32);
typedef _DRender = bool Function(
    Pointer<GhitaEngineContext>, Pointer<Uint8>, int, int);
typedef _CApplyFilter = Void Function(
    Pointer<GhitaEngineContext>, Int32, Float);
typedef _DApplyFilter = void Function(
    Pointer<GhitaEngineContext>, int, double);
typedef _CSetClipText = Int32 Function(Pointer<GhitaEngineContext>, Int32,
    Pointer<Utf8>, Float, Uint32);
typedef _DSetClipText = int Function(
    Pointer<GhitaEngineContext>, int, Pointer<Utf8>, double, int);
typedef _CClearClips = Void Function(Pointer<GhitaEngineContext>);
typedef _DClearClips = void Function(Pointer<GhitaEngineContext>);
typedef _CStartExportEx = Int32 Function(
  Pointer<GhitaEngineContext>, Pointer<Utf8>,
  Int32, Int32, Int32, Pointer<Utf8>, Int64, Bool,
);
typedef _DStartExportEx = int Function(
  Pointer<GhitaEngineContext>, Pointer<Utf8>,
  int, int, int, Pointer<Utf8>, int, bool,
);
typedef _CIsExporting = Bool Function(Pointer<GhitaEngineContext>);
typedef _DIsExporting = bool Function(Pointer<GhitaEngineContext>);
typedef _CGetProgress = Float Function(Pointer<GhitaEngineContext>);
typedef _DGetProgress = double Function(Pointer<GhitaEngineContext>);
typedef _CGetFileSize = Int64 Function(Pointer<GhitaEngineContext>);
typedef _DGetFileSize = int Function(Pointer<GhitaEngineContext>);
typedef _CSeek = Void Function(Pointer<GhitaEngineContext>, Int64);
typedef _DSeek = void Function(Pointer<GhitaEngineContext>, int);

class BenchApi {
  final Pointer<GhitaEngineContext> ctx; // ignore: library_private_types_in_public_api
  final _DRender render; // ignore: library_private_types_in_public_api
  final _DApplyFilter applyFilter; // ignore: library_private_types_in_public_api
  final _DUpsert upsert; // ignore: library_private_types_in_public_api
  final _DSetClipText setClipText; // ignore: library_private_types_in_public_api
  final _DClearClips clearClips; // ignore: library_private_types_in_public_api
  final _DStartExportEx startExportEx; // ignore: library_private_types_in_public_api
  final _DIsExporting isExporting; // ignore: library_private_types_in_public_api
  final _DGetProgress getProgress; // ignore: library_private_types_in_public_api
  final _DGetFileSize getFileSize; // ignore: library_private_types_in_public_api
  final _DSeek seek; // ignore: library_private_types_in_public_api

  BenchApi(this.ctx, this.render, this.applyFilter, this.upsert,
      this.setClipText, this.clearClips, this.startExportEx, this.isExporting,
      this.getProgress, this.getFileSize, this.seek);

  double renderFps(int frames, int w, int h) {
    final buf = calloc<Uint8>(w * h * 4);
    try {
      final t0 = DateTime.now();
      for (var i = 0; i < frames; i++) {
        if (!render(ctx, buf, w, h)) throw StateError('render failed');
      }
      final ms = DateTime.now().difference(t0).inMilliseconds;
      return frames / (ms / 1000.0);
    } finally {
      calloc.free(buf);
    }
  }

  int exportMs(String outPath, int w, int h, int fps, String codec,
      int bitrate, bool audio) {
    final op = outPath.toNativeUtf8();
    final c = codec.toNativeUtf8();
    try {
      final t0 = DateTime.now();
      if (startExportEx(ctx, op, w, h, fps, c, bitrate, audio) != 0) {
        throw StateError('export start failed');
      }
      while (isExporting(ctx)) {
        sleep(const Duration(milliseconds: 50));
      }
      final ms = DateTime.now().difference(t0).inMilliseconds;
      final prog = getProgress(ctx);
      final size = getFileSize(ctx);
      if (prog < 1.0 || size <= 0) throw StateError('export failed');
      return ms;
    } finally {
      calloc.free(op);
      calloc.free(c);
    }
  }

  void buildTimeline20Clips() {
    clearClips(ctx);
    for (var i = 0; i < 20; i++) {
      final p = 'clip$i.mp4'.toNativeUtf8();
      upsert(ctx, i + 1, p, i * 500, 500, 0, i % 5, 0, 1.0, 1.0, 1.0);
      calloc.free(p);
    }
  }

  void buildTextClips10() {
    clearClips(ctx);
    for (var i = 0; i < 10; i++) {
      final empty = ''.toNativeUtf8();
      upsert(ctx, i + 1, empty, i * 500, 1000, 0, 1, 3, 1.0, 1.0, 1.0);
      calloc.free(empty);
      final t = 'Text clip $i'.toNativeUtf8();
      setClipText(ctx, i + 1, t, 36.0, 0xFFFFFFFF);
      calloc.free(t);
    }
  }

  void buildSingleClip(int durationMs) {
    clearClips(ctx);
    final p = 'bench.mp4'.toNativeUtf8();
    upsert(ctx, 1, p, 0, durationMs, 0, 0, 0, 1.0, 1.0, 1.0);
    calloc.free(p);
  }

  int rssMb() => (ProcessInfo.currentRss / (1024 * 1024)).round();
}

void main(List<String> args) {
  var dllPath = 'native_engine/build/libghita_engine.dll';
  var outPath = 'build/bench.json';
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--dll' && i + 1 < args.length) dllPath = args[++i];
    if (args[i] == '--out' && i + 1 < args.length) outPath = args[++i];
  }

  final lib = DynamicLibrary.open(dllPath);
  final api = BenchApi(
    lib.lookupFunction<_CCreate, _DCreate>('ghita_engine_create')(),
    lib.lookupFunction<_CRender, _DRender>('ghita_engine_render_frame_rgba'),
    lib.lookupFunction<_CApplyFilter, _DApplyFilter>('ghita_engine_apply_filter'),
    lib.lookupFunction<_CUpsert, _DUpsert>('ghita_engine_upsert_clip'),
    lib.lookupFunction<_CSetClipText, _DSetClipText>('ghita_engine_set_clip_text'),
    lib.lookupFunction<_CClearClips, _DClearClips>('ghita_engine_clear_clips'),
    lib.lookupFunction<_CStartExportEx, _DStartExportEx>('ghita_engine_start_export_ex'),
    lib.lookupFunction<_CIsExporting, _DIsExporting>('ghita_engine_is_exporting'),
    lib.lookupFunction<_CGetProgress, _DGetProgress>('ghita_engine_get_export_progress'),
    lib.lookupFunction<_CGetFileSize, _DGetFileSize>('ghita_engine_get_export_file_size'),
    lib.lookupFunction<_CSeek, _DSeek>('ghita_engine_seek'),
  );

  if (api.ctx.address == 0) throw StateError('create failed');
  lib.lookupFunction<_CInit, _DInit>('ghita_engine_init')(api.ctx);

  final results = <String, dynamic>{};
  stdout.writeln('=== Track 2 benchmark ===');
  stdout.writeln('dll: $dllPath');

  // 1. Preview FPS — 20 clips / 5 tracks.
  api.buildTimeline20Clips();
  api.seek(api.ctx, 400);
  results['preview_20clips_fps'] =
      double.parse(api.renderFps(300, 640, 360).toStringAsFixed(1));
  stdout.writeln('preview_20clips_fps = ${results['preview_20clips_fps']}');

  // 2. Skin Retouch (global filter 21).
  api.buildSingleClip(60000);
  api.applyFilter(api.ctx, 21, 1.0);
  api.seek(api.ctx, 500);
  results['skin_retouch_fps'] =
      double.parse(api.renderFps(100, 640, 360).toStringAsFixed(1));
  stdout.writeln('skin_retouch_fps = ${results['skin_retouch_fps']}');
  api.applyFilter(api.ctx, 0, 1.0);

  // 3. Text clips (GDI path).
  api.buildTextClips10();
  api.seek(api.ctx, 400);
  results['text_clips_fps'] =
      double.parse(api.renderFps(100, 640, 360).toStringAsFixed(1));
  stdout.writeln('text_clips_fps = ${results['text_clips_fps']}');

  // 4. Export 2s 640x360 h264.
  api.buildSingleClip(2000);
  results['export_640_ms'] = api.exportMs(
      'build/bench_export_640.mp4', 640, 360, 30, 'h264', 2000000, true);
  stdout.writeln('export_640_ms = ${results['export_640_ms']}');

  // 5. Export 1s 1080p with SkinRetouch (heaviest path).
  api.buildSingleClip(1000);
  api.applyFilter(api.ctx, 21, 1.0);
  results['export_1080_skin_ms'] = api.exportMs(
      'build/bench_export_1080_skin.mp4', 1920, 1080, 30, 'h264', 4000000, true);
  stdout.writeln('export_1080_skin_ms = ${results['export_1080_skin_ms']}');
  api.applyFilter(api.ctx, 0, 1.0);

  // 6. RSS after scrubbing 40 distinct positions (exercises the Dart caches).
  api.buildSingleClip(40000);
  final rssBefore = api.rssMb();
  for (var i = 0; i < 40; i++) {
    api.seek(api.ctx, i * 1000);
    api.renderFps(1, 640, 360);
  }
  results['rss_scrub_mb'] = api.rssMb();
  stdout.writeln('rss_scrub_mb = ${results['rss_scrub_mb']} (before=$rssBefore)');

  lib.lookupFunction<_CDestroy, _DDestroy>('ghita_engine_destroy')(api.ctx);

  File(outPath).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(results));
  stdout.writeln('saved: $outPath');
}
