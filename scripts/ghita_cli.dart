// v1.5.0 T5-P5: Headless CLI for Ghita Edit — batch export, media info, thumbnails.
//
// Usage:
//   dart run scripts/ghita_cli.dart export <project.ghita> --output <path> [--codec h264] [--width 1920] [--height 1080] [--fps 30]
//   dart run scripts/ghita_cli.dart info <media_file>
//   dart run scripts/ghita_cli.dart thumbnail <media_file> --output <path.png> [--time 1000]
//   dart run scripts/ghita_cli.dart batch <batch.json>
//
// Exit codes: 0 success, 1 error.

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

import 'engine_ffi_shared.dart';

// Signatures live in engine_ffi_shared.dart (single source of truth) —
// local names below are ALIASES only; never declare Function(...) here.
typedef CGhitaEngineCreate = CCreate;
typedef DGhitaEngineCreate = DCreate;
typedef CGhitaEngineInit = CInit;
typedef DGhitaEngineInit = DInit;
typedef CGhitaEngineDestroy = CDestroy;
typedef DGhitaEngineDestroy = DDestroy;
typedef CGhitaEngineLoadMedia = CLoadMedia;
typedef DGhitaEngineLoadMedia = DLoadMedia;
typedef CGhitaEngineGetDurationMs = CGetDurationMs;
typedef DGhitaEngineGetDurationMs = DGetDurationMs;
typedef CGhitaEngineGetMediaInfo = CGetMediaInfo;
typedef DGhitaEngineGetMediaInfo = DGetMediaInfo;
typedef CGhitaEngineStartExportEx = CStartExportEx;
typedef DGhitaEngineStartExportEx = DStartExportEx;
typedef CGhitaEngineIsExporting = CIsExporting;
typedef DGhitaEngineIsExporting = DIsExporting;
typedef CGhitaEngineGetExportProgress = CGetExportProgress;
typedef DGhitaEngineGetExportProgress = DGetExportProgress;
typedef CGhitaEngineGetExportFileSize = CGetExportFileSize;
typedef DGhitaEngineGetExportFileSize = DGetExportFileSize;
typedef CGhitaEngineRenderFrameAt = CRenderFrameAt;
typedef DGhitaEngineRenderFrameAt = DRenderFrameAt;

void main(List<String> args) {
  if (args.isEmpty) {
    _printUsage();
    exit(1);
  }

  final command = args[0];
  switch (command) {
    case 'export':
      _cmdExport(args.sublist(1));
      break;
    case 'info':
      _cmdInfo(args.sublist(1));
      break;
    case 'thumbnail':
      _cmdThumbnail(args.sublist(1));
      break;
    case 'batch':
      _cmdBatch(args.sublist(1));
      break;
    default:
      stderr.writeln('Unknown command: $command');
      _printUsage();
      exit(1);
  }
}

void _printUsage() {
  stderr.writeln('Usage:');
  stderr.writeln('  ghita_cli export <project.ghita> --output <path> [--codec h264] [--width 1920] [--height 1080] [--fps 30]');
  stderr.writeln('  ghita_cli info <media_file>');
  stderr.writeln('  ghita_cli thumbnail <media_file> --output <path.png> [--time 1000]');
  stderr.writeln('  ghita_cli batch <batch.json>');
}

DynamicLibrary? _loadEngine() {
  // v1.5.0-T2 (P2): candidate list lives in engine_ffi_shared.dart — one
  // loader for every script instead of five diverging copies.
  final lib = loadEngineLibrary();
  if (lib == null) {
    stderr.writeln('ERROR: Could not find ghita_engine.dll');
  }
  return lib;
}

Map<String, String> _parseFlags(List<String> args) {
  final flags = <String, String>{};
  for (int i = 0; i < args.length; i++) {
    if (args[i].startsWith('--') && i + 1 < args.length) {
      flags[args[i].substring(2)] = args[i + 1];
      i++;
    }
  }
  return flags;
}

