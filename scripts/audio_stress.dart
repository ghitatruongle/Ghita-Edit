// T6 debug: reproduce audio-import freeze/RAM — time the exact calls the UI
// makes after importing an audio clip (timeline waveform 300 buckets,
// spectrogram 200x64, rms 100) on a long MP3.
//
// Usage:
//   dart run scripts/audio_stress.dart --media song180.mp3 [--dll PATH] [--iters 10]
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'engine_ffi_shared.dart';

void main(List<String> args) {
  var media = 'song180.mp3';
  String? dll;
  var iters = 10;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--media':
        media = args[++i];
      case '--dll':
        dll = args[++i];
      case '--iters':
        iters = int.parse(args[++i]);
    }
  }

  final lib = loadEngineLibrary(dllPath: dll);
  if (lib == null) {
    stderr.writeln('ERROR: engine dll not found');
    exit(1);
  }
  final create = lib.lookupFunction<CCreate, DCreate>('ghita_engine_create');
  final init = lib.lookupFunction<CInit, DInit>('ghita_engine_init');
  final destroy = lib.lookupFunction<CDestroy, DDestroy>('ghita_engine_destroy');
  final upsert = lib.lookupFunction<CUpsertClip, DUpsertClip>('ghita_engine_upsert_clip');
  final wave = lib.lookupFunction<CGetTimelineWaveform, DGetTimelineWaveform>('ghita_engine_get_timeline_waveform');
  final spec = lib.lookupFunction<CSpectrogram, DSpectrogram>('ghita_engine_get_spectrogram');
  final rms = lib.lookupFunction<CTimelineRms, DTimelineRms>('ghita_engine_get_timeline_rms');

  final ctx = create();
  if (ctx == nullptr) {
    stderr.writeln('ERROR: create failed');
    exit(1);
  }
  init(ctx);

  final pathPtr = media.toNativeUtf8();
  final ret = upsert(ctx, 1, pathPtr, 0, 180000, 0, 2, 1, 1.0, 1.0, 1.0);
  calloc.free(pathPtr);
  stdout.writeln('upsert ret = $ret');

  final wBuf = calloc<Float>(300);
  final sBuf = calloc<Float>(200 * 64);
  final rBuf = calloc<Float>(100);

  final sw = Stopwatch();
  for (var i = 1; i <= iters; i++) {
    sw..reset()..start();
    final okW = wave(ctx, wBuf, 300, 2);
    final tWave = sw.elapsedMilliseconds;

    sw..reset()..start();
    final okS = spec(ctx, sBuf, 200, 64, 2);
    final tSpec = sw.elapsedMilliseconds;

    sw..reset()..start();
    final okR = rms(ctx, rBuf, 100, 2);
    final tRms = sw.elapsedMilliseconds;

    stdout.writeln(
        'iter $i: waveform($okW)=${tWave}ms spectrogram($okS)=${tSpec}ms rms($okR)=${tRms}ms');
  }

  calloc.free(wBuf);
  calloc.free(sBuf);
  calloc.free(rBuf);
  destroy(ctx);
  stdout.writeln('DONE');
}
