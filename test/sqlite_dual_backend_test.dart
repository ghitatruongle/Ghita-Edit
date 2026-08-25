// v1.5.0-T6 (P2): SQLite dual-backend coverage — the ghita_project_db_*
// family previously had ZERO Dart-side tests (only Rust-internal ones), so
// binding drift would reach production unnoticed.
//
// Skips cleanly when the engine DLL isn't available (ubuntu CI); runs for
// real on the Windows real-engine CI job from T2-P3.
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghita_edit/src/ffi/native_bindings.dart';

void main() {
  late Directory tmp;
  GhitaNativeBindings? bindings;

  setUpAll(() {
    try {
      final b = GhitaNativeBindings.instance;
      // The sqlite feature must also be compiled into the DLL.
      if (b.projectDbSave != null &&
          b.projectDbLoad != null &&
          b.projectDbList != null &&
          b.projectDbDelete != null) {
        bindings = b;
      }
    } catch (_) {
      bindings = null;
    }
  });

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('t6_sqlite');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Pointer<Utf8> cstr(String s) => s.toNativeUtf8();

  test('project db save → list → load → delete round-trip', () {
    final b = bindings;
    if (b == null) {
      markTestSkipped('engine DLL / sqlite feature not available');
      return;
    }
    final dbPtr = cstr('${tmp.path}/projects.db');
    final name1 = cstr('Alpha');
    final name2 = cstr('Beta');
    const p1 = '{"name":"Alpha","tracks":[]}';
    const p2 = '{"name":"Beta","tracks":[]}';
    final j1 = cstr(p1);
    final j2 = cstr(p2);

    try {
      expect(b.projectDbSave!(dbPtr, name1, j1), 1, reason: 'save Alpha');
      expect(b.projectDbSave!(dbPtr, name2, j2), 1, reason: 'save Beta');

      // List returns a JSON array containing both names.
      final listPtr = b.projectDbList!(dbPtr);
      expect(listPtr, isNot(nullptr));
      final listJson = listPtr.toDartString();
      expect(listJson, contains('Alpha'));
      expect(listJson, contains('Beta'));

      // Load returns byte-identical JSON per project.
      final load1 = b.projectDbLoad!(dbPtr, name1);
      expect(load1, isNot(nullptr));
      expect(load1.toDartString(), p1);

      // Delete removes only the targeted project.
      expect(b.projectDbDelete!(dbPtr, name1), greaterThanOrEqualTo(0));
      final gone = b.projectDbLoad!(dbPtr, name1);
      expect(gone == nullptr, isTrue, reason: 'deleted project must not load');
      final stillThere = b.projectDbLoad!(dbPtr, name2);
      expect(stillThere, isNot(nullptr));
      expect(stillThere.toDartString(), p2);

      calloc.free(dbPtr);
      calloc.free(name1);
      calloc.free(name2);
      calloc.free(j1);
      calloc.free(j2);
    } catch (_) {
      calloc.free(dbPtr);
      calloc.free(name1);
      calloc.free(name2);
      calloc.free(j1);
      calloc.free(j2);
      rethrow;
    }
  });
}
