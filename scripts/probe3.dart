// probe3.dart — diagnose the 5 reported issues against the REAL DLL:
//   #1 audio windows must be FULLY filled (no half-silent chunks)
//   #2 image (PNG) decode -> non-black frame
//   #3 play() + tick loop -> position advances WITHOUT seeking first
//   #4 setPlaybackRate(2.0) actually changes advancement speed
// Usage: dart run scripts/probe3.dart --wav FILE.wav --mp3 FILE.mp3 --img FILE.png
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

final class Ctx extends Opaque {}

typedef CCreate = Pointer<Ctx> Function();
typedef DCreate = Pointer<Ctx> Function();

typedef CInit = Int32 Function(Pointer<Ctx>);
typedef DInit = int Function(Pointer<Ctx>);

typedef CUpsert = Int32 Function(Pointer<Ctx>, Int32, Pointer<Utf8>, Int64, Int64,
    Int64, Int32, Int32, Float, Float, Float);
typedef DUpsert = int Function(Pointer<Ctx>, int, Pointer<Utf8>, int, int, int, int,
    int, double, double, double);

typedef CMix = Bool Function(Pointer<Ctx>, Int64, Int64, Pointer<Float>, Int32);
typedef DMix = bool Function(Pointer<Ctx>, int, int, Pointer<Float>, int);

typedef CRender = Bool Function(Pointer<Ctx>, Pointer<Uint8>, Int32, Int32);
typedef DRender = bool Function(Pointer<Ctx>, Pointer<Uint8>, int, int);

typedef CVoid = Void Function(Pointer<Ctx>);
typedef DVoid = void Function(Pointer<Ctx>);

typedef CRenderAt = Bool Function(Pointer<Ctx>, Pointer<Uint8>, Int32, Int32, Int64);
typedef DRenderAt = bool Function(Pointer<Ctx>, Pointer<Uint8>, int, int, int);

typedef CSeek = Void Function(Pointer<Ctx>, Int64);
typedef DSeek = void Function(Pointer<Ctx>, int);

typedef CRate = Void Function(Pointer<Ctx>, Float);
typedef DRate = void Function(Pointer<Ctx>, double);

typedef CInt64 = Int64 Function(Pointer<Ctx>);
typedef DInt64 = int Function(Pointer<Ctx>);

typedef CIsPlaying = Bool Function(Pointer<Ctx>);
typedef DIsPlaying = bool Function(Pointer<Ctx>);

typedef CHasFFmpeg = Bool Function(Pointer<Ctx>);
typedef DHasFFmpeg = bool Function(Pointer<Ctx>);

int fails = 0;

void check(String label, bool ok, [String? detail]) {
  stdout.writeln('${ok ? 'PASS' : 'FAIL'}: $label${detail != null ? ' ($detail)' : ''}');
  if (!ok) fails++;
}

