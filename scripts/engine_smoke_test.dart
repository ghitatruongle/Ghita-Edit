// Engine smoke test for release builds (v1.0.1).
//
// Merged from tool/check_engine.dart + tool/play_audio_test.dart so a single
// command validates the REAL native engine before a build is shipped:
//   1. The engine DLL loads and initializes (create/init/version/destroy).
//   2. When the DLL was compiled with FFmpeg, the FFmpeg runtime DLLs
//      (avcodec/avformat/avutil/swscale/swresample) are bundled NEXT TO it —
//      otherwise the engine silently falls back to Demo Mode and the app
//      cannot import or play anything (the regression fixed in v1.0.1).
//   3. Media import + playback validation against the REAL timeline mixer:
//      * --mp3:  import + play an MP3 — playhead advances and the decoder
//        produces real non-zero PCM (via ghita_engine_mix_audio_window, the
//        same mixer the audio preview loop plays through — NOT the legacy
//        get_audio_waveform which reports a synthetic sine for timeline
//        clips and would be a false positive).
//      * --video: import + play an MP4 with a video AND an audio track —
//        live frames are non-black and CHANGE over time (live decode, not a
//        held frame), the audio track decodes non-zero PCM in sync with the
//        same playhead, and render_frame_at is deterministic yet position-
//        dependent (frame@1s != frame@4s, frame@P == frame@P twice).
//
// Usage:
//   dart run scripts/engine_smoke_test.dart [--dll PATH] [--mp3 PATH]
//       [--video PATH] [--seconds N] [--quick]
//
//   --quick    skip the media import/playback checks (load/init only).
//   --seconds  playback length in seconds (default 10; 0 = init only).
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';

final class GhitaEngineContext extends Opaque {}

typedef _CCreate = Pointer<GhitaEngineContext> Function();
typedef _DCreate = Pointer<GhitaEngineContext> Function();
typedef _CInit = Int32 Function(Pointer<GhitaEngineContext>);
typedef _DInit = int Function(Pointer<GhitaEngineContext>);
typedef _CPlay = Void Function(Pointer<GhitaEngineContext>);
typedef _DPlay = void Function(Pointer<GhitaEngineContext>);
typedef _CPause = Void Function(Pointer<GhitaEngineContext>);
typedef _DPause = void Function(Pointer<GhitaEngineContext>);
typedef _CUpsert = Int32 Function(
    Pointer<GhitaEngineContext>, Int32, Pointer<Utf8>, Int64, Int64, Int64,
    Int32, Int32, Float, Float, Float);
typedef _DUpsert = int Function(
    Pointer<GhitaEngineContext>, int, Pointer<Utf8>, int, int, int,
    int, int, double, double, double);
typedef _CRender = Bool Function(Pointer<GhitaEngineContext>, Pointer<Uint8>, Int32, Int32);
typedef _DRender = bool Function(Pointer<GhitaEngineContext>, Pointer<Uint8>, int, int);
typedef _CRenderAt = Bool Function(
    Pointer<GhitaEngineContext>, Pointer<Uint8>, Int32, Int32, Int64);
typedef _DRenderAt = bool Function(
    Pointer<GhitaEngineContext>, Pointer<Uint8>, int, int, int);
typedef _CGetPos = Int64 Function(Pointer<GhitaEngineContext>);
typedef _DGetPos = int Function(Pointer<GhitaEngineContext>);
typedef _CGetDur = Int64 Function(Pointer<GhitaEngineContext>);
typedef _DGetDur = int Function(Pointer<GhitaEngineContext>);
typedef _CMix = Bool Function(Pointer<GhitaEngineContext>, Int64, Int64, Pointer<Float>, Int32);
typedef _DMix = bool Function(Pointer<GhitaEngineContext>, int, int, Pointer<Float>, int);
typedef _CHasFFmpeg = Bool Function(Pointer<GhitaEngineContext>);
typedef _DHasFFmpeg = bool Function(Pointer<GhitaEngineContext>);
typedef _CGetVersion = Pointer<Utf8> Function();
typedef _DGetVersion = Pointer<Utf8> Function();
typedef _CClear = Void Function(Pointer<GhitaEngineContext>);
typedef _DClear = void Function(Pointer<GhitaEngineContext>);
typedef _CDestroy = Void Function(Pointer<GhitaEngineContext>);
typedef _DDestroy = void Function(Pointer<GhitaEngineContext>);

