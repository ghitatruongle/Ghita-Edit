import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghita_edit/src/controllers/editor_controller.dart';

// v1.0.2: REAL-engine end-to-end verification (runs only when the engine DLL
// plus a test video are available — fails loudly otherwise, never a silent
// Demo-Mode pass). Proves: engine initializes, video imports, the playhead
// actually ADVANCES during playback and real RGBA frames are produced.
void main() {
  testWidgets('real engine: import → play → playhead advances → frame bytes',
      (tester) async {
    final video = File(
        '${Directory.current.path}${Platform.pathSeparator}test_video.mp4');
    if (!video.existsSync()) {
      // Not a failure: the sample media just isn't checked in (CI).
      markTestSkipped('test_video.mp4 not present — skipping real-engine test');
      return;
    }

    final controller = EditorController();
    addTearDown(controller.dispose);

    // runAsync: the engine tick loop is a real Timer.periodic and the FFmpeg
    // decode runs against the real wall clock — inside a plain testWidgets
    // body the fake async zone never fires those timers and the playhead can
    // never advance (which itself would be a false failure).
    await tester.runAsync(() async {
      debugPrint('STEP1: init()...');
      await controller.init();
      debugPrint('STEP2: init done, isEngineReady=${controller.isEngineReady} '
          'status="${controller.statusMessage}"');

      debugPrint('STEP3: importMedia...');
      await controller.importMedia(video.path);
      debugPrint('STEP4: imported, clips=${controller.project.allClips.length}');

      debugPrint('STEP5: play...');
      controller.play();
      final start = DateTime.now();
      var lastReport = 0;
      while (controller.positionMs < 500 &&
          DateTime.now().difference(start).inMilliseconds < 12000) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final secs = DateTime.now().difference(start).inMilliseconds ~/ 1000;
        if (secs != lastReport) {
          lastReport = secs;
          debugPrint('  t=${secs}s enginePlaying=${controller.engineService.isPlaying} '
              'enginePos=${controller.engineService.positionMs} '
              'frameBytes=${controller.frameBytes?.length}');
        }
      }
      controller.pause();
      debugPrint('STEP6: played, positionMs=${controller.positionMs}');
    });

    expect(controller.isEngineReady, isTrue,
        reason: 'engine must initialize (status: ${controller.statusMessage})');
    expect(controller.project.allClips.length, equals(1));
    expect(controller.positionMs, greaterThan(500),
        reason: 'playhead must advance: got ${controller.positionMs}ms');

    final bytes = controller.frameBytes;
    expect(bytes, isNotNull, reason: 'preview frame buffer must exist');
    expect(bytes!.isNotEmpty, isTrue);
    // Non-black: at least one pixel has color energy. A skipped/stub render
    // leaves an all-black (or all-transparent) buffer.
    var colored = 0;
    for (var i = 0; i < bytes.length; i += 4) {
      final r = bytes[i];
      final g = bytes[i + 1];
      final b = bytes[i + 2];
      final lum = (r > g ? r : g) > b ? (r > g ? r : g) : b;
      if (lum > 24) {
        colored++;
        if (colored > 20) break;
      }
    }
    expect(colored, greaterThan(0),
        reason: 'decoded frames must be non-black (got only dark pixels)');
  });
}