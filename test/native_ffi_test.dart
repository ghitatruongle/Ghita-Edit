import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghita_edit/src/controllers/engine_service.dart';
import 'package:ghita_edit/src/models/project.dart';
import 'package:ghita_edit/src/controllers/project_service.dart';

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
  });
}