void main(List<String> args) {
  var dll = 'build/windows/x64/runner/Release/ghita_engine.dll';
  String? wavPath;
  String? mp3Path;
  String? imgPath;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--dll') dll = args[++i];
    if (args[i] == '--wav') wavPath = args[++i];
    if (args[i] == '--mp3') mp3Path = args[++i];
    if (args[i] == '--img') imgPath = args[++i];
  }

  final lib = DynamicLibrary.open(dll);
  final create = lib.lookupFunction<CCreate, DCreate>('ghita_engine_create');
  final init = lib.lookupFunction<CInit, DInit>('ghita_engine_init');
  final upsert = lib.lookupFunction<CUpsert, DUpsert>('ghita_engine_upsert_clip');
  final play = lib.lookupFunction<CVoid, DVoid>('ghita_engine_play');
  final pause = lib.lookupFunction<CVoid, DVoid>('ghita_engine_pause');
  final getPos = lib.lookupFunction<CInt64, DInt64>('ghita_engine_get_position_ms');
  final mix = lib.lookupFunction<CMix, DMix>('ghita_engine_mix_audio_window');
  final renderFrameRgba = lib.lookupFunction<CRender, DRender>('ghita_engine_render_frame_rgba');
  final renderAt = lib.lookupFunction<CRenderAt, DRenderAt>('ghita_engine_render_frame_at');
  final seek = lib.lookupFunction<CSeek, DSeek>('ghita_engine_seek');
  final setRate = lib.lookupFunction<CRate, DRate>('ghita_engine_set_playback_rate');
  final isPlaying = lib.lookupFunction<CIsPlaying, DIsPlaying>('ghita_engine_is_playing');
  final hasFFmpeg = lib.lookupFunction<CHasFFmpeg, DHasFFmpeg>('ghita_engine_has_ffmpeg');

  final ctx = create();
  check('engine create', ctx != nullptr);
  check('engine init', init(ctx) == 0);
  check('has FFmpeg', hasFFmpeg(ctx));

  // ------------ #1 audio fullness for a 100ms window ------------
  if (wavPath != null) {
    final pathPtr = wavPath.toNativeUtf8();
    upsert(ctx, 1, pathPtr, 0, 3000, 0, 0, 1, 1.0, 1.0, 1.0); // kind 1 = audio
    calloc.free(pathPtr);
    final buf = calloc<Float>(4410 * 2);
    final ok = mix(ctx, 0, 100, buf, 4410 * 2);
    final s = buf.asTypedList(4410 * 2);
    var nz = 0;
    for (final v in s) {
      if (v.abs() > 1e-4) nz++;
    }
    check('WAV: window 0-100ms FULLY decoded (non-zero float coverage)',
        ok && nz > 4410 * 2 * 0.95, 'non-zero $nz / 8820');
    calloc.free(buf);
  }

  // ------------ #2 image decode -> non-black ------------
  if (imgPath != null) {
    final pathPtr = imgPath.toNativeUtf8();
    // trackIndex 1 — renders ABOVE the WAV (kind 1) clip on track 0 that is
    // also covering [0,3000); the compositor picks the first visual clip per
    // track and would otherwise skip the image entirely.
    upsert(ctx, 2, pathPtr, 0, 3000, 0, 1, 2, 1.0, 1.0, 1.0); // kind 2 = image
    calloc.free(pathPtr);
    final frame = calloc<Uint8>(160 * 90 * 4);
    final rendered = renderAt(ctx, frame, 160, 90, 500);
    if (rendered) {
      final bytes = frame.asTypedList(160 * 90 * 4);
      var bright = 0;
      for (var i = 0; i < bytes.length; i += 4) {
        var m = bytes[i] > bytes[i + 1] ? bytes[i] : bytes[i + 1];
        if (bytes[i + 2] > m) m = bytes[i + 2];
        if (m > bright) bright = m;
      }
      check('IMAGE decode -> non-black frame', bright > 40, 'max brightness $bright');
    } else {
      check('IMAGE decode -> non-black frame', false, 'renderFrameAt returned false');
    }
    calloc.free(frame);
  }

  // ------------ #3 / #4 play advance + playback rate ------------
  if (mp3Path != null && File(mp3Path).existsSync()) {
    final pathPtr = mp3Path.toNativeUtf8();
    upsert(ctx, 3, pathPtr, 0, 4000, 0, 0, 1, 1.0, 1.0, 1.0); // kind 1 = audio
    calloc.free(pathPtr);
  }

  // Simulate the app: a Dart tick loop calls renderFrameRGBA every ~33ms,
  // which is what advances the engine position during playback.
  final tickFrame = calloc<Uint8>(160 * 90 * 4);
  void renderTickLoop(int ms) {
    final sw = Stopwatch()..start();
    while (sw.elapsedMilliseconds < ms) {
      // The app's engine tick calls render_frame_rgba every ~33ms — THIS is
      // what advances the engine position during playback (render_frame_at
      // intentionally does NOT touch playback state).
      renderFrameRgba(ctx, tickFrame, 160, 90);
      sleep(const Duration(milliseconds: 5));
    }
  }

  // #4: rate 2.0 -> 1s real time should advance ~2s
  seek(ctx, 0);
  setRate(ctx, 2.0);
  play(ctx);
  renderTickLoop(1100);
  pause(ctx);
  final pos2x = getPos(ctx);
  check('PLAYBACK: position advanced while playing at 2x (no seek)',
      pos2x > 1500, 'pos after 1.1s real @2x = ${pos2x}ms (expect ~2000)');

  // #5: play at 1.0 from a fresh seek must advance without any seek interaction
  seek(ctx, 0);
  setRate(ctx, 1.0);
  play(ctx);
  renderTickLoop(700);
  final pos1x = getPos(ctx);
  check('PLAYBACK: play() from position 0 advances (no prior seek)',
      pos1x > 200, 'pos after 0.7s @1x = ${pos1x}ms');
  pause(ctx);
  check('PLAYBACK: paused', !isPlaying(ctx));
  calloc.free(tickFrame);

  stdout.writeln(fails == 0 ? 'PROBE3: ALL PASSED' : 'PROBE3: $fails FAILED');
  exit(fails == 0 ? 0 : 1);
}