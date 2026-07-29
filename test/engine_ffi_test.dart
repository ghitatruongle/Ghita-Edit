import 'package:flutter_test/flutter_test.dart';
import 'package:ghita_edit/src/controllers/editor_controller.dart';
import 'package:ghita_edit/src/controllers/command_history.dart';
import 'package:ghita_edit/src/models/clip.dart';
import 'package:ghita_edit/src/models/track.dart';
import 'package:ghita_edit/src/models/project.dart';

void main() {
  group('EditorController initialization', () {
    test('initializes with sensible defaults before engine is ready', () {
      final controller = EditorController();
      expect(controller.isEngineReady, isFalse);
      expect(controller.isPlaying, isFalse);
      expect(controller.positionMs, equals(0));
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
      expect(controller.statusMessage, isNotNull);
      controller.dispose();
    });

    test('project is created with default tracks', () {
      final controller = EditorController();
      expect(controller.project.tracks.length, equals(3));
      expect(controller.project.tracks[0].type, equals(TrackType.video));
      expect(controller.project.tracks[1].type, equals(TrackType.overlay));
      expect(controller.project.tracks[2].type, equals(TrackType.audio));
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

    test('invalid filter type < 0 is clamped', () {
      controller.setFilter(-1, 0.5);
      expect(controller.activeFilterType, equals(0));
    });

    test('invalid filter type > 4 is clamped', () {
      controller.setFilter(99, 0.5);
      expect(controller.activeFilterType, equals(4));
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

    test('play and pause methods work', () {
      controller.play();
      expect(controller.isPlaying, isTrue);
      controller.pause();
      expect(controller.isPlaying, isFalse);
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
      controller.importMedia('test.mp4');
    });
  });

  group('media import and clip management', () {
    late EditorController controller;

    setUp(() => controller = EditorController());
    tearDown(() => controller.dispose());

    test('importMedia adds clip to video track', () {
      controller.importMedia('/path/to/video.mp4');
      expect(controller.project.allClips.length, equals(1));
      expect(controller.project.allClips.first.displayName, equals('video.mp4'));
      expect(controller.project.allClips.first.type, equals(ClipType.video));
    });

    test('importMedia detects audio files', () {
      controller.importMedia('/path/to/song.mp3');
      expect(controller.project.allClips.first.type, equals(ClipType.audio));
    });

    test('importMedia detects image files', () {
      controller.importMedia('/path/to/photo.png');
      expect(controller.project.allClips.first.type, equals(ClipType.image));
    });

    test('empty path does nothing', () {
      controller.importMedia('');
      expect(controller.project.allClips.length, equals(0));
    });

    test('multiple imports stack on track', () {
      controller.importMedia('clip1.mp4');
      controller.importMedia('clip2.mp4');
      expect(controller.project.allClips.length, equals(2));
      final clips = controller.project.tracks[0].clips;
      expect(clips[1].timelineStartMs, greaterThan(clips[0].timelineStartMs));
    });
  });

  group('undo/redo', () {
    late EditorController controller;

    setUp(() => controller = EditorController());
    tearDown(() => controller.dispose());

    test('undo reverses import', () {
      controller.importMedia('test.mp4');
      expect(controller.project.allClips.length, equals(1));
      controller.undo();
      expect(controller.project.allClips.length, equals(0));
    });

    test('redo restores undone action', () {
      controller.importMedia('test.mp4');
      controller.undo();
      controller.redo();
      expect(controller.project.allClips.length, equals(1));
    });

    test('canUndo/canRedo reflect state', () {
      expect(controller.canUndo, isFalse);
      expect(controller.canRedo, isFalse);
      controller.importMedia('test.mp4');
      expect(controller.canUndo, isTrue);
      expect(controller.canRedo, isFalse);
      controller.undo();
      expect(controller.canUndo, isFalse);
      expect(controller.canRedo, isTrue);
    });
  });

  group('split and delete', () {
    late EditorController controller;

    setUp(() {
      controller = EditorController();
      controller.importMedia('video.mp4');
    });
    tearDown(() => controller.dispose());

    test('split at playhead creates two clips', () {
      controller.seek(5000); // Seek to 5s into a 10s clip
      controller.splitAtPlayhead();
      final videoTrack = controller.project.tracks[0];
      expect(videoTrack.clips.length, equals(2));
    });

    test('delete selected removes clip', () {
      final clip = controller.project.allClips.first;
      controller.selectClip(clip.id);
      controller.deleteSelectedClip();
      expect(controller.project.allClips.length, equals(0));
    });

    test('delete without selection shows message', () {
      controller.deselectAll();
      controller.deleteSelectedClip();
      expect(controller.statusMessage, contains('No clip selected'));
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
      controller.seek(999999);
      expect(controller.positionMs, equals(controller.durationMs));
    });

    test('valid position is set', () {
      controller.seek(15000);
      expect(controller.positionMs, equals(15000));
    });

    test('seekRelative works', () {
      controller.seek(10000);
      controller.seekRelative(-3000);
      expect(controller.positionMs, equals(7000));
    });
  });

  group('project management', () {
    late EditorController controller;

    setUp(() => controller = EditorController());
    tearDown(() => controller.dispose());

    test('new project resets state', () {
      controller.importMedia('test.mp4');
      controller.newProject();
      expect(controller.project.allClips.length, equals(0));
      expect(controller.positionMs, equals(0));
      expect(controller.isPlaying, isFalse);
    });

    test('project serializes to JSON', () {
      controller.importMedia('test.mp4');
      final json = controller.project.toJsonString();
      expect(json.contains('test.mp4'), isTrue);
      expect(json.contains('0.3.7'), isTrue);
    });

    test('project deserializes from JSON', () {
      controller.importMedia('test.mp4');
      final json = controller.project.toJsonString();
      final loaded = Project.fromJsonString(json);
      expect(loaded.allClips.length, equals(1));
      expect(loaded.allClips.first.displayName, equals('test.mp4'));
    });

    test('dynamic track add and remove work with undo/redo', () {
      expect(controller.project.tracks.length, equals(3));
      controller.addNewTrack('Extra Audio', TrackType.audio);
      expect(controller.project.tracks.length, equals(4));
      expect(controller.project.tracks.last.name, equals('Extra Audio'));

      final addedTrackId = controller.project.tracks.last.id;
      controller.undo();
      expect(controller.project.tracks.length, equals(3));

      controller.redo();
      expect(controller.project.tracks.length, equals(4));

      controller.removeTrack(addedTrackId);
      expect(controller.project.tracks.length, equals(3));
    });
  });

  group('clipboard operations', () {
    late EditorController controller;

    setUp(() {
      controller = EditorController();
      controller.importMedia('video.mp4');
    });
    tearDown(() => controller.dispose());

    test('copy and paste creates new clip', () {
      final clip = controller.project.allClips.first;
      controller.selectClip(clip.id);
      controller.copySelectedClip();
      expect(controller.hasClipboard, isTrue);
      controller.seek(15000);
      controller.pasteClip();
      expect(controller.project.allClips.length, equals(2));
    });
  });

  group('Clip model', () {
    test('splitAt works correctly', () {
      final clip = Clip(
        id: 'test',
        sourceFilePath: '/path/test.mp4',
        displayName: 'test.mp4',
        timelineStartMs: 0,
        durationMs: 10000,
      );

      final parts = clip.splitAt(5000);
      expect(parts, isNotNull);
      expect(parts!.length, equals(2));
      expect(parts[0].durationMs, equals(5000));
      expect(parts[1].durationMs, equals(5000));
      expect(parts[1].timelineStartMs, equals(5000));
    });

    test('splitAt outside bounds returns null', () {
      final clip = Clip(
        id: 'test',
        sourceFilePath: '/path/test.mp4',
        displayName: 'test.mp4',
        timelineStartMs: 0,
        durationMs: 10000,
      );

      expect(clip.splitAt(-1), isNull);
      expect(clip.splitAt(0), isNull);
      expect(clip.splitAt(10000), isNull);
      expect(clip.splitAt(15000), isNull);
    });

    test('toJson/fromJson round-trips correctly', () {
      final clip = Clip(
        id: 'c1',
        sourceFilePath: '/test.mp4',
        displayName: 'test.mp4',
        timelineStartMs: 5000,
        durationMs: 8000,
        filterType: 2,
        filterIntensity: 0.7,
        volume: 0.8,
        type: ClipType.audio,
      );

      final json = clip.toJson();
      final restored = Clip.fromJson(json);
      expect(restored.id, equals('c1'));
      expect(restored.timelineStartMs, equals(5000));
      expect(restored.durationMs, equals(8000));
      expect(restored.filterType, equals(2));
      expect(restored.type, equals(ClipType.audio));
    });
  });

  group('Track model', () {
    test('addClipAtEnd stacks clips', () {
      final track = Track(id: 't1', name: 'Video', type: TrackType.video);
      final clip1 = Clip(id: 'c1', sourceFilePath: 'a.mp4', displayName: 'a', timelineStartMs: 0, durationMs: 5000);
      final clip2 = Clip(id: 'c2', sourceFilePath: 'b.mp4', displayName: 'b', timelineStartMs: 0, durationMs: 3000);

      track.addClipAtEnd(clip1);
      track.addClipAtEnd(clip2);

      expect(track.clips.length, equals(2));
      expect(track.clips[1].timelineStartMs, equals(5000));
      expect(track.durationMs, equals(8000));
    });

    test('removeClip works', () {
      final track = Track(id: 't1', name: 'Video', type: TrackType.video);
      final clip = Clip(id: 'c1', sourceFilePath: 'a.mp4', displayName: 'a', timelineStartMs: 0, durationMs: 5000);
      track.addClipAtEnd(clip);
      expect(track.removeClip('c1'), isNotNull);
      expect(track.clips.length, equals(0));
    });

    test('clipAtPosition finds correct clip', () {
      final track = Track(id: 't1', name: 'Video', type: TrackType.video);
      final clip = Clip(id: 'c1', sourceFilePath: 'a.mp4', displayName: 'a', timelineStartMs: 1000, durationMs: 5000);
      track.clips.add(clip);

      expect(track.clipAtPosition(500), isNull);
      expect(track.clipAtPosition(1000), equals(clip));
      expect(track.clipAtPosition(3000), equals(clip));
      expect(track.clipAtPosition(6000), isNull);
    });
  });

  group('CommandHistory', () {
    test('execute/undo/redo cycle works', () {
      final history = CommandHistory();
      final project = Project(name: 'Test');
      final clip = Clip(id: 'c1', sourceFilePath: 'a.mp4', displayName: 'a', timelineStartMs: 0, durationMs: 5000);

      final cmd = AddClipCommand(trackId: 'track_video_1', clip: clip, positionMs: 0);
      history.execute(cmd, project);
      expect(project.allClips.length, equals(1));

      history.undo(project);
      expect(project.allClips.length, equals(0));

      history.redo(project);
      expect(project.allClips.length, equals(1));

      history.dispose();
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