void _cmdExport(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('ERROR: Missing project path');
    exit(1);
  }
  final projectPath = args[0];
  final flags = _parseFlags(args.sublist(1));
  final output = flags['output'];
  if (output == null) {
    stderr.writeln('ERROR: --output required');
    exit(1);
  }
  final codec = flags['codec'] ?? 'h264';
  final width = int.tryParse(flags['width'] ?? '') ?? 1920;
  final height = int.tryParse(flags['height'] ?? '') ?? 1080;
  final fps = int.tryParse(flags['fps'] ?? '') ?? 30;

  final lib = _loadEngine();
  if (lib == null) exit(1);

  final create = lib.lookupFunction<CGhitaEngineCreate, DGhitaEngineCreate>('ghita_engine_create');
  final init = lib.lookupFunction<CGhitaEngineInit, DGhitaEngineInit>('ghita_engine_init');
  final destroy = lib.lookupFunction<CGhitaEngineDestroy, DGhitaEngineDestroy>('ghita_engine_destroy');
  final startExport = lib.lookupFunction<CGhitaEngineStartExportEx, DGhitaEngineStartExportEx>('ghita_engine_start_export_ex');
  final isExporting = lib.lookupFunction<CGhitaEngineIsExporting, DGhitaEngineIsExporting>('ghita_engine_is_exporting');
  final getProgress = lib.lookupFunction<CGhitaEngineGetExportProgress, DGhitaEngineGetExportProgress>('ghita_engine_get_export_progress');
  final getFileSize = lib.lookupFunction<CGhitaEngineGetExportFileSize, DGhitaEngineGetExportFileSize>('ghita_engine_get_export_file_size');

  final ctx = create();
  if (ctx == nullptr) {
    stderr.writeln('ERROR: Failed to create engine');
    exit(1);
  }
  try {
    init(ctx);
    // Load project JSON to set up timeline (simplified — just loads media).
    final projFile = File(projectPath);
    if (!projFile.existsSync()) {
      stderr.writeln('ERROR: Project file not found: $projectPath');
      exit(1);
    }
    stderr.writeln('{"status":"loading","project":"$projectPath"}');

    final outPtr = output.toNativeUtf8();
    final codecPtr = codec.toNativeUtf8();
    try {
      final ret = startExport(ctx, outPtr, width, height, fps, codecPtr, 5000000, true);
      if (ret != 0) {
        stderr.writeln('ERROR: Export failed to start (code $ret)');
        exit(1);
      }
      stderr.writeln('{"status":"exporting","output":"$output","codec":"$codec","resolution":"${width}x$height","fps":$fps}');

      while (isExporting(ctx)) {
        final progress = getProgress(ctx);
        stderr.writeln('{"status":"progress","value":${progress.toStringAsFixed(3)}}');
        sleep(const Duration(milliseconds: 500));
      }

      final size = getFileSize(ctx);
      if (size > 0) {
        stderr.writeln('{"status":"complete","size":$size,"output":"$output"}');
      } else {
        stderr.writeln('{"status":"failed","error":"Output file empty"}');
        exit(1);
      }
    } finally {
      calloc.free(outPtr);
      calloc.free(codecPtr);
    }
  } finally {
    destroy(ctx);
  }
}

void _cmdInfo(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('ERROR: Missing media path');
    exit(1);
  }
  final mediaPath = args[0];
  final lib = _loadEngine();
  if (lib == null) exit(1);

  final create = lib.lookupFunction<CGhitaEngineCreate, DGhitaEngineCreate>('ghita_engine_create');
  final init = lib.lookupFunction<CGhitaEngineInit, DGhitaEngineInit>('ghita_engine_init');
  final destroy = lib.lookupFunction<CGhitaEngineDestroy, DGhitaEngineDestroy>('ghita_engine_destroy');
  final loadMedia = lib.lookupFunction<CGhitaEngineLoadMedia, DGhitaEngineLoadMedia>('ghita_engine_load_media');
  final getDuration = lib.lookupFunction<CGhitaEngineGetDurationMs, DGhitaEngineGetDurationMs>('ghita_engine_get_duration_ms');
  final getMediaInfo = lib.lookupFunction<CGhitaEngineGetMediaInfo, DGhitaEngineGetMediaInfo>('ghita_engine_get_media_info');

  final ctx = create();
  if (ctx == nullptr) exit(1);
  try {
    init(ctx);
    final pathPtr = mediaPath.toNativeUtf8();
    try {
      loadMedia(ctx, pathPtr);
    } finally {
      calloc.free(pathPtr);
    }
    final duration = getDuration(ctx);
    final infoPtr = getMediaInfo(ctx);
    final info = infoPtr != nullptr ? infoPtr.toDartString() : '{}';
    stdout.writeln(jsonEncode({
      'file': mediaPath,
      'duration_ms': duration,
      'media_info': jsonDecode(info),
    }));
  } finally {
    destroy(ctx);
  }
}

