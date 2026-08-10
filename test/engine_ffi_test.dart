import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghita_edit/src/controllers/editor_controller.dart';
import 'package:ghita_edit/src/controllers/command_history.dart';
import 'package:ghita_edit/src/controllers/project_service.dart';
import 'package:ghita_edit/src/core/version.dart';
import 'package:ghita_edit/src/models/clip.dart';
import 'package:ghita_edit/src/models/curve_speed.dart';
import 'package:ghita_edit/src/models/track.dart';
import 'package:ghita_edit/src/models/project.dart';
import 'package:ghita_edit/src/ui/widgets/timeline_panel.dart';

// v0.8.0: Extended test file — appends the new feature groups after main's
// existing groups (see bottom of file).

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

    // v0.8.0: Filter range extended to 0-20 (was 0-10).
    // v1.0.2: Extended to 0-22 (Skin Retouch 21, Chroma Key 22).
    test('invalid filter type > 22 is clamped', () {
      controller.setFilter(99, 0.5);
      expect(controller.activeFilterType, equals(22));
    });

    test('valid types 0-22 are accepted', () {
      for (final t in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 14, 15, 17, 20, 21, 22]) {
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

    test('splitAt at speed partitions the source range exactly', () {
      // v1.0.1: with speed != 1.0 the halves must cover speed * duration of
      // source material, and the two halves must partition the original
      // source range exactly (no ±1ms drift on repeated splits).
      final clip = Clip(
        id: 'test',
        sourceFilePath: '/path/test.mp4',
        displayName: 'test.mp4',
        timelineStartMs: 0,
        durationMs: 1000,
        sourceInMs: 100,
        sourceOutMs: 1600, // 1000ms timeline at 1.5x → 1500ms of source
        speed: 1.5,
      );

      final parts = clip.splitAt(333);
      expect(parts, isNotNull);
      final left = parts![0];
      final right = parts[1];

      // Halves are contiguous — left source-out == right source-in.
      expect(left.sourceOutMs, equals(right.sourceInMs));
      // The right half never extends past the total source span.
      expect(right.sourceOutMs, equals(clip.sourceOutMs));
      // Left half covers round(333 * 1.5) = 500ms of source.
      expect(left.sourceOutMs - left.sourceInMs, equals(500));

      // Repeated splits never drift past the media end.
      final again = right.splitAt(400);
      expect(again, isNotNull);
      expect(again![1].sourceOutMs, lessThanOrEqualTo(clip.sourceOutMs));
    });

    test('splitAt at 2x speed covers twice the source per timeline ms', () {
      final clip = Clip(
        id: 'test',
        sourceFilePath: '/path/test.mp4',
        displayName: 'test.mp4',
        timelineStartMs: 0,
        durationMs: 5000,
        sourceInMs: 0,
        sourceOutMs: 10000, // 2x speed → 10s of source in 5s of timeline
        speed: 2.0,
      );

      final parts = clip.splitAt(2500);
      expect(parts, isNotNull);
      // Mid-point split: each half covers 5000ms of source.
      expect(parts![0].sourceOutMs, equals(5000));
      expect(parts[1].sourceInMs, equals(5000));
      expect(parts[1].sourceOutMs, equals(10000));
      // Timeline halves stay at the split position.
      expect(parts[0].durationMs, equals(2500));
      expect(parts[1].durationMs, equals(2500));
      expect(parts[1].timelineStartMs, equals(2500));
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

  // ========== v0.7.9: Bug-fix regression tests ==========

  group('v0.7.9 bug fixes', () {
    test('BUG-01: fromJson survives missing sourceOutMs/durationMs', () {
      // Legacy file without sourceOutMs → sourceInMs + durationMs
      final legacyJson = <String, dynamic>{
        'id': 'c1',
        'sourceFilePath': '/a.mp4',
        'displayName': 'a.mp4',
        'timelineStartMs': 0,
        'durationMs': 10000,
        'sourceInMs': 2000,
      };
      final clip = Clip.fromJson(legacyJson);
      expect(clip.sourceOutMs, equals(12000));

      // Corrupt file missing durationMs entirely — must NOT throw TypeError
      final corruptJson = <String, dynamic>{
        'id': 'c2',
        'sourceFilePath': '/b.mp4',
        'displayName': 'b.mp4',
        'timelineStartMs': 0,
      };
      final clip2 = Clip.fromJson(corruptJson);
      expect(clip2.durationMs, equals(0));
      expect(clip2.sourceOutMs, equals(0));
    });

    test('BUG-02: nextId stays unique across 1000 rapid calls', () {
      final ids = <String>{};
      for (var i = 0; i < 1000; i++) {
        ids.add(Clip.nextId());
      }
      expect(ids.length, equals(1000));
    });

    test('BUG-07: splitAt rejects zero-duration halves', () {
      final clip = Clip(
        id: 'test',
        sourceFilePath: '/path/test.mp4',
        displayName: 'test.mp4',
        timelineStartMs: 0,
        durationMs: 10000,
      );
      // Boundary positions are rejected outright
      expect(clip.splitAt(0), isNull);
      expect(clip.splitAt(10000), isNull);
      // A 1ms sliver still yields two valid positive-duration halves
      final parts = clip.splitAt(1);
      expect(parts, isNotNull);
      expect(parts![0].durationMs, greaterThan(0));
      expect(parts[1].durationMs, greaterThan(0));
    });

    test('BUG-06: saveProject writes atomically and leaves no .tmp', () async {
      final service = ProjectService();
      final dir = await Directory.systemTemp.createTemp('ghita_v079_');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/test.ghita';
      final project = Project(name: 'Atomic Test');

      final ok = await service.saveProject(project, path);
      expect(ok, isTrue);
      expect(File(path).existsSync(), isTrue);
      // No stray temp file after a successful save
      expect(File('$path.tmp').existsSync(), isFalse);

      // Round-trips correctly
      final loaded = await service.loadProject(path);
      expect(loaded, isNotNull);
      expect(loaded!.name, equals('Atomic Test'));
    });

    test('BUG-04: cut semantics = copy + delete, then paste restores', () {
      final controller = EditorController();
      addTearDown(controller.dispose);
      controller.importMedia('video.mp4');
      final clip = controller.project.allClips.first;
      controller.selectClip(clip.id);

      // Same sequence the "Cut (Ctrl+X)" menu item performs
      controller.copySelectedClip();
      expect(controller.hasClipboard, isTrue);
      controller.deleteSelectedClip();
      expect(controller.project.allClips.length, equals(0));

      // Clipboard still holds the cut clip → paste brings it back
      controller.seek(15000);
      controller.pasteClip();
      expect(controller.project.allClips.length, equals(1));
    });
  });

  // ========== v0.7.9 deep-review regression tests ==========

  group('v0.7.9 deep-review fixes', () {
    test('BUG-R5: fromJson survives missing timelineStartMs', () {
      final json = <String, dynamic>{
        'id': 'c1',
        'sourceFilePath': '/a.mp4',
        'displayName': 'a.mp4',
        'durationMs': 5000,
      };
      final clip = Clip.fromJson(json);
      expect(clip.timelineStartMs, equals(0));
      expect(clip.durationMs, equals(5000));
    });

    test('BUG-R4: overlap undo/redo restores shifted clips correctly', () {
      final controller = EditorController();
      addTearDown(controller.dispose);

      // First clip occupies 0–5000
      controller.importMedia('a.mp4');
      final first = controller.project.allClips.first;

      // Add a second clip at 3000 → overlap shifts the first clip to 10000
      controller.project.tracks[0].clips.add(
        Clip(
          id: Clip.nextId(),
          sourceFilePath: '/b.mp4',
          displayName: 'b.mp4',
          timelineStartMs: 3000,
          durationMs: 5000,
          type: ClipType.video,
        ),
      );
      final cmd = AddClipCommand(
        trackId: controller.project.tracks[0].id,
        clip: controller.project.tracks[0].clips.last,
        positionMs: 3000,
      );
      controller.commandHistory.execute(cmd, controller.project);
      // Clip b spans 3000–8000 → clip a is shifted to 8000
      expect(first.timelineStartMs, equals(8000));

      // Undo → first clip restored to its original start (0)
      controller.undo();
      expect(first.timelineStartMs, equals(0));

      // Redo → overlap resolution again
      controller.redo();
      expect(first.timelineStartMs, equals(8000));
    });

    test('v1.0.1: addClipAt between two adjacent clips never stacks them', () {
      // Inserting a clip into the middle of two adjacent clips used to move
      // BOTH clips to exactly newClip.timelineEndMs, leaving them overlapping
      // each other at the same position. The cascade must place them
      // sequentially so the timeline stays non-overlapping.
      final track = Track(id: 't', name: 't', type: TrackType.video);
      final a = Clip(
        id: 'a', sourceFilePath: '/a.mp4', displayName: 'a',
        timelineStartMs: 0, durationMs: 100,
      );
      final b = Clip(
        id: 'b', sourceFilePath: '/b.mp4', displayName: 'b',
        timelineStartMs: 100, durationMs: 100,
      );
      final inserted = Clip(
        id: 'c', sourceFilePath: '/c.mp4', displayName: 'c',
        timelineStartMs: 50, durationMs: 100,
      );
      track.clips.addAll([a, b]);

      track.addClipAt(inserted, 50);

      // Inserted clip keeps its requested position.
      expect(inserted.timelineStartMs, equals(50));
      // The adjacent clips are pushed past the new clip, in order.
      expect(a.timelineStartMs, equals(150));
      expect(b.timelineStartMs, equals(250));
      // No pair of clips overlaps.
      for (final clip in track.clips) {
        for (final other in track.clips) {
          if (identical(clip, other)) continue;
          final overlaps = clip.timelineStartMs < other.timelineEndMs &&
              clip.timelineEndMs > other.timelineStartMs;
          expect(overlaps, isFalse,
              reason: '${clip.id} overlaps ${other.id}');
        }
      }
    });

    test('v1.0.1: shifted clip never collides with a clip that starts at '
        'the insertion end', () {
      // A@0-100 overlaps the new clip; B@150-250 starts EXACTLY at
      // newClip.timelineEndMs (touching, so it is NOT overlapping and must
      // not move). The shifted A must land past B, not on top of it.
      final track = Track(id: 't', name: 't', type: TrackType.video);
      final a = Clip(
        id: 'a', sourceFilePath: '/a.mp4', displayName: 'a',
        timelineStartMs: 0, durationMs: 100,
      );
      final b = Clip(
        id: 'b', sourceFilePath: '/b.mp4', displayName: 'b',
        timelineStartMs: 150, durationMs: 100,
      );
      final inserted = Clip(
        id: 'c', sourceFilePath: '/c.mp4', displayName: 'c',
        timelineStartMs: 50, durationMs: 100,
      );
      track.clips.addAll([a, b]);

      track.addClipAt(inserted, 50);

      // The touching clip keeps its position; the shifted clip jumps past it.
      expect(b.timelineStartMs, equals(150));
      expect(a.timelineStartMs, equals(250));
      // No pair of clips overlaps.
      for (final clip in track.clips) {
        for (final other in track.clips) {
          if (identical(clip, other)) continue;
          final overlaps = clip.timelineStartMs < other.timelineEndMs &&
              clip.timelineEndMs > other.timelineStartMs;
          expect(overlaps, isFalse,
              reason: '${clip.id} overlaps ${other.id}');
        }
      }
    });
  });

  // ========== v0.8.0 tests ==========

  group('v0.8.0 timeline sync (engine-less)', () {
    late EditorController controller;

    setUp(() => controller = EditorController());
    tearDown(() => controller.dispose());

    test('syncTimelineToEngine is a safe no-op without the engine', () {
      // Must not throw when the native engine is unavailable.
      controller.syncTimelineToEngine();
      controller.markEngineSync();
      controller.importMedia('/fake/video.mp4');
      controller.splitAtPlayhead();
      controller.undo();
      controller.redo();
      expect(controller.project.allClips.length, 1);
    });

    test('setClipColorCorrection updates the model', () {
      controller.importMedia('/fake/video.mp4');
      final clip = controller.project.allClips.first;
      controller.setClipColorCorrection(
        clip.id,
        exposure: 0.5,
        contrast: -0.25,
        saturation: 0.8,
        temperature: 0.4,
      );
      expect(clip.colorExposure, equals(0.5));
      expect(clip.colorContrast, equals(-0.25));
      expect(clip.colorSaturation, equals(0.8));
      expect(clip.colorTemperature, equals(0.4));
    });

    test('track volume clamps to 0-2 and mutates the model', () {
      final track = controller.project.tracks.first;
      controller.setTrackVolume(track.id, 5.0);
      expect(track.volume, equals(2.0));
      controller.setTrackVolume(track.id, -1.0);
      expect(track.volume, equals(0.0));
      controller.setTrackVolume(track.id, 1.5);
      expect(track.volume, equals(1.5));
    });

    test('track mute/visibility toggle without engine does not crash', () {
      final track = controller.project.tracks.first;
      controller.setTrackMute(track.id, true);
      expect(track.isMuted, isTrue);
      controller.setTrackVisible(track.id, false);
      expect(track.isVisible, isFalse);
      controller.setTrackLock(track.id, true);
      expect(track.isLocked, isTrue);
    });

    test('filter range now reaches 20', () {
      controller.setFilter(20, 1.0);
      expect(controller.activeFilterType, equals(20));
      controller.setFilter(11, 0.5);
      expect(controller.activeFilterType, equals(11));
    });
  });

  // ========== v1.1.0 regression tests (PLAN_1.1.0 Track 1) ==========

  group('PLAN 1.1 Track 1 regression', () {
    late EditorController controller;

    setUp(() => controller = EditorController());
    tearDown(() => controller.dispose());

    test('trimClipStart never leaves a clip shorter than the minimum duration', () {
      // PLAN 1.1/B8: the left trim handle used to be able to create a
      // 0/negative-duration clip; the model layer now clamps to
      // Track.kMinClipDurationMs as the last line of defense.
      final track = controller.project.tracks.first;
      final clip = Clip(
        id: Clip.nextId(),
        sourceFilePath: '/fake/video.mp4',
        displayName: 't.mp4',
        timelineStartMs: 1000,
        durationMs: 5000,
        type: ClipType.video,
      );
      track.clips.add(clip);

      // Trim start almost to the right edge (delta 4950 of 5000) → the
      // effective delta clamps so at least kMinClipDurationMs survives.
      track.trimClipStart(clip.id, 1000 + 4950);
      expect(clip.durationMs, greaterThanOrEqualTo(Track.kMinClipDurationMs));
      expect(clip.timelineStartMs + clip.durationMs, equals(6000));

      // Trimming past the end is a no-op (delta >= duration).
      track.trimClipStart(clip.id, 1000 + 6000);
      expect(clip.durationMs, greaterThanOrEqualTo(Track.kMinClipDurationMs));

      // trimClipEnd to the clip start is a no-op too.
      track.trimClipEnd(clip.id, clip.timelineStartMs);
      expect(clip.durationMs, greaterThanOrEqualTo(Track.kMinClipDurationMs));
    });

    test('ChangeMultiClipFilterCommand applies to every clip and undoes as one', () {
      // PLAN 1.1/B12: the inspector multi-select "Apply Filter" used to
      // mutate clips directly (no undo, no engine sync). The new command
      // snapshots the whole batch → one Ctrl+Z restores all clips.
      controller.importMedia('/fake/a.mp4');
      controller.importMedia('/fake/b.mp4');
      final clips = controller.project.allClips;
      expect(clips.length, greaterThanOrEqualTo(2));

      final history = controller.commandHistory;
      history.execute(
        ChangeMultiClipFilterCommand(
          clipIds: clips.map((c) => c.id).toList(),
          newFilterType: 15,
          newIntensity: 0.5,
        ),
        controller.project,
      );
      for (final c in clips) {
        expect(c.filterType, equals(15));
        expect(c.filterIntensity, equals(0.5));
      }

      expect(history.canUndo, isTrue);
      history.undo(controller.project);
      for (final c in clips) {
        expect(c.filterType, equals(0));
        expect(c.filterIntensity, equals(1.0));
      }

      // Redo applies the batch again.
      history.redo(controller.project);
      for (final c in clips) {
        expect(c.filterType, equals(15));
      }
    });

    test('filter reset through setClipFilter is undoable', () {
      // PLAN 1.1/B12: the inspector Reset button now routes through the
      // undoable command path instead of a direct mutation.
      controller.importMedia('/fake/video.mp4');
      final clip = controller.project.allClips.first;

      controller.setClipFilter(clip.id, 5, 0.5);
      expect(clip.filterType, equals(5));

      controller.setClipFilter(clip.id, 0, 1.0); // "Reset"
      expect(clip.filterType, equals(0));

      controller.undo();
      expect(clip.filterType, equals(5));
      expect(clip.filterIntensity, equals(0.5));
    });

    test('Track.kMinClipDurationMs is shared by trim paths', () {
      expect(Track.kMinClipDurationMs, equals(100));
    });
  });

  // ========== v1.1.0 regression tests (PLAN_1.1.0 Track 3) ==========

  group('PLAN 3 Track 3 regression', () {
    late EditorController controller;

    setUp(() => controller = EditorController());
    tearDown(() => controller.dispose());

    test('Clip JSON round-trips keyframes / pip / speed curve', () {
      final clip = Clip(
        id: 'c1',
        sourceFilePath: '/fake/v.mp4',
        displayName: 'v.mp4',
        timelineStartMs: 0,
        durationMs: 5000,
        keyframes: const [
          KeyframeData(timeMs: 0, value: 0, property: 0),
          KeyframeData(
              timeMs: 1000,
              value: 1,
              property: 0,
              interpolation: 2,
              cp1x: 1,
              cp1y: 0,
              cp2x: 0,
              cp2y: 1),
        ],
        speedCurve: const [SpeedRampPoint(0.0, 1.0), SpeedRampPoint(1.0, 4.0)],
        pipX: 0.25,
        pipY: 0.25,
        pipW: 0.5,
        pipH: 0.5,
      );
      final restored = Clip.fromJson(clip.toJson());
      expect(restored.keyframes.length, equals(2));
      expect(restored.keyframes[1].interpolation, equals(2));
      expect(restored.keyframes[1].cp2y, equals(1.0));
      expect(restored.speedCurve.length, equals(2));
      expect(restored.speedCurve[1].speed, equals(4.0));
      expect(restored.pipW, equals(0.5));
      expect(restored.pipH, equals(0.5));
      expect(restored.pipX, equals(0.25));
    });

    test('legacy Clip JSON without Track-3 fields loads with safe defaults', () {
      final restored = Clip.fromJson(const {
        'id': 'c2',
        'sourceFilePath': '/fake/v.mp4',
        'displayName': 'v.mp4',
        'timelineStartMs': 0,
        'durationMs': 1000,
      });
      expect(restored.keyframes, isEmpty);
      expect(restored.speedCurve, isEmpty);
      expect(restored.pipW, equals(1.0));
      expect(restored.pipH, equals(1.0));
      expect(restored.pipRotation, equals(0.0));
    });

    test('ChangeSpeedCurveCommand applies and undoes', () {
      controller.importMedia('/fake/v.mp4');
      final clip = controller.project.allClips.first;
      final curve = const [SpeedRampPoint(0.0, 0.5), SpeedRampPoint(1.0, 2.0)];
      controller.setClipSpeedCurve(clip.id, curve);
      expect(clip.speedCurve.length, equals(2));
      expect(clip.speedCurve.last.speed, equals(2.0));

      controller.undo();
      expect(clip.speedCurve, isEmpty);
      controller.redo();
      expect(clip.speedCurve.length, equals(2));
    });

    test('ChangePipCommand applies, undoes and coalesces per gesture', () {
      controller.importMedia('/fake/v.mp4');
      final clip = controller.project.allClips.first;

      controller.beginPropertyGesture();
      controller.setClipPip(clip.id, w: 0.5, h: 0.5);
      controller.setClipPip(clip.id, w: 0.4, h: 0.4); // same gesture → coalesce
      expect(clip.pipW, equals(0.4));
      // Stack: [AddClip, Pip] — the two setClipPip calls coalesced into ONE.
      expect(controller.commandHistory.undoCount, equals(2));

      controller.undo();
      expect(clip.pipW, equals(1.0)); // back to pre-gesture value
      expect(clip.pipH, equals(1.0));
    });

    test('SpeedCurvePreset.evaluateSpeedAt produces valid curve points', () {
      // PLAN 3.11: presets must stay within the engine's 0.25-4.0 clamp range.
      for (final preset in SpeedCurvePreset.values) {
        if (preset == SpeedCurvePreset.custom) continue;
        for (var i = 0; i <= 8; i++) {
          final s = preset.evaluateSpeedAt(i / 8);
          expect(s, greaterThanOrEqualTo(0.1));
          expect(s, lessThanOrEqualTo(4.0));
        }
      }
    });

    // ===== v1.1.0 (PLAN_REVIEW A.1): model invariant guards =====

    test('Clip.splitAt partitions the source window exactly under speed 2x', () {
      // PLAN_REVIEW A.1 invariant: left.sourceOut - left.sourceIn equals
      // right.sourceIn - parent.sourceIn for ANY speed — two halves must
      // tile the parent source span without overlap or gap.
      final clip = Clip(
        id: 'c',
        sourceFilePath: '/fake/v.mp4',
        displayName: 'v',
        timelineStartMs: 1000,
        durationMs: 1500,
        sourceInMs: 200,
        sourceOutMs: 200 + 1500 * 2, // speed 2x covers 3000ms of source
        speed: 2.0,
      );
      final parts = clip.splitAt(1000 + 500)!; // split at timeline 1500
      final left = parts[0];
      final right = parts[1];
      expect(left.durationMs, equals(500));
      expect(right.durationMs, equals(1000));
      // Exact tiling: left covers [200, 1200) and right starts at 1200.
      expect(left.sourceInMs, equals(200));
      expect(left.sourceOutMs, equals(200 + 500 * 2));
      expect(right.sourceInMs, equals(200 + 500 * 2));
      expect(right.sourceOutMs, equals(left.sourceOutMs + 1000 * 2));
      // Timeline positions tile too.
      expect(right.timelineStartMs, equals(1500));
      expect(right.timelineEndMs, equals(2500));
      expect(left.timelineEndMs, equals(right.timelineStartMs));
    });

    test('splitAt returns null at boundary (no zero-duration half)', () {
      final clip = Clip(
        id: 'c',
        sourceFilePath: '/fake/v.mp4',
        displayName: 'v',
        timelineStartMs: 0,
        durationMs: 200,
        speed: 1.0,
      );
      expect(clip.splitAt(0), isNull);
      expect(clip.splitAt(200), isNull);
      expect(clip.splitAt(100), isNotNull);
      final parts = clip.splitAt(100)!;
      expect(parts[0].durationMs, greaterThanOrEqualTo(Track.kMinClipDurationMs));
      expect(parts[1].durationMs, greaterThanOrEqualTo(Track.kMinClipDurationMs));
    });

    test('Project serialization round-trips every field', () {
      final project = Project(
        name: 'Ser Test',
        outputWidth: 1280,
        outputHeight: 720,
        outputFps: 30,
        outputFormat: 'mp4',
      );
      final track = project.tracks.first;
      track.addClipAt(
          Clip(
            id: 'ser1',
            sourceFilePath: '/fake/a.mp4',
            displayName: 'a.mp4',
            timelineStartMs: 0,
            durationMs: 2000,
            speed: 1.5,
            volume: 0.7,
            opacity: 0.8,
            pipW: 0.5,
            pipH: 0.5,
            keyframes: const [
              KeyframeData(timeMs: 0, value: 0.5, property: 0)
            ],
          ),
          0);
      final restored = Project.fromJsonString(project.toJsonString());
      expect(restored.name, equals('Ser Test'));
      expect(restored.outputWidth, equals(1280));
      expect(restored.outputFps, equals(30));
      final clip = restored.allClips.first;
      expect(clip.speed, equals(1.5));
      expect(clip.volume, equals(0.7));
      expect(clip.opacity, equals(0.8));
      expect(clip.pipW, equals(0.5));
      expect(clip.keyframes.length, equals(1));
    });

    test('CommandHistory coalesces per gesture and survives undo/redo', () {
      final project = Project(name: 'Coalesce');
      final history = CommandHistory();
      final track = project.tracks.first;
      track.addClipAt(
          Clip(
            id: 'cc1',
            sourceFilePath: '/fake/a.mp4',
            displayName: 'a',
            timelineStartMs: 0,
            durationMs: 1000,
          ),
          0);
      final clip = track.clips.first;

      // Gesture 1: two slider ticks coalesce into ONE undo entry.
      history.execute(ChangeClipPropertyCommand(clipId: clip.id, property: 'opacity', newValue: 0.4, gestureId: 1), project);
      history.execute(ChangeClipPropertyCommand(clipId: clip.id, property: 'opacity', newValue: 0.3, gestureId: 1), project);
      expect(history.undoCount, equals(1));

      // Undo → back to 1.0.
      history.undo(project);
      expect(clip.opacity, equals(1.0));
      expect(history.canRedo, isTrue);

      // Redo → 0.3.
      history.redo(project);
      expect(clip.opacity, equals(0.3));

      // Gesture 2 (new gestureId) must NOT coalesce with gesture 1's entry.
      history.execute(ChangeClipPropertyCommand(clipId: clip.id, property: 'opacity', newValue: 0.5, gestureId: 2), project);
      expect(history.undoCount, equals(2));
      history.undo(project);
      expect(clip.opacity, equals(0.3)); // gesture 2 undone, gesture 1 intact
    });

    // ===== v1.1.0 (PLAN_REVIEW A.3): controller coverage for the 70% gate =====

    test('newProject resets playback state and default pip', () {
      controller.importMedia('/fake/v.mp4');
      final clip = controller.project.allClips.first;
      controller.setClipPip(clip.id, w: 0.5, h: 0.5);
      controller.setFilter(7, 0.5);
      expect(clip.pipW, equals(0.5));

      controller.newProject();
      expect(controller.project.allClips, isEmpty);
      expect(controller.positionMs, equals(0));
      expect(controller.isPlaying, isFalse);
      expect(controller.activeFilterType, equals(0));
      // A fresh project's first clip uses the default full-frame pip.
      controller.importMedia('/fake/b.mp4');
      final fresh = controller.project.allClips.first;
      expect(fresh.pipW, equals(1.0));
      expect(fresh.pipH, equals(1.0));
    });

    test('change-clip-text command is undoable and preserves all fields', () {
      controller.importMedia('/fake/v.mp4');
      final clip = controller.project.allClips.first;
      // Turn it into a text clip.
      clip.type = ClipType.text;
      controller.setClipText(clip.id,
          content: 'Hi', fontSize: 40, gradient: true, bold: true);
      expect(clip.textContent, equals('Hi'));
      expect(clip.textGradient, isTrue);
      expect(clip.textBold, isTrue);
      controller.undo();
      expect(clip.textContent, equals(''));
      expect(clip.textGradient, isFalse);
      expect(clip.textBold, isFalse);
      controller.redo();
      expect(clip.textContent, equals('Hi'));
      expect(clip.textGradient, isTrue);
    });

    test('playback rate clamps to engine range 0.25-4x', () {
      controller.engineService.setPlaybackRate(10.0);
      expect(controller.engineService.playbackRate, equals(4.0));
      controller.engineService.setPlaybackRate(0.01);
      expect(controller.engineService.playbackRate, equals(0.25));
      controller.engineService.setPlaybackRate(2.0);
      expect(controller.engineService.playbackRate, equals(2.0));
    });

    test('audio mixer master volume clamps through the controller', () {
      controller.setVolume(5.0);
      expect(controller.volume, equals(2.0));
      controller.setVolume(-3.0);
      expect(controller.volume, equals(0.0));
      controller.setVolume(1.5);
      expect(controller.volume, equals(1.5));
    });
  });
}
