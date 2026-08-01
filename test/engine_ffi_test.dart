import 'package:flutter_test/flutter_test.dart';
import 'package:ghita_edit/src/controllers/editor_controller.dart';
import 'package:ghita_edit/src/controllers/command_history.dart';
import 'package:ghita_edit/src/core/version.dart';
import 'package:ghita_edit/src/models/clip.dart';
import 'package:ghita_edit/src/models/track.dart';
import 'package:ghita_edit/src/models/project.dart';
import 'package:ghita_edit/src/ui/widgets/timeline_panel.dart';

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

    test('invalid filter type > 10 is clamped', () {
      controller.setFilter(99, 0.5);
      expect(controller.activeFilterType, equals(10));
    });

    test('valid types 0-10 are accepted', () {
      for (final t in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]) {
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
      controller.seek(5000);
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
      // Version comes from the centralized version constants, not hardcoded
      expect(json.contains(flutterVersion), isTrue);
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

  // ========== v0.5.5 New Tests ==========

  group('multi-select clips', () {
    late EditorController controller;

    setUp(() {
      controller = EditorController();
      controller.importMedia('clip1.mp4');
      controller.importMedia('clip2.mp4');
      controller.importMedia('clip3.mp4');
      // allClips returns a copy; patch IDs directly on the track clips
      for (final track in controller.project.tracks) {
        for (var i = 0; i < track.clips.length; i++) {
          track.clips[i] = track.clips[i].copyWith(id: 'clip_${i + 1}');
        }
      }
    });
    tearDown(() => controller.dispose());

    test('toggleClipSelection adds/removes from selection', () {
      final c1 = controller.project.allClips[0].id;
      final c2 = controller.project.allClips[1].id;

      controller.toggleClipSelection(c1);
      expect(controller.selectedClipCount, equals(1));
      expect(controller.selectedClip?.id, equals(c1));

      controller.toggleClipSelection(c2);
      expect(controller.selectedClipCount, equals(2));
      expect(controller.selectedClips.map((c) => c.id).contains(c2), isTrue);
    });

    test('selectRange selects clips between two IDs', () {
      final c1 = controller.project.allClips[0].id;
      final c3 = controller.project.allClips[2].id;

      controller.selectRange(c1, c3);
      expect(controller.selectedClipCount, equals(3));
    });

    test('deselectAll clears selection', () {
      final c1 = controller.project.allClips[0].id;
      controller.toggleClipSelection(c1);
      expect(controller.selectedClipCount, equals(1));
      controller.deselectAll();
      expect(controller.selectedClipCount, equals(0));
      expect(controller.selectedClip, isNull);
    });

    test('selectClip clears previous selection (single-select)', () {
      final c1 = controller.project.allClips[0].id;
      final c2 = controller.project.allClips[1].id;

      controller.toggleClipSelection(c1);
      controller.toggleClipSelection(c2);
      expect(controller.selectedClipCount, equals(2));

      controller.selectClip(c1);
      expect(controller.selectedClipCount, equals(1));
      expect(controller.selectedClip?.id, equals(c1));
    });

    test('multi-delete removes all selected clips', () {
      final c1 = controller.project.allClips[0].id;
      final c2 = controller.project.allClips[1].id;

      controller.toggleClipSelection(c1);
      controller.toggleClipSelection(c2);
      expect(controller.selectedClipCount, equals(2));

      controller.deleteSelectedClip();
      expect(controller.project.allClips.length, equals(1));
      expect(controller.statusMessage, contains('2 clips'));
    });
  });

  group('trim operations', () {
    late EditorController controller;

    setUp(() {
      controller = EditorController();
      controller.importMedia('video.mp4');
    });
    tearDown(() => controller.dispose());

    test('trimClipStart reduces clip duration and shifts start', () {
      final clip = controller.project.allClips.first;
      final originalStart = clip.timelineStartMs;
      final originalDuration = clip.durationMs;
      final originalSourceIn = clip.sourceInMs;

      controller.trimClipStart(clip.id, originalStart + 1000);
      expect(clip.timelineStartMs, equals(originalStart + 1000));
      expect(clip.durationMs, lessThan(originalDuration));
      expect(clip.sourceInMs, equals(originalSourceIn + 1000));
    });

    test('trimClipEnd increases clip duration', () {
      final clip = controller.project.allClips.first;
      final originalDuration = clip.durationMs;
      final newEnd = clip.timelineStartMs + originalDuration + 2000;

      controller.trimClipEnd(clip.id, newEnd);
      expect(clip.durationMs, equals(originalDuration + 2000));
      expect(clip.sourceOutMs, equals(clip.sourceInMs + originalDuration + 2000));
    });

    test('trim is undoable', () {
      final clip = controller.project.allClips.first;
      final originalDuration = clip.durationMs;

      controller.trimClipEnd(clip.id, clip.timelineEndMs + 2000);
      expect(clip.durationMs, equals(originalDuration + 2000));

      controller.undo();
      expect(clip.durationMs, equals(originalDuration));
    });
  });

  group('Clip model extensions (v0.5.5)', () {
    test('speed and opacity default to 1.0', () {
      final clip = Clip(
        id: 'test',
        sourceFilePath: '/test.mp4',
        displayName: 'test.mp4',
        timelineStartMs: 0,
        durationMs: 5000,
      );
      expect(clip.speed, equals(1.0));
      expect(clip.opacity, equals(1.0));
    });

    test('speed and opacity serialize to JSON', () {
      final clip = Clip(
        id: 'c1',
        sourceFilePath: '/test.mp4',
        displayName: 'test.mp4',
        timelineStartMs: 0,
        durationMs: 5000,
        speed: 1.5,
        opacity: 0.8,
      );

      final json = clip.toJson();
      expect(json['speed'], equals(1.5));
      expect(json['opacity'], equals(0.8));

      final restored = Clip.fromJson(json);
      expect(restored.speed, equals(1.5));
      expect(restored.opacity, equals(0.8));
    });

    test('copyWith preserves speed and opacity', () {
      final clip = Clip(
        id: 'test',
        sourceFilePath: '/test.mp4',
        displayName: 'test.mp4',
        timelineStartMs: 0,
        durationMs: 5000,
        speed: 2.0,
        opacity: 0.5,
      );

      final copy = clip.copyWith(id: 'copy');
      expect(copy.speed, equals(2.0));
      expect(copy.opacity, equals(0.5));
    });
  });

  group('SnapEngine', () {
    test('off mode never snaps', () {
      final engine = SnapEngine(mode: SnapMode.off);
      expect(engine.snap(1500, 100.0), isNull);
    });

    test('snaps to 1s grid when within threshold', () {
      final engine = SnapEngine(mode: SnapMode.oneSecond, snapThresholdPx: 10.0);
      // 1500ms is 1.5s, 0.5s away from 1s and 2s grid
      // With pxPerSec=100, 500ms = 50px which is > 10px threshold
      expect(engine.snap(1500, 100.0), isNull);

      // 1050ms is 0.05s away from 1s grid, 5px at 100px/s
      expect(engine.snap(1050, 100.0), equals(1000));
    });

    test('snaps to 0.5s grid', () {
      final engine = SnapEngine(mode: SnapMode.halfSecond, snapThresholdPx: 10.0);
      // 750ms is 0.25s from 0.5s and 0.75s grids
      // 250ms * 100px/s = 25px > 10px threshold
      expect(engine.snap(750, 100.0), isNull);

      // 525ms is 25ms from 0.5s grid = 2.5px < 10px
      expect(engine.snap(525, 100.0), equals(500));
    });

    test('exact grid points return themselves', () {
      final engine = SnapEngine(mode: SnapMode.oneSecond);
      expect(engine.snap(1000, 100.0), equals(1000));
      expect(engine.snap(2000, 100.0), equals(2000));
    });
  });

  group('track operations', () {
    test('setTrackMute updates track state', () {
      final controller = EditorController();
      final trackId = controller.project.tracks[0].id;
      expect(controller.project.tracks[0].isMuted, isFalse);

      controller.setTrackMute(trackId, true);
      expect(controller.project.tracks[0].isMuted, isTrue);
      expect(controller.statusMessage, contains('muted'));

      controller.setTrackMute(trackId, false);
      expect(controller.project.tracks[0].isMuted, isFalse);
      controller.dispose();
    });

    test('setTrackVolume updates track state', () {
      final controller = EditorController();
      final trackId = controller.project.tracks[0].id;
      controller.setTrackVolume(trackId, 0.5);
      expect(controller.project.tracks[0].volume, equals(0.5));
      controller.dispose();
    });
  });

  // ========== v0.7.8: Clip property commands (undoable) ==========

  group('clip property commands (v0.7.8)', () {
    late EditorController controller;
    late String clipId;

    setUp(() {
      controller = EditorController();
      controller.importMedia('video.mp4');
      clipId = controller.project.allClips.first.id;
    });
    tearDown(() => controller.dispose());

    test('setClipSpeed changes clip and is undoable', () {
      controller.setClipSpeed(clipId, 2.0);
      expect(controller.project.allClips.first.speed, equals(2.0));
      controller.undo();
      expect(controller.project.allClips.first.speed, equals(1.0));
      controller.redo();
      expect(controller.project.allClips.first.speed, equals(2.0));
    });

    test('setClipOpacity clamps to [0,1]', () {
      controller.setClipOpacity(clipId, 5.0);
      expect(controller.project.allClips.first.opacity, equals(1.0));
      controller.setClipOpacity(clipId, -3.0);
      expect(controller.project.allClips.first.opacity, equals(0.0));
    });

    test('slider drag coalesces into one undo entry', () {
      controller.setClipSpeed(clipId, 1.1);
      controller.setClipSpeed(clipId, 1.3);
      controller.setClipSpeed(clipId, 1.6);
      controller.setClipSpeed(clipId, 2.0);
      // Four ticks of one drag → exactly one undo entry
      expect(controller.canUndo, isTrue);
      controller.undo();
      // Undo restores the pre-gesture value (1.0), not an intermediate one
      expect(controller.project.allClips.first.speed, equals(1.0));
      expect(controller.project.allClips.first.opacity, equals(1.0));
      controller.redo();
      expect(controller.project.allClips.first.speed, equals(2.0));
    });

    test('different properties do not coalesce', () {
      controller.setClipSpeed(clipId, 2.0);
      controller.setClipOpacity(clipId, 0.5);
      controller.undo(); // undo opacity only
      expect(controller.project.allClips.first.opacity, equals(1.0));
      expect(controller.project.allClips.first.speed, equals(2.0));
      controller.undo(); // undo speed
      expect(controller.project.allClips.first.speed, equals(1.0));
    });

    test('different clips do not coalesce', () {
      controller.importMedia('second.mp4');
      final secondId = controller.project.allClips.last.id;
      controller.setClipSpeed(clipId, 2.0);
      controller.setClipSpeed(secondId, 2.5);
      controller.undo();
      expect(controller.project.allClips.last.speed, equals(1.0));
      expect(controller.project.allClips.first.speed, equals(2.0));
      controller.undo();
      expect(controller.project.allClips.first.speed, equals(1.0));
    });

    test('interleaved actions break coalescing chain', () {
      controller.setClipSpeed(clipId, 2.0);
      controller.setClipOpacity(clipId, 0.5); // different property breaks chain
      controller.setClipSpeed(clipId, 3.0);   // does NOT coalesce with first
      controller.undo();
      expect(controller.project.allClips.first.speed, equals(2.0));
    });

    test('transition persists on model and round-trips JSON', () {
      controller.setClipTransition(clipId, 3, 500); // Slide
      expect(controller.project.allClips.first.transitionType, equals(3));
      final json = controller.project.toJsonString();
      expect(json.contains('transitionType'), isTrue);
      final loaded = Project.fromJsonString(json);
      expect(loaded.allClips.first.transitionType, equals(3));
    });
  });
}
