// T2.P2 (v1.5.5-beta2) stress regression — the milestone's undo/SQLite
// deliverables as permanent tests:
//   1. undo 500: 500 distinct-gesture edits at the production history depth
//      (maxHistory=500) — full undo returns the exact initial clip.
//   2. Coalescing: 500 ticks inside ONE gesture collapse into a single undo
//      entry, and undo restores the PRE-GESTURE value.
//   3. SQLite save→load round-trip ×50 with a growing payload — every load
//      byte-identical (catches rowid/blob drift a single round-trip misses).
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghita_edit/src/controllers/command_history.dart';
import 'package:ghita_edit/src/ffi/native_bindings.dart';
import 'package:ghita_edit/src/models/clip.dart';
import 'package:ghita_edit/src/models/project.dart';

Clip _videoClip(String id) => Clip(
      id: id,
      sourceFilePath: 'stress.mp4',
      displayName: 'C$id',
      timelineStartMs: 0,
      durationMs: 4000,
    );

void main() {
  group('T2.P2 undo stress (production depth 500)', () {
    test('500 distinct gestures — full undo restores the exact initial clip', () {
      final project = Project(name: 'stress');
      final track = project.tracks.first;
      final original = _videoClip('c1');
      track.clips.add(original);

      final history = CommandHistory(maxHistory: 500, snapshotInterval: 0);
      var current = original;
      for (var i = 0; i < 500; i++) {
        final after = current.copyWith(volume: (i + 1) / 500.0);
        final cmd = ClipStateCommand(
          clipId: 'c1',
          field: 'volume',
          afterValue: after,
          gestureId: i, // every tick its own gesture → 500 entries
        )..preloadBefore(current);
        history.execute(cmd, project);
        current = after;
      }
      expect(history.undoCount, 500, reason: 'production depth keeps all 500');
      expect(track.clips.single.volume, closeTo(1.0, 1e-6),
          reason: 'sanity: the 500th edit is the live state');

      var undos = 0;
      while (history.canUndo) {
        expect(history.undo(project), isTrue);
        undos++;
      }
      expect(undos, 500);
      expect(track.clips.single.volume, 1.0,
          reason: 'full undo returns the exact initial clip');
      expect(history.canRedo, isTrue);

      var redos = 0;
      while (history.canRedo) {
        expect(history.redo(project), isTrue);
        redos++;
      }
      expect(redos, 500);
      expect(track.clips.single.volume, closeTo(1.0, 1e-6),
          reason: 'redo replays the 500th state');
    });

    test('500 ticks in ONE gesture coalesce into a single undo entry', () {
      final project = Project(name: 'coalesce');
      final track = project.tracks.first;
      final original = _videoClip('c1');
      track.clips.add(original);

      final history = CommandHistory(maxHistory: 500, snapshotInterval: 0);
      var current = original;
      for (var i = 0; i < 500; i++) {
        final after = current.copyWith(volume: (i + 1) / 500.0);
        final cmd = ClipStateCommand(
          clipId: 'c1',
          field: 'volume',
          afterValue: after,
          gestureId: 7, // one drag gesture for the whole sweep
        )..preloadBefore(current);
        history.execute(cmd, project);
        current = after;
      }
      expect(history.undoCount, 1, reason: 'one gesture = one undo entry');
      expect(history.undo(project), isTrue);
      expect(track.clips.single.volume, 1.0,
          reason: 'undo restores the PRE-GESTURE value, not the last tick');
    });
  });

  group('T2.P2 SQLite round-trip ×50', () {
    late Directory tmp;
    GhitaNativeBindings? b;

    setUpAll(() {
      try {
        final bindings = GhitaNativeBindings.instance;
        if (bindings.projectDbSave != null &&
            bindings.projectDbLoad != null &&
            bindings.projectDbList != null) {
          b = bindings;
        }
      } catch (_) {
        b = null;
      }
    });

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('t2_sqlite_loop');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('50 save→load cycles with growing payload stay byte-identical', () {
      final bindings = b;
      if (bindings == null) {
        markTestSkipped('engine DLL / sqlite feature not available');
        return;
      }
      final dbPath = '${tmp.path}/loop.db'.toNativeUtf8();
      final name = 'StressLoop'.toNativeUtf8();
      try {
        for (var i = 0; i < 50; i++) {
          final payload = jsonEncode({
            'name': 'StressLoop',
            'revision': i,
            'tracks': [
              for (var t = 0; t <= i % 4; t++)
                {'id': 't$t', 'name': 'T$t', 'type': 0, 'clips': <Map>[]},
            ],
            'padding': 'x' * (100 * (i + 1)), // payload grows to ~5 KB
          });
          final json = payload.toNativeUtf8();
          try {
            // 0/-1 family: 0 = success (mirrors ghita_project_db_save).
            expect(bindings.projectDbSave!(dbPath, name, json), 0,
                reason: 'cycle $i: save');
          } finally {
            calloc.free(json);
          }
          // The load/list results point into a Rust THREAD-LOCAL buffer that
          // is reused by the next call on the same thread (c_api T_JSON) —
          // copy with toDartString immediately and NEVER free (freeing a
          // Rust thread-local with the Dart allocator corrupts the heap).
          final loaded = bindings.projectDbLoad!(dbPath, name);
          expect(loaded, isNot(nullptr), reason: 'cycle $i: load after save');
          expect(loaded.toDartString(), payload,
              reason: 'cycle $i: byte-identical round-trip');
        }
        final list = bindings.projectDbList!(dbPath);
        expect(list, isNot(nullptr));
        expect(list.toDartString(), contains('StressLoop'));
      } finally {
        calloc.free(dbPath);
        calloc.free(name);
      }
    });
  });
}
