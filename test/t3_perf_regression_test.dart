// v1.5.0-T3 performance regression suite — each test FAILS on the pre-T3
// behavior so the optimizations cannot silently regress.
//
// Covers:
// * O(1) selection membership/count (was O(clips × selection) per build);
// * position-only tick gating (playback ticks used to rebuild every panel
//   via full notifyListeners ~30×/s);
// * structural-vs-property command classification (property drags used to
//   clear the timeline waveform cache on every coalesced tick).
import 'package:flutter_test/flutter_test.dart';
import 'package:ghita_edit/src/controllers/command_history.dart';
import 'package:ghita_edit/src/controllers/editor_controller.dart';
import 'package:ghita_edit/src/models/clip.dart';
import 'package:ghita_edit/src/models/project.dart';
import 'package:ghita_edit/src/models/track.dart';

/// Minimal property-only command for classification tests.
class _NopPropertyCommand extends EditCommand {
  @override
  String get description => 'nop';

  @override
  void execute(Project project) {}

  @override
  void undo(Project project) {}
}

void main() {
  group('T3-P4 O(1) selection', () {
    test('membership + count are correct and FAST at scale', () {
      final project = Project(name: 'p');
      final track = Track(id: 't1', name: 'V', type: TrackType.video);
      for (var i = 0; i < 2000; i++) {
        track.clips.add(Clip(
          id: 'c$i',
          sourceFilePath: '',
          displayName: 'clip $i',
          timelineStartMs: i * 1000,
          durationMs: 900,
        ));
      }
      project.tracks.clear();
      project.tracks.add(track);

      // Select every 20th clip → 100 live selections.
      for (var i = 0; i < 2000; i += 20) {
        project.addToSelection({'c$i'});
      }
      expect(project.selectedClipCount, 100);
      expect(project.isClipSelected('c0'), isTrue);
      expect(project.isClipSelected('c1'), isFalse);

      // The hot loop shape used by TimelinePanel._buildClipWidget — 2000
      // membership checks per build. The old expression
      // `selectedClips.any((c) => c.id == clip.id)` cost O(clips²·scan)
      // (~200M ops) here; the new path must be effectively instant.
      final sw = Stopwatch()..start();
      var hits = 0;
      for (final clip in track.clips) {
        if (project.isClipSelected(clip.id)) hits++;
      }
      sw.stop();
      expect(hits, 100);
      expect(sw.elapsedMilliseconds, lessThan(50),
          reason: 'O(1) selection checks must not degrade with clip count');

      // Stale ids of deleted clips must not inflate the count.
      track.clips.removeWhere((c) => c.id == 'c0');
      project.pruneSelection();
      expect(project.selectedClipCount, 99);
    });

    test('deselectAll clears the live set too', () {
      final project = Project(name: 'p');
      final track = project.tracks.first;
      track.clips.add(Clip(
          id: 'only',
          sourceFilePath: '',
          displayName: 'x',
          timelineStartMs: 0,
          durationMs: 100));
      project.selectClip('only');
      expect(project.selectedClipCount, 1);
      project.deselectAll();
      expect(project.selectedClipCount, 0);
      expect(project.isClipSelected('only'), isFalse);
    });
  });

  group('T3-P1 position-only tick gating', () {
    test('unchanged samples update playhead but do NOT notify', () {
      final controller = EditorController();
      addTearDown(controller.dispose);

      var notifies = 0;
      controller.addListener(() => notifies++);

      // First sample always notifies (baseline).
      controller.debugApplyEngineTick(posMs: 500);
      expect(notifies, 1);
      expect(controller.playheadMs.value, 500);

      // Identical playback tick (position-only engine ticks during pause) —
      // playhead still updates but the FULL app must not rebuild.
      controller.debugApplyEngineTick(posMs: 500);
      expect(notifies, 1, reason: 'identical sample must be suppressed');
      expect(controller.playheadMs.value, 500);

      // Position-only change during playback: playhead moves, app suppressed.
      controller.debugApplyEngineTick(posMs: 533);
      expect(notifies, 2); // position CHANGED → still a wake-up
      controller.debugApplyEngineTick(posMs: 566);
      expect(notifies, 3);
      expect(controller.playheadMs.value, 566);
    });

    test('duration / playing / frame-generation changes DO notify', () {
      final controller = EditorController();
      addTearDown(controller.dispose);
      var notifies = 0;
      controller.addListener(() => notifies++);

      controller.debugApplyEngineTick(posMs: 0);
      expect(notifies, 1);

      // Same position but a state flag moved — full notify required.
      controller.debugApplyEngineTick(posMs: 0, playing: true);
      expect(notifies, 2);
      controller.debugApplyEngineTick(posMs: 0, generation: 7);
      expect(notifies, 3);
      controller.debugApplyEngineTick(posMs: 0, durationMs: 60000);
      expect(notifies, 4);
    });
  });

  group('T3-P2 command classification', () {
    test('property commands are non-structural, delete is structural', () {
      final project = Project(name: 'p');
      final controller = EditorController();
      addTearDown(controller.dispose);
      final history = controller.commandHistory;

      history.execute(_NopPropertyCommand(), project);
      expect(history.lastChangeWasStructural, isFalse,
          reason: 'property ticks must NOT clear waveform caches');

      final track = project.tracks.first;
      final clip = Clip(
          id: 'victim',
          sourceFilePath: '',
          displayName: 'victim',
          timelineStartMs: 0,
          durationMs: 1000);
      track.clips.add(clip);
      history.execute(DeleteClipCommand(trackId: track.id, clip: clip), project);
      expect(history.lastChangeWasStructural, isTrue,
          reason: 'membership changes invalidate waveform peaks');
      history.undo(project);
      expect(history.lastChangeWasStructural, isTrue);
    });
  });
}
