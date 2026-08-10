// Export matrix driver — P3.12 (PLAN_1.1.0): exports the SAME timeline through
// every supported output format and reports per-format results so
// scripts/verify_export_matrix.sh can ffprobe-verify each file.
// ignore_for_file: avoid_print — CLI tool; stdout is the machine-readable
// output contract consumed by verify_export_matrix.sh.
//
// Usage:
//   export PATH="/c/msys64/mingw64/bin:$PATH"
//   dart run scripts/export_matrix.dart --dll native_engine/build/libghita_engine.dll
//       --media native_engine/build/test_media.mp4 --out build/export_matrix
//
// Output: <out>/<name>.<ext> files + one JSON line per export on stdout.
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

class ExportCase {
  final String name;
  final String ext;
  final int w, h, fps;
  final String codec;
  final int bitrate;

  const ExportCase(this.name, this.ext, this.w, this.h, this.fps, this.codec, this.bitrate);
}

const cases = [
  ExportCase('mp4_h264', 'mp4', 320, 240, 30, 'h264', 1500000),
  ExportCase('mp4_h265', 'mp4', 320, 240, 30, 'h265', 1000000),
  ExportCase('mp4_vp9', 'mp4', 320, 240, 30, 'vp9', 800000),
  ExportCase('gif', 'gif', 160, 120, 10, 'gif', 0),
  ExportCase('mp3', 'mp3', 0, 0, 0, 'mp3', 128000),
  ExportCase('mov_h264', 'mov', 320, 240, 30, 'h264', 1500000),
];

void main(List<String> args) {
  var dllPath = 'native_engine/build/libghita_engine.dll';
  var mediaPath = 'native_engine/build/test_media.mp4';
  var outDir = 'build/export_matrix';
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--dll' && i + 1 < args.length) dllPath = args[++i];
    if (args[i] == '--media' && i + 1 < args.length) mediaPath = args[++i];
    if (args[i] == '--out' && i + 1 < args.length) outDir = args[++i];
  }

  if (!File(mediaPath).existsSync()) {
    stderr.writeln('ERROR: media not found: $mediaPath');
    exit(2);
  }
  Directory(outDir).createSync(recursive: true);

  final lib = DynamicLibrary.open(dllPath);
  final ctx = lib.lookupFunction<_CCreate, _DCreate>('ghita_engine_create')();
  lib.lookupFunction<_CInit, _DInit>('ghita_engine_init')(ctx);
  final destroy = lib.lookupFunction<_CDestroy, _DDestroy>('ghita_engine_destroy');
  final upsert = lib.lookupFunction<_CUpsert, _DUpsert>('ghita_engine_upsert_clip');
  final clearClips = lib.lookupFunction<Void Function(Pointer<GhitaEngineContext>),
      void Function(Pointer<GhitaEngineContext>)>('ghita_engine_clear_clips');
  final startExportEx =
      lib.lookupFunction<_CStartExportEx, _DStartExportEx>('ghita_engine_start_export_ex');
  final isExporting =
      lib.lookupFunction<_CIsExporting, _DIsExporting>('ghita_engine_is_exporting');
  final getProgress =
      lib.lookupFunction<_CGetProgress, _DGetProgress>('ghita_engine_get_export_progress');
  final getFileSize =
      lib.lookupFunction<_CGetFileSize, _DGetFileSize>('ghita_engine_get_export_file_size');

  // One timeline: a video clip (with audio) covering the whole 1.2s media.
  clearClips(ctx);
  final mp = mediaPath.toNativeUtf8();
  upsert(ctx, 1, mp, 0, 1200, 0, 0, 0, 1.0, 1.0, 1.0);
  calloc.free(mp);

  for (final c in cases) {
    final outPath = '$outDir/${c.name}.${c.ext}';
    final op = outPath.toNativeUtf8();
    final codec = c.codec.toNativeUtf8();
    final started =
        startExportEx(ctx, op, c.w, c.h, c.fps, codec, c.bitrate, true) == 0;
    calloc.free(codec);
    calloc.free(op);

    final stopwatch = Stopwatch()..start();
    if (started) {
      while (isExporting(ctx)) {
        sleep(const Duration(milliseconds: 50));
      }
    }
    stopwatch.stop();
    final progress = getProgress(ctx);
    final size = getFileSize(ctx);
    final fileExists = File(outPath).existsSync();
    print(jsonEncode({
      'case': c.name,
      'started': started,
      'progress': progress,
      'size': size,
      'file': fileExists,
      'ms': stopwatch.elapsedMilliseconds,
    }));
  }

  destroy(ctx);
}