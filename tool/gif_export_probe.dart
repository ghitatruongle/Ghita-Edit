// v1.5.5-beta1: GIF export robustness probe — the matrix case is tiny
// (160x120, 12 frames); this runs a realistic 640x480 / 20-frame GIF and
// reports what ffprobe sees. Prints timing so palette pre-scan + dithering
// cost is visible at a real size.
// ignore_for_file: avoid_print

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef CCreate = Pointer<Void> Function();
typedef DCreate = Pointer<Void> Function();
typedef CInt = Int32 Function(Pointer<Void>);
typedef DInt = int Function(Pointer<Void>);
typedef CLoad = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef DLoad = int Function(Pointer<Void>, Pointer<Utf8>);
typedef CExport = Int32 Function(
    Pointer<Void>, Pointer<Utf8>, Int32, Int32, Int32, Pointer<Utf8>, Int64, Bool);
typedef DExport = int Function(Pointer<Void>, Pointer<Utf8>, int, int, int, Pointer<Utf8>, int, bool);
typedef CBool = Bool Function(Pointer<Void>);
typedef DBool = bool Function(Pointer<Void>);

void main(List<String> args) {
  final dll = args.isNotEmpty
      ? args[0]
      : 'E:/Ghita Edit/build/windows/x64/runner/Release/ghita_engine.dll';
  final lib = DynamicLibrary.open(dll);
  final create = lib.lookupFunction<CCreate, DCreate>('ghita_engine_create');
  final init = lib.lookupFunction<CInt, DInt>('ghita_engine_init');
  final destroy = lib.lookupFunction<CInt, DInt>('ghita_engine_destroy');
  final load = lib.lookupFunction<CLoad, DLoad>('ghita_engine_load_media');
  final export = lib.lookupFunction<CExport, DExport>('ghita_engine_start_export_ex');
  final isExporting = lib.lookupFunction<CBool, DBool>('ghita_engine_is_exporting');

  const w = 640, h = 480, fps = 20;
  final out = '${Directory.systemTemp.path}/probe_big.gif';
  final outPtr = out.toNativeUtf8();
  final codec = 'gif'.toNativeUtf8();
  final src = File('test_video.mp4').absolute.path.toNativeUtf8();

  final ctx = create();
  init(ctx);
  load(ctx, src);
  final sw = Stopwatch()..start();
  final rc = export(ctx, outPtr, w, h, fps, codec, 0, false);
  final started = rc == 0;
  var waited = 0;
  while (started && isExporting(ctx) && waited < 3000) {
    sleep(const Duration(milliseconds: 10));
    waited++;
  }
  sw.stop();
  destroy(ctx);
  calloc.free(outPtr);
  calloc.free(codec);
  calloc.free(src);

  final f = File(out);
  print('export started=$started finished=${!isExporting(ctx)} '
      'elapsed=${sw.elapsedMilliseconds}ms '
      'size=${f.existsSync() ? f.lengthSync() : 0} bytes -> $out');
  exit(started && f.existsSync() && f.lengthSync() > 0 ? 0 : 1);
}
