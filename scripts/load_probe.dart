// Self-containment probe for the staged Windows bundle: opens the engine DLL
// the way the app does, creates + initializes a context, reports hasFFmpeg.
//
// CI / local usage (mimics a clean machine by stripping msys64 from PATH):
//   cd build/windows/x64/runner/Release
//   env PATH="/c/Windows/System32:/c/Windows" \
//     "$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart.exe" \
//     <repo>/scripts/load_probe.dart ghita_engine.dll
// Exits 1 unless the DLL loads, initializes and reports FFmpeg.
//
// dart:ffi only — no package imports, so it runs from any working directory.
import 'dart:ffi';
import 'dart:io';

void main(List<String> args) {
  if (args.isEmpty) {
    stdout.writeln('usage: load_probe.dart <path-or-name-of-ghita_engine.dll>');
    exit(2);
  }
  final DynamicLibrary lib;
  try {
    lib = DynamicLibrary.open(args[0]);
  } catch (e) {
    stdout.writeln('LOAD FAILED: $e');
    exit(1);
  }
  final create = lib.lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>('ghita_engine_create');
  final init = lib.lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>('ghita_engine_init');
  final hasFFmpeg = lib.lookupFunction<Bool Function(Pointer<Void>), bool Function(Pointer<Void>)>('ghita_engine_has_ffmpeg');
  final destroy = lib.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('ghita_engine_destroy');
  final ctx = create();
  if (ctx == nullptr) {
    stdout.writeln('LOAD OK but ghita_engine_create returned null');
    exit(1);
  }
  final rc = init(ctx);
  final ff = hasFFmpeg(ctx);
  destroy(ctx);
  stdout.writeln('LOAD OK init=$rc hasFFmpeg=$ff');
  if (rc != 0 || !ff) {
    exit(1);
  }
}
