// Track 1 (PLAN_1.1.0) release-gate smoke: real 10-minute session against the
// WORKING-TREE engine DLL — import → continuous playback with seeks → export
// MP4 → verify output. No commit/push involved; this only validates the
// freshly built engine.
//
// Usage:
//   export PATH="/c/msys64/mingw64/bin:$PATH"   # FFmpeg transitive deps
//   dart run scripts/smoke_track1.dart --dll native_engine/build/libghita_engine.dll
//       [--media test_video.mp4] [--session-minutes 9]
//
// Exit code 0 = PASS, 1 = FAIL.
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';

import 'engine_ffi_shared.dart';

// Signatures live in engine_ffi_shared.dart (single source of truth) —
// local names below are ALIASES only; never declare Function(...) here.
typedef GhitaEngineContext = GhitaCtx;
typedef _DGetPosition = DGetPositionMs;
typedef _DPause = DPause;
typedef _DRender = DRenderFrame;

int _failures = 0;
void check(bool ok, String what) {
  if (!ok) {
    _failures++;
    stdout.writeln('  [FAIL] $what');
  } else {
    stdout.writeln('  [PASS] $what');
  }
}


Future<void> playFromZeroCheck(
    Pointer<GhitaEngineContext> ctx,
    // ignore: library_private_types_in_public_api
    _DGetPosition getPosition,
    // ignore: library_private_types_in_public_api
    _DRender render,
    // ignore: library_private_types_in_public_api
    _DPause pause,
    int waitMs) async {
  final t0 = DateTime.now();
  int lastPos = -1;
  final buf = calloc<Uint8>(640 * 360 * 4);
  while (DateTime.now().difference(t0).inMilliseconds < waitMs) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    render(ctx, buf, 640, 360); // the engine advances INSIDE render
    lastPos = getPosition(ctx);
  }
  calloc.free(buf);
  stdout.writeln('  play-from-0 check: pos after ${waitMs}ms = $lastPos ms');
  check(lastPos > 50,
      'playhead advanced from 0 without manual seek (bug #4)');
  pause(ctx);
}

