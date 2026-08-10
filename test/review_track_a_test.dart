import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghita_edit/src/controllers/editor_controller.dart';
import 'package:ghita_edit/src/controllers/project_service.dart';
import 'package:ghita_edit/src/models/clip.dart';
import 'package:ghita_edit/src/models/project.dart';
import 'package:ghita_edit/src/models/track.dart';

// v1.1.0 (PLAN_REVIEW Track A, gate: controllers ≥ 70%): unit coverage for
// project_service.dart (save/quickSave/listRecent/_writeFile fail path) and
// editor_controller.dart (copy/paste, group, load-project round-trip, track
// fallback) — paths that the earlier controller tests did not exercise.
void main() {
  group('ProjectService extended coverage', () {
    test('quickSave returns false before any path is set', () async {
      final service = ProjectService();
      expect(await service.quickSave(Project(name: 'x')), isFalse);
    });

    test('saveProject creates nested directories and round-trips', () async {
      final dir = await Directory.systemTemp.createTemp('ghita_a_nest_');
      addTearDown(() => dir.delete(recursive: true));
      final service = ProjectService();
      final project = Project(name: 'Nested', outputWidth: 1280);
      final path = '${dir.path}${Platform.pathSeparator}a${Platform.pathSeparator}b${Platform.pathSeparator}p.ghita';
      expect(await service.saveProject(project, path), isTrue);
      expect(File(path).existsSync(), isTrue);
      final loaded = await service.loadProject(path);
      expect(loaded?.name, equals('Nested'));
      expect(loaded?.outputWidth, equals(1280));
      // quickSave now works (last path captured by saveProject).
      expect(await service.quickSave(project), isTrue);
    });

    test('listRecentProjects returns newest-first (mtime sorted)', () async {
      final dir = await Directory.systemTemp.createTemp('ghita_a_recent_');
      addTearDown(() => dir.delete(recursive: true));
      final service = ProjectService();
      // Fix the modification times explicitly — relying on natural mtime of a
      // fast write is flaky on Windows (coarser timestamps). A controlled
      // order makes the sort behavior deterministic.
      for (var i = 0; i < 3; i++) {
        final f = File('${dir.path}${Platform.pathSeparator}$i.ghita');
        f.writeAsStringSync('{}');
        f.setLastModifiedSync(DateTime.utc(2024, 1, 1 + i, 12));
      }
      final recent = await service.listRecentProjects(dir.path);
      expect(recent.length, equals(3));
      // The most recently "modified" file (2.ghita) sorts first.
      expect(recent.first, endsWith('2.ghita'));
    });

    test('_writeFile failure path returns false and cleans the .tmp', () async {
      final dir = await Directory.systemTemp.createTemp('ghita_a_fail_');
      addTearDown(() => dir.delete(recursive: true));
      final service = ProjectService();
      final project = Project(name: 'Fail');
      // Using an existing DIRECTORY as the target makes the rename fail in a
      // controlled way (write succeeds to .tmp, rename over a directory fails).
      final path = dir.path; // it is a directory
      expect(await service.saveProject(project, path), isFalse);
      expect(File('$path.tmp').existsSync(), isFalse);
    });
  });

  group('EditorController extended coverage', () {
    late EditorController controller;
    setUp(() => controller = EditorController());
    tearDown(() => controller.dispose());

    test('copy + paste duplicates a clip at the playhead', () {
      controller.importMedia('/fake/movie.mp4');
      expect(controller.project.allClips.length, equals(1));
      controller.selectClip(controller.project.allClips.first.id);
      controller.copySelectedClip();
      expect(controller.hasClipboard, isTrue);
      controller.seek(2000);
      controller.pasteClip();
      expect(controller.project.allClips.length, equals(2));
      final pasted =
          controller.project.allClips.firstWhere((c) => c.timelineStartMs == 2000);
      expect(pasted.displayName, equals('movie.mp4'));
    });

    test('group/ungroup marks and clears group ids', () {
      controller.importMedia('/fake/a.mp4');
      controller.importMedia('/fake/b.mp4');
      controller.project.selectAll();
      controller.groupSelectedClips();
      final gids = controller.project.allClips.map((c) => c.groupId).toSet();
      expect(gids.length, equals(1));
      expect(gids.single, isNotNull);

      controller.ungroupSelectedClips();
      expect(
          controller.project.allClips.every((c) => c.groupId == null), isTrue);
    });

    test('selectRange ignores bad ids (keeps existing selection)', () {
      controller.importMedia('/fake/a.mp4');
      controller.importMedia('/fake/b.mp4');
      final clips = List.of(controller.project.allClips);
      controller.selectClip(clips[0].id);
      controller.selectRange('missing-1', 'missing-2');
      // Clips[0] is still selected — bad ids were validated before deselect.
      expect(controller.selectedClipCount, equals(1));
      expect(controller.selectedClip?.id, equals(clips[0].id));
    });

    test('loadProject round-trips through the controller', () async {
      final dir = await Directory.systemTemp.createTemp('ghita_a_load_');
      addTearDown(() => dir.delete(recursive: true));
      controller.importMedia('/fake/v.mp4');
      controller.project.name = 'Loaded Name';
      final path = '${dir.path}${Platform.pathSeparator}proj.ghita';
      expect(await controller.saveProject(path), isTrue);
      expect(await controller.loadProject(path), isTrue);
      expect(controller.project.name, equals('Loaded Name'));
      expect(controller.project.allClips.length, equals(1));
      expect(controller.canUndo, isFalse); // command history reset on load
    });

    test('trackIdForClipType falls back to first track when defaults missing',
        () {
      controller.project.tracks.clear();
      controller.project.tracks.add(Track(
        id: 'custom_track',
        name: 'Only Track',
        type: TrackType.audio,
      ));
      expect(controller.trackIdForClipType(ClipType.video), equals('custom_track'));
    });
  });

  group('Real engine: FFI guards & caches (runs when DLL present)', () {
    // v1.1.0 (PLAN_REVIEW Track A): exercise the engine-backed paths that the
    // no-engine tests can only guard. Skipped gracefully when the DLL is not
    // loadable (CI without the Windows build).
    testWidgets('initialize → caches, clamps and waveform work', (tester) async {
      final controller = EditorController();
      addTearDown(controller.dispose);
      await tester.runAsync(() async {
        await controller.init();
        if (!controller.isEngineReady) {
          markTestSkipped('engine DLL not available — FFI cache tests skipped');
          return;
        }
        final engine = controller.engineService;

        // Clamps hit the engine now.
        engine.setVolume(5.0);
        expect(engine.volume, equals(2.0));
        engine.applyFilter(30, 2.0);
        expect(engine.activeFilterType, equals(22));

        // Frame cache: LRU eviction beyond the 24-entry bound.
        final sample = List<int>.filled(16, 7);
        for (var i = 0; i < 40; i++) {
          engine.cacheFrame('k$i', Uint8List.fromList(sample));
        }
        expect(engine.getCachedFrame('k0'), isNull, reason: 'oldest evicted');
        expect(engine.getCachedFrame('k39'), isNotNull, reason: 'newest kept');

        // Waveform works on the real engine.
        engine.loadMedia('native_engine/build/test_media.mp4');
        final wave = engine.getAudioWaveform(200);
        expect(wave, isA<Float32List>());
        expect(wave.length, equals(200));
        final tlWave = engine.getTimelineWaveform(100, 0);
        expect(tlWave, isA<Float32List>());
        // 100 buckets when the timeline carries audio, 0 when the synthetic
        // clip contributes no decodable audio — both are valid states.
        expect(tlWave.length == 100 || tlWave.isEmpty, isTrue);

        // Render APIs return bytes.
        expect(engine.renderFrameAt(1000), isNotNull);
        expect(engine.renderFrameAt(1000, width: 320, height: 180), isNotNull);
      });
    });

    testWidgets('FFI wrappers exercise the real engine', (tester) async {
      final controller = EditorController();
      addTearDown(controller.dispose);
      await tester.runAsync(() async {
        await controller.init();
        if (!controller.isEngineReady) {
          markTestSkipped('engine DLL not available — FFI wrapper tests skipped');
          return;
        }
        final engine = controller.engineService;

        // Timeline sync wrappers (all mirrored to the engine).
        final upsertRet = engine.upsertClip(
          clipId: 1,
          filePath: 'clip.mp4',
          startMs: 0,
          durationMs: 1000,
          sourceInMs: 0,
          trackIndex: 0,
          kind: 0,
        );
        expect(upsertRet, isTrue);
        expect(engine.hasClip(1), isTrue);
        expect(engine.setClipFilter(1, 3, 0.5), isTrue);
        expect(engine.setClipTransition(1, 1, 500), isTrue);
        expect(engine.setClipColorCorrection(clipId: 1, exposure: 0.5), isTrue);
        expect(engine.setClipText(clipId: 1, text: 'T', fontSize: 24), isTrue);
        expect(engine.setTrackState(0, muted: false, visible: true), isTrue);
        expect(engine.addClipKeyframeEx(1, 0, 0.0, 0, 0, 0, 0, 0, 0), isTrue);
        expect(engine.setClipPip(1, 0.25, 0.25, 0.5, 0.5, 0.0), isTrue);
        expect(engine.addSpeedRampPoint(1, 0.0, 1.0), isTrue);
        engine.clearSpeedCurve(1); // must not throw
        engine.clearSpeedCurve(999); // unknown clip — safe no-op
        engine.setNoiseSuppress(true); // safe no-op path
        engine.setNoiseSuppress(false);

        // Per-clip thumbnail decodes the synthetic frame.
        final thumb = engine.getThumbnail(1, 500, 96, 54);
        expect(thumb, isNotNull);
        expect(thumb!.length, equals(96 * 54 * 4));

        // Waveform upsampling path (downsamplingFactor → interpolated back).
        engine.loadMedia('native_engine/build/test_media.mp4');
        final up = engine.getAudioWaveform(400, downsamplingFactor: 2);
        expect(up.length, equals(400), reason: 'interpolated back to the full count');

        engine.removeClip(1);
        expect(engine.hasClip(1), isFalse);
        expect(engine.removeClip(1), isFalse, reason: 'missing clip → false');

        // Playback / preview state machine.
        engine.pause();
        engine.seek(0);
        engine.startPreview();
        // Cache-hit path: rendering the SAME paused position must not
        // re-render (frameGeneration does not keep climbing).
        engine.seek(1200);
        await Future<void>.delayed(const Duration(milliseconds: 80));
        final gen1 = engine.frameGeneration;
        await Future<void>.delayed(const Duration(milliseconds: 80));
        final gen2 = engine.frameGeneration;
        final hitDiff = gen2 - gen1;
        expect(hitDiff, lessThanOrEqualTo(1),
            reason: 'repeated frames at the same paused position are cache hits');
        expect(engine.frameBytes, isNotNull);
        engine.stopPreview();
      });
    });

    testWidgets('play from 0 advances even when frame 0 is cached',
        (tester) async {
      // PLAN_REVIEW fix #4 regression: scrub to 0 (frame cached), pause, then
      // play — the playhead must advance WITHOUT a manual seek.
      final controller = EditorController();
      addTearDown(controller.dispose);
      await tester.runAsync(() async {
        await controller.init();
        if (!controller.isEngineReady) {
          markTestSkipped('engine DLL not available — play-from-0 test skipped');
          return;
        }
        await controller.importMedia('native_engine/build/test_media.mp4');
        final engine = controller.engineService;
        // Cache the frame at 0 while paused.
        controller.seek(0);
        await Future<void>.delayed(const Duration(milliseconds: 120));
        final genBefore = engine.frameGeneration;
        controller.play();
        await Future<void>.delayed(const Duration(milliseconds: 700));
        final pos = controller.positionMs;
        controller.pause();
        expect(pos, greaterThan(100),
            reason: 'play at position 0 must advance (bug #4: stuck on cached frame)');
        expect(engine.frameGeneration >= genBefore, isTrue);
      });
    });
  });
}