void _cmdThumbnail(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('ERROR: Missing media path');
    exit(1);
  }
  final mediaPath = args[0];
  final flags = _parseFlags(args.sublist(1));
  final output = flags['output'];
  if (output == null) {
    stderr.writeln('ERROR: --output required');
    exit(1);
  }
  final timeMs = int.tryParse(flags['time'] ?? '') ?? 0;

  final lib = _loadEngine();
  if (lib == null) exit(1);

  final create = lib.lookupFunction<CGhitaEngineCreate, DGhitaEngineCreate>('ghita_engine_create');
  final init = lib.lookupFunction<CGhitaEngineInit, DGhitaEngineInit>('ghita_engine_init');
  final destroy = lib.lookupFunction<CGhitaEngineDestroy, DGhitaEngineDestroy>('ghita_engine_destroy');
  final loadMedia = lib.lookupFunction<CGhitaEngineLoadMedia, DGhitaEngineLoadMedia>('ghita_engine_load_media');
  final renderAt = lib.lookupFunction<CGhitaEngineRenderFrameAt, DGhitaEngineRenderFrameAt>('ghita_engine_render_frame_at');

  const w = 320;
  const h = 180;
  final ctx = create();
  if (ctx == nullptr) exit(1);
  try {
    init(ctx);
    final pathPtr = mediaPath.toNativeUtf8();
    try {
      loadMedia(ctx, pathPtr);
    } finally {
      calloc.free(pathPtr);
    }
    final buf = calloc<Uint8>(w * h * 4);
    try {
      final ok = renderAt(ctx, buf, w, h, timeMs);
      if (!ok) {
        stderr.writeln('ERROR: Render failed at ${timeMs}ms');
        exit(1);
      }
      // Write raw RGBA as PPM (simple image format).
      final file = File(output);
      final sink = file.openSync(mode: FileMode.write);
      sink.writeStringSync('P6\n$w $h\n255\n');
      for (int i = 0; i < w * h; i++) {
        sink.writeByteSync(buf[i * 4]);     // R
        sink.writeByteSync(buf[i * 4 + 1]); // G
        sink.writeByteSync(buf[i * 4 + 2]); // B
      }
      sink.closeSync();
      stderr.writeln('{"status":"complete","output":"$output","size":"${w}x$h","time_ms":$timeMs}');
    } finally {
      calloc.free(buf);
    }
  } finally {
    destroy(ctx);
  }
}

void _cmdBatch(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('ERROR: Missing batch JSON path');
    exit(1);
  }
  final batchFile = File(args[0]);
  if (!batchFile.existsSync()) {
    stderr.writeln('ERROR: Batch file not found: ${args[0]}');
    exit(1);
  }
  final jobs = jsonDecode(batchFile.readAsStringSync()) as List;
  stderr.writeln('{"status":"batch_start","jobs":${jobs.length}}');
  int completed = 0;
  for (int i = 0; i < jobs.length; i++) {
    final job = jobs[i] as Map<String, dynamic>;
    final input = job['input'] as String? ?? '';
    final output = job['output'] as String? ?? '';
    final codec = job['codec'] as String? ?? 'h264';
    final width = (job['width'] as num?)?.toInt() ?? 1920;
    final height = (job['height'] as num?)?.toInt() ?? 1080;
    final fps = (job['fps'] as num?)?.toInt() ?? 30;

    stderr.writeln('{"status":"job_start","index":$i,"input":"$input","output":"$output"}');
    // Re-use export logic inline.
    _doExportJob(input, output, codec, width, height, fps);
    completed++;
    stderr.writeln('{"status":"job_complete","index":$i,"completed":$completed,"total":${jobs.length}}');
  }
  stderr.writeln('{"status":"batch_complete","completed":$completed,"total":${jobs.length}}');
}

void _doExportJob(String input, String output, String codec, int width, int height, int fps) {
  final lib = _loadEngine();
  if (lib == null) return;

  final create = lib.lookupFunction<CGhitaEngineCreate, DGhitaEngineCreate>('ghita_engine_create');
  final init = lib.lookupFunction<CGhitaEngineInit, DGhitaEngineInit>('ghita_engine_init');
  final destroy = lib.lookupFunction<CGhitaEngineDestroy, DGhitaEngineDestroy>('ghita_engine_destroy');
  final startExport = lib.lookupFunction<CGhitaEngineStartExportEx, DGhitaEngineStartExportEx>('ghita_engine_start_export_ex');
  final isExporting = lib.lookupFunction<CGhitaEngineIsExporting, DGhitaEngineIsExporting>('ghita_engine_is_exporting');
  final getFileSize = lib.lookupFunction<CGhitaEngineGetExportFileSize, DGhitaEngineGetExportFileSize>('ghita_engine_get_export_file_size');

  final ctx = create();
  if (ctx == nullptr) return;
  try {
    init(ctx);
    final outPtr = output.toNativeUtf8();
    final codecPtr = codec.toNativeUtf8();
    try {
      startExport(ctx, outPtr, width, height, fps, codecPtr, 5000000, true);
      while (isExporting(ctx)) {
        sleep(const Duration(milliseconds: 200));
      }
      final size = getFileSize(ctx);
      stderr.writeln('{"status":"export_result","output":"$output","size":$size}');
    } finally {
      calloc.free(outPtr);
      calloc.free(codecPtr);
    }
  } finally {
    destroy(ctx);
  }
}