Future<void> main(List<String> args) async {
  var dllPath = 'native_engine/build/libghita_engine.dll';
  var mediaPath = 'test_video.mp4';
  var sessionMinutes = 9;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--dll' && i + 1 < args.length) dllPath = args[++i];
    if (args[i] == '--media' && i + 1 < args.length) mediaPath = args[++i];
    if (args[i] == '--session-minutes' && i + 1 < args.length) {
      sessionMinutes = int.parse(args[++i]);
    }
  }

  stdout.writeln('=== Track 1 release-gate smoke ===');
  stdout.writeln('dll: $dllPath');
  stdout.writeln('media: $mediaPath (exists=${File(mediaPath).existsSync()})');
  stdout.writeln('session: ${sessionMinutes}min play + export');

  final lib = DynamicLibrary.open(dllPath);
  final create = lib.lookupFunction<CCreate, DCreate>('ghita_engine_create');
  final init = lib.lookupFunction<CInit, DInit>('ghita_engine_init');
  final destroy = lib.lookupFunction<CDestroy, DDestroy>('ghita_engine_destroy');
  final loadMedia = lib.lookupFunction<CLoadMedia, DLoadMedia>('ghita_engine_load_media');
  final getDuration = lib.lookupFunction<CGetDurationMs, DGetDurationMs>('ghita_engine_get_duration_ms');
  final getPosition = lib.lookupFunction<CGetPositionMs, DGetPositionMs>('ghita_engine_get_position_ms');
  final play = lib.lookupFunction<CPlay, DPlay>('ghita_engine_play');
  final pause = lib.lookupFunction<CPause, DPause>('ghita_engine_pause');
  final seek = lib.lookupFunction<CSeek, DSeek>('ghita_engine_seek');
  final render = lib.lookupFunction<CRenderFrame, DRenderFrame>('ghita_engine_render_frame_rgba');
  final startExportEx = lib.lookupFunction<CStartExportEx, DStartExportEx>('ghita_engine_start_export_ex');
  final isExporting = lib.lookupFunction<CIsExporting, DIsExporting>('ghita_engine_is_exporting');
  final getProgress = lib.lookupFunction<CGetExportProgress, DGetExportProgress>('ghita_engine_get_export_progress');
  final getFileSize = lib.lookupFunction<CGetExportFileSize, DGetExportFileSize>('ghita_engine_get_export_file_size');
  final getVersion = lib.lookupFunction<CGetVersion, DGetVersion>('ghita_engine_get_version');

  final ctx = create();
  check(ctx.address != 0, 'engine create');

  check(init(ctx) == 0, 'engine init');

  final verPtr = getVersion();
  if (verPtr != nullptr) {
    stdout.writeln('  version: ${verPtr.toDartString()}');
    check(verPtr.toDartString().contains('1.1.'), 'version string is 1.1.x');
  }

  // ---- Phase 1: import ----
  final media = File(mediaPath);
  if (!media.existsSync()) {
    stdout.writeln('  [SKIP] media file missing — import phase skipped');
  } else {
    final mp = mediaPath.toNativeUtf8();
    final ok = loadMedia(ctx, mp) == 0;
    calloc.free(mp);
    check(ok, 'import media ($mediaPath)');
    final dur = getDuration(ctx);
    stdout.writeln('  media durationMs = $dur');
    check(dur > 0, 'media duration > 0');
  }

  // ---- Phase 2: ~sessionMinutes of continuous playback with seeks ----
  final durationMs = getDuration(ctx);
  final start = DateTime.now();
  final sessionEnd = start.add(Duration(minutes: sessionMinutes));
  final frameBuf = calloc<Uint8>(640 * 360 * 4);
  var frameCount = 0;
  var lastLog = start;
  var lastSeek = start;
  var renderedBytes = 0;
  var framesNonBlack = 0;

  // v1.1.0 (PLAN_REVIEW fix #4 regression): start playback from position 0
  // without any seek — the playhead must advance on its own (the old cache-
  // hit path kept serving the cached 0ms frame and never advanced).
  seek(ctx, 0);
  play(ctx);
  await playFromZeroCheck(ctx, getPosition, render, pause, 600);
  while (DateTime.now().isBefore(sessionEnd)) {
    // Seek to a pseudo-random position every 3s (scrubbing behavior).
    if (DateTime.now().difference(lastSeek).inSeconds >= 3) {
      final target =
          (math.Random().nextDouble() * math.max(durationMs - 1, 1)).toInt();
      seek(ctx, target);
      lastSeek = DateTime.now();
    }
    // Render a frame every ~250ms to prove live decoding.
    if (DateTime.now().difference(lastLog).inMilliseconds >= 250) {
      if (render(ctx, frameBuf, 640, 360)) {
        final list = frameBuf.asTypedList(640 * 360 * 4);
        renderedBytes += list.length;
        frameCount++;
        var colored = 0;
        for (var i = 0; i < list.length && colored <= 20; i += 4) {
          final lum = (list[i] > list[i + 1] ? list[i] : list[i + 1]) > list[i + 2]
              ? (list[i] > list[i + 1] ? list[i] : list[i + 1])
              : list[i + 2];
          if (lum > 24) colored++;
        }
        if (colored > 0) framesNonBlack++;
      }
      lastLog = DateTime.now();
    }
    // Log playhead every 30s.
    if (DateTime.now().difference(lastLog).inSeconds >= 30) {
      final elapsed = DateTime.now().difference(start).inSeconds;
      stdout.writeln(
          '  t=${elapsed}s pos=${getPosition(ctx)}ms frames=$frameCount');
    }
    sleep(const Duration(milliseconds: 50));
  }
  pause(ctx);
  calloc.free(frameBuf);

  final elapsedSec = DateTime.now().difference(start).inSeconds;
  stdout.writeln('  session done: ${elapsedSec}s, frames rendered=$frameCount, '
      'non-black=$framesNonBlack, bytes=$renderedBytes');
  check(frameCount > 0, 'frames rendered during session');
  check(framesNonBlack > 0, 'live non-black frames (real decode, not held)');

  // ---- Phase 3: export MP4 ----
  final outPath = 'build/smoke_track1_export.mp4';
  final op = outPath.toNativeUtf8();
  final codec = 'h264'.toNativeUtf8();
  final startOk = startExportEx(ctx, op, 640, 360, 30, codec, 2000000, true) == 0;
  calloc.free(op);
  calloc.free(codec);
  check(startOk, 'start export MP4 (640x360@30 h264 2Mbps + audio)');

  if (startOk) {
    final exportStart = DateTime.now();
    while (isExporting(ctx) &&
        DateTime.now().difference(exportStart).inMinutes < 5) {
      sleep(const Duration(milliseconds: 150));
    }
    final progress = getProgress(ctx);
    final fileSize = getFileSize(ctx);
    stdout.writeln('  export progress=$progress fileSize=$fileSize');
    check(progress >= 1.0, 'export progress reached 1.0');
    check(fileSize > 0, 'export produced a non-empty file');
    if (fileSize > 0) {
      final f = File(outPath);
      check(f.existsSync() && f.lengthSync() == fileSize, 'output file on disk matches size');
      // ffprobe verification when available.
      final ffprobe = Process.runSync('ffprobe', [
        '-v', 'error', '-show_entries', 'format=duration,size',
        '-show_entries', 'stream=codec_type,codec_name',
        '-of', 'json', outPath,
      ]);
      if (ffprobe.exitCode == 0) {
        stdout.writeln('  ffprobe: ${(ffprobe.stdout as String).trim()}');
        final json = (ffprobe.stdout as String);
        check(json.contains('"codec_type": "video"') &&
            json.contains('"codec_type": "audio"'), 'ffprobe: video + audio streams');
        check(json.contains('"codec_name": "h264"'), 'ffprobe: h264 video codec');
      } else {
        stdout.writeln('  [WARN] ffprobe unavailable — skipping stream verify');
      }
    }
  }

  destroy(ctx);
  stdout.writeln(_failures == 0
      ? '=== SMOKE PASS ==='
      : '=== SMOKE FAIL ($_failures) ===');
  exit(_failures == 0 ? 0 : 1);
}
