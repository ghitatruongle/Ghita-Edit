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

import 'engine_ffi_shared.dart';

// Signatures live in engine_ffi_shared.dart (single source of truth) —
// local names below are ALIASES only; never declare Function(...) here.
typedef GhitaEngineContext = GhitaCtx;

class ExportCase {
  final String name;
  final String ext;
  final int w, h, fps;
  final String codec;
  final int bitrate;
  // v1.5.0-T2 (P3): optional channel layout for multichannel AAC rows.
  final String? channelLayout;

  const ExportCase(this.name, this.ext, this.w, this.h, this.fps, this.codec,
      this.bitrate, {this.channelLayout});
}

const cases = [
  ExportCase('mp4_h264', 'mp4', 320, 240, 30, 'h264', 1500000),
  ExportCase('mp4_h265', 'mp4', 320, 240, 30, 'h265', 1000000),
  ExportCase('mp4_vp9', 'mp4', 320, 240, 30, 'vp9', 800000),
  ExportCase('gif', 'gif', 160, 120, 10, 'gif', 0),
  ExportCase('mp3', 'mp3', 0, 0, 0, 'mp3', 128000),
  ExportCase('mov_h264', 'mov', 320, 240, 30, 'h264', 1500000),
  ExportCase('aac_51', 'mp4', 320, 240, 30, 'h264', 1500000,
      channelLayout: '5.1'),
  ExportCase('aac_71', 'mp4', 320, 240, 30, 'h264', 1500000,
      channelLayout: '7.1'),
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
  final ctx = lib.lookupFunction<CCreate, DCreate>('ghita_engine_create')();
  lib.lookupFunction<CInit, DInit>('ghita_engine_init')(ctx);
  final destroy = lib.lookupFunction<CDestroy, DDestroy>('ghita_engine_destroy');
  final upsert = lib.lookupFunction<CUpsertClip, DUpsertClip>('ghita_engine_upsert_clip');
  final clearClips =
      lib.lookupFunction<CClearClips, DClearClips>('ghita_engine_clear_clips');
  final startExportEx =
      lib.lookupFunction<CStartExportEx, DStartExportEx>('ghita_engine_start_export_ex');
  final isExporting =
      lib.lookupFunction<CIsExporting, DIsExporting>('ghita_engine_is_exporting');
  final getProgress =
      lib.lookupFunction<CGetExportProgress, DGetExportProgress>('ghita_engine_get_export_progress');
  final getFileSize =
      lib.lookupFunction<CGetExportFileSize, DGetExportFileSize>('ghita_engine_get_export_file_size');
  // v1.5.0-T2 (P3): new C export enabling multichannel verification.
  final setChannelLayout = lib.lookupFunction<CSetExportChannelLayout,
      DSetExportChannelLayout>('ghita_engine_set_export_channel_layout');

  // One timeline: a video clip (with audio) covering the whole 1.2s media.
  clearClips(ctx);
  final mp = mediaPath.toNativeUtf8();
  upsert(ctx, 1, mp, 0, 1200, 0, 0, 0, 1.0, 1.0, 1.0);
  calloc.free(mp);

  for (final c in cases) {
    final outPath = '$outDir/${c.name}.${c.ext}';
    final op = outPath.toNativeUtf8();
    final codec = c.codec.toNativeUtf8();
    // Always publish the layout so non-multichannel rows reset to stereo.
    final layout = (c.channelLayout ?? 'stereo').toNativeUtf8();
    setChannelLayout(ctx, layout);
    calloc.free(layout);
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