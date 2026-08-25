// v1.5.0-T1 regression suite — every hotfix in Track 1 gets a test that fails
// on the pre-fix behavior.
//
// Covers: copyWith color wipe, splitAt color inheritance, trimClipEnd minimum
// duration, delete→undo exact restoration, SRT millisecond/CRLF/overlay-track
// transcript import, project-switch state leaks.
import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:ghita_edit/src/controllers/command_history.dart';
import 'package:ghita_edit/src/controllers/editor_controller.dart';
import 'package:ghita_edit/src/models/clip.dart';
import 'package:ghita_edit/src/models/project.dart';
import 'package:ghita_edit/src/models/track.dart';

Clip _textClip({int start = 0, int duration = 1000}) {
  final c = Clip(
    id: Clip.nextId(),
    sourceFilePath: '',
    displayName: 'caption',
    timelineStartMs: start,
    durationMs: duration,
    type: ClipType.text,
    textContent: 'hello',
    textFontSize: 42,
  );
  c.textColor = const Color(0xFFFF0000);
  c.textStrokeColor = const Color(0xFF00FF00);
  c.textBackgroundColor = const Color(0xFF0000FF);
  return c;
}

void main() {
  group('T1-P3 copyWith text colors', () {
    test('omitted color parameters PRESERVE current colors', () {
      final clip = _textClip();
      // The old fallback to transparent wiped colors on EVERY copyWith.
      final edited = clip.copyWith(durationMs: 500);
      expect(edited.textColorValue, clip.textColorValue);
      expect(edited.textStrokeColorValue, clip.textStrokeColorValue);
      expect(edited.textBackgroundColorValue, clip.textBackgroundColorValue);
    });

    test('explicit recolor still works', () {
      final clip = _textClip();
      final recolored = clip.copyWith(textColor: const Color(0xFF123456));
      expect(recolored.textColorValue, 0xFF123456);
      // …and siblings stay intact.
      expect(recolored.textBackgroundColorValue, clip.textBackgroundColorValue);
    });

    test('splitAt halves inherit text colors', () {
      final clip = _textClip(start: 0, duration: 1000);
      final halves = clip.splitAt(400);
      expect(halves, isNotNull);
      expect(halves![0].textColorValue, clip.textColorValue);
      expect(halves[1].textColorValue, clip.textColorValue);
      expect(halves[0].textStrokeColorValue, clip.textStrokeColorValue);
      expect(halves[1].textBackgroundColorValue, clip.textBackgroundColorValue);
    });
  });

  group('T1-P3 trimClipEnd guard', () {
    test('rejects sub-minimum durations like trimClipStart does', () {
      final track = Track(id: 'tr', name: 'V', type: TrackType.video)
        ..clips.add(_textClip(start: 0, duration: 500));
      // 50ms would violate kMinClipDurationMs (100) — must be rejected.
      track.trimClipEnd(track.clips.first.id, 50);
      expect(track.clips.first.durationMs, 500);
      // A legal trim still applies.
      track.trimClipEnd(track.clips.first.id, 300);
      expect(track.clips.first.durationMs, 300);
      expect(track.clips.first.sourceOutMs,
          track.clips.first.sourceInMs + 300);
    });
  });

  group('T1-P3 delete undo', () {
    test('undo restores the exact pre-delete timeline', () {
      final project = Project(name: 'p');
      final track = project.tracks.first;
      final a = Clip(
          id: 'a',
          sourceFilePath: '',
          displayName: 'A',
          timelineStartMs: 0,
          durationMs: 1000);
      final b = Clip(
          id: 'b',
          sourceFilePath: '',
          displayName: 'B',
          timelineStartMs: 1000,
          durationMs: 1000);
      final c = Clip(
          id: 'c',
          sourceFilePath: '',
          displayName: 'C',
          timelineStartMs: 2000,
          durationMs: 1000);
      track.clips.addAll([a, b, c]);

      final cmd = DeleteClipCommand(trackId: track.id, clip: b);
      cmd.execute(project);
      expect(track.clips.map((e) => e.id), ['a', 'c']);

      cmd.undo(project);
      // Old undo went through addClipAt()'s overlap resolution which could
      // shift unrelated clips — restore must be byte-for-byte.
      expect(track.clips.map((e) => e.id).toList(), ['a', 'b', 'c']);
      expect(track.clips.map((e) => e.timelineStartMs).toList(),
          [0, 1000, 2000]);
    });
  });

  group('T1-P3 transcript import', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('t1_srt'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('CRLF + comma milliseconds land fully on the overlay track', () {
      final srt =
          '1\r\n00:00:00,500 --> 00:00:02,000\r\nHello world\r\n\r\n'
          '2\r\n00:00:02,000 --> 00:00:04,250\r\nSecond line\r\n';
      final file = File('${tmp.path}/crlf.srt')..writeAsStringSync(srt);

      final controller = EditorController();
      final n = controller.importTranscriptFromFile(file.path);
      expect(n, 2, reason: 'CRLF blocks must all parse');

      final overlayIdx = controller.project.tracks
          .indexWhere((t) => t.type == TrackType.overlay);
      expect(overlayIdx, greaterThanOrEqualTo(0),
          reason: 'captions belong on an overlay track');
      final clips = controller.project.tracks[overlayIdx].clips;
      expect(clips.length, 2, reason: 'no double-add via direct engine call');
      // Comma milliseconds were previously truncated to whole seconds.
      expect(clips[0].timelineStartMs, 500);
      expect(clips[0].durationMs, 1500);
      expect(clips[1].durationMs, 2250);
    });

    test('explicit trackIndex still wins over the overlay default', () {
      final file = File('${tmp.path}/plain.srt')
        ..writeAsStringSync('1\n00:00:01,000 --> 00:00:02,000\nX\n');
      final controller = EditorController();
      controller.importTranscriptFromFile(file.path, trackIndex: 2);
      final audioTrack =
          controller.project.tracks.where((t) => t.type == TrackType.audio).first;
      expect(audioTrack.clips.length, 1);
    });
  });

  group('T1-P3 project switch state', () {
    test('newProject clears bookmarks, guides and canvas background', () {
      final controller = EditorController();
      controller.bookmarks.add(BookmarkModel(
          id: 1, timeMs: 1234, color: 0xFFFF0000, note: 'stale'));
      controller.guideMs.add(4321);
      controller.setCanvasBackground(1, 0xFF112233, color2: 0xFF445566);

      controller.newProject();

      expect(controller.bookmarks, isEmpty);
      expect(controller.guideMs, isEmpty);
      expect(controller.canvasBgKind, 0);
      expect(controller.canvasBgColor, 0xFF000000);
      expect(controller.canvasBgColor2, 0xFF000000);
    });
  });
}
