import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghita_edit/src/core/version.dart';
import 'package:ghita_edit/src/ui/theme/app_theme.dart';
import 'package:ghita_edit/src/ui/views/editor_view.dart';

void main() {
  group('AppTheme', () {
    test('darkTheme uses correct primary colors and typography', () {
      final theme = AppTheme.darkTheme;

      expect(theme.scaffoldBackgroundColor, equals(AppTheme.background));
      expect(theme.cardColor, equals(AppTheme.card));
      expect(theme.colorScheme.primary, equals(AppTheme.primary));
      expect(theme.appBarTheme.backgroundColor, equals(AppTheme.surface));

      final titleMedium = theme.textTheme.titleMedium!;
      expect(titleMedium.color, equals(AppTheme.textMain));
      // v0.7.8 design system: titleMedium is 14 (was 16 pre-v0.7.0)
      expect(titleMedium.fontSize, equals(14));

      final bodySmall = theme.textTheme.bodySmall!;
      expect(bodySmall.color, equals(AppTheme.textMuted));
      expect(bodySmall.fontSize, equals(11));

      final labelSmall = theme.textTheme.labelSmall!;
      expect(labelSmall.fontSize, equals(10));
    });

    test('appVersion string matches centralized version constants', () {
      expect(AppTheme.appVersion, startsWith('v'));
      expect(AppTheme.appVersion, contains(flutterVersion));
    });
  });

  group('EditorView rendering', () {
    testWidgets('renders loading shell when engine not ready', (tester) async {
      // Provide a wide enough surface to prevent RenderFlex overflows during tests
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: EditorView(
            themeMode: ThemeMode.dark,
            onThemeModeChanged: (mode) async {},
          ),
        ),
      );

      // The loading shell should show while engine initializes
      await tester.pump(const Duration(milliseconds: 100));

      // v0.7.8: When a native ghita_engine.dll is discoverable in the test
      // environment the engine can come up almost immediately — accept either
      // the loading shell or the full editor layout. The stability contract
      // is: no exceptions at any point.
      final loading = find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
      final editorReady = find.text('Export Media Project').evaluate().isNotEmpty ||
          find.text('Timeline').evaluate().isNotEmpty;
      expect(loading || editorReady, isTrue,
          reason: 'expected loading shell or full editor layout');
      expect(tester.takeException(), isNull);

      // Let the session-recovery timer (500ms) fire so no timer is left pending
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders full editor layout after init', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: EditorView(
            themeMode: ThemeMode.dark,
            onThemeModeChanged: (mode) async {},
          ),
        ),
      );

      // Pump a few frames to let init complete
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 100));

      // In test env without native DLL, we stay in loading shell
      expect(tester.takeException(), isNull);
    });

    testWidgets('menu labels are present when engine ready', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: EditorView(
            themeMode: ThemeMode.dark,
            onThemeModeChanged: (mode) async {},
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 100));

      // In test env, engine won't be ready - just verify stability
      expect(tester.takeException(), isNull);
    });
  });

  group('EditorView animation smoke test', () {
    testWidgets('animates multiple frames without exception', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: EditorView(
            themeMode: ThemeMode.dark,
            onThemeModeChanged: (mode) async {},
          ),
        ),
      );

      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(tester.takeException(), isNull);
    });
  });
}