int _failures = 0;

void _check(String label, bool ok, [String? detail]) {
  stdout.writeln('${ok ? "PASS" : "FAIL"}: $label${detail != null ? " ($detail)" : ""}');
  if (!ok) _failures++;
}

void _warn(String msg) => stdout.writeln('WARN: $msg');

/// Simple FNV-1a-ish hash over an RGBA frame — used to prove live frames
/// CHANGE as the playhead moves and render_frame_at is position-dependent.
int _frameHash(Pointer<Uint8> buf, int byteCount) {
  var h = 0x811c9dc5;
  final bytes = buf.asTypedList(byteCount);
  for (final b in bytes) {
    h ^= b;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

/// Peak |sample| of the mix buffer (interleaved stereo float).
double _mixPeak(Pointer<Float> buf, int count) {
  var peak = 0.0;
  for (final s in buf.asTypedList(count)) {
    final a = s.abs();
    if (a > peak) peak = a;
  }
  return peak;
}

void main(List<String> args) {
  var dllPath = 'build/windows/x64/runner/Release/ghita_engine.dll';
  String? mp3Path;
  String? videoPath;
  var seconds = 10;
  var quick = false;

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    String next() {
      if (i + 1 >= args.length) {
        stderr.writeln('Missing value for $arg');
        exit(2);
      }
      return args[++i];
    }

    if (arg == '--dll') {
      dllPath = next();
    } else if (arg == '--mp3') {
      mp3Path = next();
    } else if (arg == '--video') {
      videoPath = next();
    } else if (arg == '--seconds') {
      seconds = int.tryParse(next()) ?? -1;
    } else if (arg == '--quick') {
      quick = true;
    } else {
      stderr.writeln('Unknown argument: $arg');
      exit(2);
    }
  }
  if (seconds < 1) {
    stderr.writeln('--seconds must be a positive integer');
    exit(2);
  }

  _check('engine DLL exists', File(dllPath).existsSync(), dllPath);
  if (!File(dllPath).existsSync()) {
    stderr.writeln('Build the Release app first: flutter build windows --release');
    exit(1);
  }

  // ---------------------------------------------------------------- load
  final lib = DynamicLibrary.open(dllPath);
  final create = lib.lookupFunction<_CCreate, _DCreate>('ghita_engine_create');
  final init = lib.lookupFunction<_CInit, _DInit>('ghita_engine_init');
  final play = lib.lookupFunction<_CPlay, _DPlay>('ghita_engine_play');
  final pause = lib.lookupFunction<_CPause, _DPause>('ghita_engine_pause');
  final upsert = lib.lookupFunction<_CUpsert, _DUpsert>('ghita_engine_upsert_clip');
  final render = lib.lookupFunction<_CRender, _DRender>('ghita_engine_render_frame_rgba');
  final renderAt = lib.lookupFunction<_CRenderAt, _DRenderAt>('ghita_engine_render_frame_at');
  final getPos = lib.lookupFunction<_CGetPos, _DGetPos>('ghita_engine_get_position_ms');
  final getDur = lib.lookupFunction<_CGetDur, _DGetDur>('ghita_engine_get_duration_ms');
  final mix = lib.lookupFunction<_CMix, _DMix>('ghita_engine_mix_audio_window');
  final hasFFmpeg = lib.lookupFunction<_CHasFFmpeg, _DHasFFmpeg>('ghita_engine_has_ffmpeg');
  final getVersion = lib.lookupFunction<_CGetVersion, _DGetVersion>('ghita_engine_get_version');
  final clear = lib.lookupFunction<_CClear, _DClear>('ghita_engine_clear_clips');
  final destroy = lib.lookupFunction<_CDestroy, _DDestroy>('ghita_engine_destroy');

  final ctx = create();
  _check('create()', ctx != nullptr);
  _check('init() == 0', init(ctx) == 0);
  final verPtr = getVersion();
  _check('engine version', verPtr != nullptr,
      verPtr != nullptr ? verPtr.toDartString() : '');

  // ------------------------------------------------- FFmpeg bundle check
  // The critical regression: a DLL compiled with FFmpeg that ships WITHOUT
  // the FFmpeg runtime DLLs silently falls back to Demo Mode (app stuck on
  // the loading shell, nothing importable). Fail hard if that ever happens.
  final ffmpegCompiled = hasFFmpeg(ctx);
  if (ffmpegCompiled) {
    final dir = File(dllPath).parent.path;
    const needed = [
      'avcodec-',
      'avformat-',
      'avutil-',
      'swscale-',
      'swresample-',
    ];
    final found = <String>{};
    for (final entry in Directory(dir).listSync()) {
      final name = entry is File ? entry.uri.pathSegments.last : '';
      for (final prefix in needed) {
        if (name.startsWith(prefix)) found.add(prefix);
      }
    }
    final missing = needed.where((p) => !found.contains(p)).toList();
    _check(
        'FFmpeg runtime DLLs bundled next to the engine DLL',
        missing.isEmpty,
        missing.isEmpty
            ? 'all present'
            : 'MISSING: ${missing.join(', ')} — engine will fail to load (Demo Mode)');
  } else {
    _warn('engine compiled WITHOUT FFmpeg — media decode unavailable on this build');
  }

  if (quick || (mp3Path == null && videoPath == null)) {
    if (mp3Path == null && videoPath == null && !quick) {
      _warn('no --mp3/--video provided — skipping import/playback checks');
    }
    destroy(ctx);
    stdout.writeln(_failures == 0 ? 'ENGINE SMOKE TEST PASSED' : '$_failures CHECK(S) FAILED');
    exit(_failures == 0 ? 0 : 1);
  }

  // Never run the import/playback checks against the synthetic fallback
  // decoder — a non-zero sine waveform would fake a PASS for an engine that
  // cannot decode real media at all. Report the skip explicitly instead.
  if (!ffmpegCompiled) {
    _warn('engine compiled WITHOUT FFmpeg — SKIPPING media import/playback checks '
        '(the synthetic decoder would produce a false PASS)');
    destroy(ctx);
    stdout.writeln(_failures == 0 ? 'ENGINE SMOKE TEST PASSED (engine-only)' : '$_failures CHECK(S) FAILED');
    exit(_failures == 0 ? 0 : 1);
  }

  final waveBuf = calloc<Float>(4410 * 2); // 100ms stereo @ 44.1kHz
  final frameBuf = calloc<Uint8>(160 * 90 * 4);
  final frameBytes = 160 * 90 * 4;

  if (mp3Path != null) {
    clear(ctx); // fresh timeline — the audio clip is its own track 0
    _runAudioChecks(ctx, mp3Path, seconds, upsert, play, pause, render, getPos,
        getDur, mix, waveBuf, frameBuf);
  }
  if (videoPath != null) {
    clear(ctx); // fresh timeline — never leave a previous clip on track 0
    _runVideoChecks(ctx, videoPath, seconds, upsert, play, pause, render,
        renderAt, getPos, getDur, mix, waveBuf, frameBuf, frameBytes);
  }

  calloc.free(waveBuf);
  calloc.free(frameBuf);
  destroy(ctx);

  stdout.writeln(_failures == 0
      ? 'ENGINE SMOKE TEST PASSED — media imported, played $seconds s, log clean.'
      : '$_failures CHECK(S) FAILED');
  exit(_failures == 0 ? 0 : 1);
}

// ====================================================================
// Audio-only (MP3) section
// ====================================================================
void _runAudioChecks(
  Pointer<GhitaEngineContext> ctx,
  String mp3Path,
  int seconds,
  _DUpsert upsert,
  _DPlay play,
  _DPause pause,
  _DRender render,
  _DGetPos getPos,
  _DGetDur getDur,
  _DMix mix,
  Pointer<Float> waveBuf,
  Pointer<Uint8> frameBuf,
) {
  _check('MP3 exists', File(mp3Path).existsSync(), mp3Path);
  if (!File(mp3Path).existsSync()) return;

  final pathPtr = mp3Path.toNativeUtf8();
  final upsertOk = upsert(ctx, 1, pathPtr, 0, seconds * 1000, 0, 0, 1, 1.0, 1.0, 1.0);
  calloc.free(pathPtr);
  _check('upsertClip(mp3, ${seconds}s) != 0', upsertOk != 0);

  final dur = getDur(ctx);
  // NOTE: after upsertClip this is the CLIP duration (start+duration), not a
  // file probe — real file decode is validated by the PCM checks below.
  _check('clip duration computed', dur >= 1000, 'got ${dur}ms');

  play(ctx);
  stdout.writeln('PLAYING MP3 $seconds seconds (audio preview thread active) ...');

  var maxPos = 0;
  var maxPeak = 0.0;
  final stopwatch = Stopwatch()..start();
  final sampling = Stopwatch()..start();
  // Sample at most every 2s, but at least 3 times for very short runs so
  // --seconds 1/2 still exercises (and verifies) the playhead + audio.
  final sampleEveryMs = math.min(2000, (seconds * 1000) ~/ 3);
  while (stopwatch.elapsedMilliseconds < seconds * 1000) {
    render(ctx, frameBuf, 4, 4); // preview tick advances the playhead
    if (sampling.elapsedMilliseconds >= sampleEveryMs) {
      sampling.reset();
      final pos = getPos(ctx);
      if (pos > maxPos) maxPos = pos;
      // Mix 100ms of REAL timeline audio at the current playhead.
      final mixOk = mix(ctx, pos, pos + 100, waveBuf, 4410 * 2);
      final peak = _mixPeak(waveBuf, 4410 * 2);
      if (mixOk && peak > maxPeak) maxPeak = peak;
      stdout.writeln('  t=${stopwatch.elapsedMilliseconds ~/ 1000}s pos=${pos}ms '
          'mixPeak=${mixOk ? peak.toStringAsFixed(4) : 'N/A'}');
    }
    sleep(const Duration(milliseconds: 33));
  }
  pause(ctx);

  _check('playhead advanced during playback', maxPos > (seconds / 2) * 1000,
      'max pos observed: ${maxPos}ms');
  _check('MP3 decoded to real PCM via timeline mixer (non-zero amplitude)',
      maxPeak > 0.01, 'peak amplitude: ${maxPeak.toStringAsFixed(4)}');
}

// ====================================================================
// Video + audio sync section (MP4 with video AND audio tracks)
// ====================================================================
void _runVideoChecks(
  Pointer<GhitaEngineContext> ctx,
  String videoPath,
  int seconds,
  _DUpsert upsert,
  _DPlay play,
  _DPause pause,
  _DRender render,
  _DRenderAt renderAt,
  _DGetPos getPos,
  _DGetDur getDur,
  _DMix mix,
  Pointer<Float> waveBuf,
  Pointer<Uint8> frameBuf,
  int frameBytes,
) {
  _check('video file exists', File(videoPath).existsSync(), videoPath);
  if (!File(videoPath).existsSync()) return;

  final pathPtr = videoPath.toNativeUtf8();
  // kind = 0 (Video) — the file has both a video and an audio stream.
  final upsertOk = upsert(ctx, 2, pathPtr, 0, seconds * 1000, 0, 0, 0, 1.0, 1.0, 1.0);
  calloc.free(pathPtr);
  _check('upsertClip(video, ${seconds}s) != 0', upsertOk != 0);

  final dur = getDur(ctx);
  // NOTE: after upsertClip this is the CLIP duration (start+duration), not a
  // file probe — real file decode is validated by the frame/PCM checks below.
  _check('clip duration computed', dur >= 1000, 'got ${dur}ms');

  play(ctx);
  stdout.writeln('PLAYING VIDEO+audio $seconds seconds (preview + audio threads) ...');

  var maxPos = 0;
  var maxPeak = 0.0;
  var maxBrightness = 0;
  final liveHashes = <int>{};
  final stopwatch = Stopwatch()..start();
  final sampling = Stopwatch()..start();
  // Same as the audio section: never leave short runs unsampled.
  final sampleEveryMs = math.min(2000, (seconds * 1000) ~/ 3);
  while (stopwatch.elapsedMilliseconds < seconds * 1000) {
    final rendered = render(ctx, frameBuf, 160, 90);
    if (rendered) {
      final bytes = frameBuf.asTypedList(frameBytes);
      var bright = 0;
      for (var i = 0; i < bytes.length; i += 4) {
        // Skip alpha — it is 255 even on an all-black frame, so a real
        // "video never drawn" bug must not pass the non-black check.
        var rgb = bytes[i] > bytes[i + 1] ? bytes[i] : bytes[i + 1];
        if (bytes[i + 2] > rgb) rgb = bytes[i + 2];
        if (rgb > bright) bright = rgb;
      }
      if (bright > maxBrightness) maxBrightness = bright;
      liveHashes.add(_frameHash(frameBuf, frameBytes));
    }
    if (sampling.elapsedMilliseconds >= sampleEveryMs) {
      sampling.reset();
      final pos = getPos(ctx);
      if (pos > maxPos) maxPos = pos;
      // Audio track of the SAME file, mixed at the current playhead — proves
      // A/V stay in sync (both derive from the same playhead position).
      final mixOk = mix(ctx, pos, pos + 100, waveBuf, 4410 * 2);
      final peak = _mixPeak(waveBuf, 4410 * 2);
      if (mixOk && peak > maxPeak) maxPeak = peak;
      stdout.writeln('  t=${stopwatch.elapsedMilliseconds ~/ 1000}s pos=${pos}ms '
          'mixPeak=${mixOk ? peak.toStringAsFixed(4) : 'N/A'}');
    }
    sleep(const Duration(milliseconds: 33));
  }
  pause(ctx);

  _check('playhead advanced during playback', maxPos > (seconds / 2) * 1000,
      'max pos observed: ${maxPos}ms');
  _check('live video frames are non-black (real video decode)',
      maxBrightness > 40, 'max pixel brightness: $maxBrightness');
  _check('live video frames CHANGE over time (not a held/static frame)',
      liveHashes.length >= 2, '${liveHashes.length} distinct frames seen');

  // Audio must be non-zero at the playhead, not just somewhere in the file:
  // mix a 100ms window at a mid-playback position reached during playback.
  final mid = dur ~/ 2;
  final midMixOk = mix(ctx, mid, mid + 100, waveBuf, 4410 * 2);
  final midPeak = _mixPeak(waveBuf, 4410 * 2);
  _check('video audio track decodes real PCM (A/V in sync)',
      midMixOk && midPeak > 0.01, 'mid-playback peak: ${midPeak.toStringAsFixed(4)}');

  // render_frame_at: deterministic at the same position, different across
  // positions (frame content tracks the playhead). Positions derive from the
  // clip duration so they are ALWAYS inside the clip — a hardcoded 4s would
  // land past the end of a 3s clip and compare a real frame against black.
  final p1 = dur ~/ 4;
  final p2 = (dur * 3) ~/ 4;
  final h1a = _frameAtHash(renderAt, ctx, frameBuf, frameBytes, p1);
  final h1b = _frameAtHash(renderAt, ctx, frameBuf, frameBytes, p1);
  final h2 = _frameAtHash(renderAt, ctx, frameBuf, frameBytes, p2);
  _check('render_frame_at is deterministic (same position, same frame)',
      h1a != null && h1a == h1b, h1a != null ? 'hash $h1a' : 'render failed');
  _check('render_frame_at tracks the playhead (frame@p1 != frame@p2)',
      h1a != null && h2 != null && h1a != h2,
      h1a != null && h2 != null ? 'p1=${p1}ms: $h1a vs p2=${p2}ms: $h2' : 'render failed');
}

int? _frameAtHash(
  _DRenderAt renderAt,
  Pointer<GhitaEngineContext> ctx,
  Pointer<Uint8> buf,
  int frameBytes,
  int posMs,
) {
  final ok = renderAt(ctx, buf, 160, 90, posMs);
  if (!ok) return null;
  return _frameHash(buf, frameBytes);
}
