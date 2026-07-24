// TODO: Add a mock EngineService and real FFI-binding tests for complete coverage.
// Currently EditorController is tested without an actual native engine — this covers
// state management only. In the future, inject a fake GhitaNativeBindings (or ffi::NativeLibraryMock)
// so we can verify that play/pause/seek/volume/filter actually reach the C++ layer.
// Example: `test('play() forwards to engine', () { ... });`
import 'package:flutter_test/flutter_test.dart';
import 'package:ghita_edit/src/controllers/editor_controller.dart';

void main() {
  group('EditorController initialization', () {
    test('initializes with sensible defaults before engine is ready', () {
      final controller = EditorController();
      expect(controller.isEngineReady, isFalse);
      expect(controller.isPlaying, isFalse);
      expect(controller.positionMs, equals(0));
      expect(controller.durationMs, equals(60000));
      expect(controller.volume, equals(1.0));
      expect(controller.filterIntensity, equals(1.0));
      expect(controller.activeFilterType, equals(0));
      expect(controller.currentMediaName, contains('No media loaded'));
      expect(controller.statusMessage, isNotEmpty);
      controller.dispose();
    });

    test('init does not throw when engine unavailable', () async {
      final controller = EditorController();
      await controller.init();
      // Should produce some status message after init attempt
      expect(controller.statusMessage, isNotNull);
      controller.dispose();
    });
  });

  group('volume clamping', () {
    late EditorController controller;

    setUp(() => controller = EditorController());
    tearDown(() => controller.dispose());

    test('negative values clamp to 0.0', () {
      controller.setVolume(-0.5);
      expect(controller.volume, equals(0.0));
    });

    test('excessive values clamp to 2.0', () {
      controller.setVolume(3.0);
      expect(controller.volume, equals(2.0));
    });

    test('valid values are preserved', () {
      controller.setVolume(0.75);
      expect(controller.volume, equals(0.75));
    });

    test('boundary values work correctly', () {
      controller.setVolume(0.0);
      expect(controller.volume, equals(0.0));
      controller.setVolume(2.0);
      expect(controller.volume, equals(2.0));
    });
  });

  group('filter clamping', () {
    late EditorController controller;

    setUp(() => controller = EditorController());
    tearDown(() => controller.dispose());

    test('invalid filter type < 0 is rejected', () {
      controller.setFilter(-1, 0.5);
      expect(controller.activeFilterType, equals(0));
    });

    test('invalid filter type > 4 is rejected', () {
      controller.setFilter(99, 0.5);
      expect(controller.activeFilterType, equals(0));
    });

    test('valid types 0-4 are accepted', () {
      for (final t in [0, 1, 2, 3, 4]) {
        controller.setFilter(t, 0.5);
        expect(controller.activeFilterType, equals(t), reason: 'type $t');
      }
    });

    test('intensity below zero clamps to 0.0', () {
      controller.setFilter(2, -0.5);
      expect(controller.filterIntensity, equals(0.0));
    });

    test('intensity above one clamps to 1.0', () {
      controller.setFilter(2, 1.5);
      expect(controller.filterIntensity, equals(1.0));
    });

    test('valid intensity range is preserved', () {
      controller.setFilter(1, 0.0);
      expect(controller.filterIntensity, equals(0.0));
      controller.setFilter(1, 0.5);
      expect(controller.filterIntensity, equals(0.5));
      controller.setFilter(1, 1.0);
      expect(controller.filterIntensity, equals(1.0));
    });
  });

  group('play/pause toggle', () {
    late EditorController controller;

    setUp(() => controller = EditorController());
    tearDown(() => controller.dispose());

    test('starts paused', () {
      expect(controller.isPlaying, isFalse);
    });

    test('toggle transitions correctly', () {
      controller.togglePlayPause();
      expect(controller.isPlaying, isTrue);
      controller.togglePlayPause();
      expect(controller.isPlaying, isFalse);
      controller.togglePlayPause();
      expect(controller.isPlaying, isTrue);
    });
  });

  group('dispose safety', () {
    test('can dispose twice without throwing', () {
      final controller = EditorController();
      controller.dispose();
      controller.dispose();
    });

    test('operations after dispose do not throw', () {
      final controller = EditorController();
      controller.dispose();
      controller.togglePlayPause();
      controller.seek(1000);
      controller.setVolume(0.5);
      controller.setFilter(1, 0.5);
      controller.loadMedia('test.mp4');
    });
  });

  group('media loading', () {
    late EditorController controller;

    setUp(() => controller = EditorController());
    tearDown(() => controller.dispose());

    test('extracts file name from path', () {
      controller.loadMedia('/path/to/video.mp4');
      expect(controller.currentMediaName, equals('video.mp4'));
      expect(controller.statusMessage, contains('video.mp4'));
      expect(controller.positionMs, equals(0));
    });

    test('handles Windows-style paths', () {
      controller.loadMedia('C:/Media/sample.mov');
      expect(controller.currentMediaName, equals('sample.mov'));
    });

    test('empty path does nothing', () {
      controller.loadMedia('');
      expect(controller.currentMediaName, contains('No media loaded'));
      expect(controller.positionMs, equals(0));
    });
  });

  group('seek clamping', () {
    late EditorController controller;

    setUp(() => controller = EditorController());
    tearDown(() => controller.dispose());

    test('negative position clamps to 0', () {
      controller.seek(-100);
      expect(controller.positionMs, equals(0));
    });

    test('excessive position clamps to duration', () {
      controller.seek(99999);
      expect(controller.positionMs, equals(60000));
    });

    test('valid position is set', () {
      controller.seek(15000);
      expect(controller.positionMs, equals(15000));
    });
  });

  group('engine version', () {
    test('defaults to empty before initialization', () {
      final controller = EditorController();
      expect(controller.engineVersion, isEmpty);
      controller.dispose();
    });
  });
}
