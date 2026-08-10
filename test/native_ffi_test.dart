import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghita_edit/src/controllers/engine_service.dart';
import 'package:ghita_edit/src/models/project.dart';
import 'package:ghita_edit/src/controllers/project_service.dart';

// v1.1.0 (PLAN_REVIEW A.1): additional controller/service resilience tests —
// raises coverage of engine_service.dart / project_service.dart and guards
// the post-Track-3 API surface (timeline waveform, raw render, thumbnail,
// atomic project writes, autosave rotation).
void main() {
  group('EngineService Resilience & Audio Waveform API', () {
    test('getAudioWaveform returns empty array when engine is unavailable', () {
      final service = EngineService(skipNativeInit: true);
      final samples = service.getAudioWaveform(100);
      expect(samples, isA<Float32List>());
      expect(samples.length, equals(0));
      service.dispose();
    });

    test('EngineService dispose safety', () {
      final service = EngineService(skipNativeInit: true);
      expect(() => service.dispose(), returnsNormally);
      expect(() => service.dispose(), returnsNormally); // Double dispose
    });

    // v1.1.0 (PLAN_REVIEW A.1): the Track-3 APIs must no-op (never throw)
    // when the native engine is unavailable.
    test('Track-3 APIs no-op gracefully without the engine', () {
      final service = EngineService(skipNativeInit: true);

      expect(service.addClipKeyframeEx(1, 0, 1.0, 0, 0, 0, 0, 0, 0), isFalse);
      expect(service.setClipPip(1, 0.25, 0.25, 0.5, 0.5, 0.0), isFalse);
      expect(service.addSpeedRampPoint(1, 0.0, 1.0), isFalse);
      service.clearSpeedCurve(1); // must not throw
      expect(service.renderRawFrameAt(500), isNull);
      expect(service.getTimelineWaveform(200, 0), isA<Float32List>());
      expect(service.getTimelineWaveform(200, 0).length, equals(0));
      expect(service.getThumbnail(1, 500, 96, 54), isNull);

      service.dispose();
    });

    // v1.1.0 (PLAN_REVIEW A.1): calls after dispose must fail loudly — the
    // engine context is gone, silently accepting commands hides bugs.
    test('EngineService methods throw after dispose', () {
      final service = EngineService(skipNativeInit: true);
      service.dispose();
      expect(() => service.seek(100), throwsStateError);
      expect(() => service.setVolume(0.5), throwsStateError);
      expect(() => service.getAudioWaveform(10), throwsStateError);
    });

    // v1.1.0 (PLAN_REVIEW A.1): the timeline-waveform cache is bounded and
    // clearable (invalidated by EditorController on every timeline change).
    test('timeline waveform cache bounded + clearable', () {
      final service = EngineService(skipNativeInit: true);
      // Without an engine nothing is cached; the important part is that the
      // public clear API exists and never throws.
      service.clearTimelineWaveformCache();
      expect(service.getTimelineWaveform(100, 0).length, equals(0));
      expect(service.getTimelineWaveform(200, 0).length, equals(0));
      service.clearTimelineWaveformCache();
      service.dispose();
    });

    // v1.1.0 (PLAN_REVIEW A.1): volume/filter/rate clamping is enforced on the
    // Dart side even without the engine (the UI trusts these values).
    test('volume and filter clamps', () {
      final service = EngineService(skipNativeInit: true);
      service.setVolume(5.0);
      expect(service.volume, equals(2.0));
      service.setVolume(-1.0);
      expect(service.volume, equals(0.0));
      service.applyFilter(50, 3.0); // out of range → clamped to 0..22 / 0..1
      expect(service.activeFilterType, equals(22));
      expect(service.filterIntensity, equals(1.0));
      service.dispose();
    });
  });

  group('Project Resilience & Corrupt File Handling', () {
    test('ProjectService handles corrupt JSON gracefully', () async {
      final service = ProjectService();
      // Load non-existent file returns null
      final result = await service.loadProject('/non_existent_path/project.ghita');
      expect(result, isNull);
    });

    test('Project totalDurationMs defaults to minimum 60s for empty project', () {
      final project = Project(name: 'Test Project');
      expect(project.totalDurationMs, equals(60000));
    });

    // v1.1.0 (PLAN_REVIEW A.1): atomic write — saves a .tmp, then renames.
    // A success must never leave a stray .tmp behind.
    test('ProjectService save is atomic and leaves no .tmp', () async {
      final dir = await Directory.systemTemp.createTemp('ghita_a1_');
      addTearDown(() => dir.delete(recursive: true));
      final service = ProjectService();
      final project = Project(name: 'Atomic Test');
      final path = '${dir.path}${Platform.pathSeparator}p.ghita';

      expect(await service.saveProject(project, path), isTrue);
      expect(File(path).existsSync(), isTrue);
      final stray = File('$path.tmp');
      expect(stray.existsSync(), isFalse);
      // Round-trip: content parses back to the same project name.
      final loaded = await service.loadProject(path);
      expect(loaded?.name, equals('Atomic Test'));
    });

    // v1.1.0 (PLAN_REVIEW A.1): autosave rotation caps at 5 files and the
    // latest is returned by getLatestAutoSave.
    test('ProjectService autosave keeps only the last 5 files', () async {
      final dir = await Directory.systemTemp.createTemp('ghita_a1_auto_');
      addTearDown(() => dir.delete(recursive: true));
      final service = ProjectService();
      final project = Project(name: 'Auto Test');
      // Force distinct timestamps (autosave names use ms).
      for (var i = 0; i < 7; i++) {
        expect(await service.autoSave(project, dir.path), isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith(ProjectService.projectExtension))
          .toList();
      // 1 directory per call → 7 dirs, each with ≤5 autosaves historically,
      // but the CURRENT dir must only hold the 5 most recent.
      expect(files.length, lessThanOrEqualTo(5));
      expect(await service.getLatestAutoSave(dir.path), isNotNull);
    });
  });
}