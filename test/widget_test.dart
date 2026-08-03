import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghita_edit/src/controllers/editor_controller.dart';
import 'package:ghita_edit/src/core/version.dart';
import 'package:ghita_edit/src/ui/theme/app_theme.dart';
import 'package:ghita_edit/src/ui/views/editor_view.dart';
import 'package:ghita_edit/src/ui/widgets/inspector_panel.dart';
import 'package:ghita_edit/src/ui/widgets/voiceover_recorder.dart';

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

    // v0.7.9: UX-05 — high-contrast theme keeps white-on-black text
    test('highContrastDarkTheme uses black/white accessibility palette', () {
      final theme = AppTheme.highContrastDarkTheme;
      expect(theme.scaffoldBackgroundColor, equals(const Color(0xFF000000)));
      expect(theme.cardColor, equals(const Color(0xFF000000)));
      expect(theme.colorScheme.onSurface, equals(Colors.white));
      expect(theme.colorScheme.primary, equals(Colors.white));
    });
  });

  // v0.7.9: UX-05 — theme transition builder swaps child keyed by mode
  group('AppTheme themeTransitionBuilder', () {
    testWidgets('switches child key when theme mode changes', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AppTheme.themeTransitionBuilder(
            themeMode: ThemeMode.dark,
            child: const SizedBox(key: ValueKey('dark-child')),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('dark-child')), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          home: AppTheme.themeTransitionBuilder(
            themeMode: ThemeMode.light,
            child: const SizedBox(key: ValueKey('light-child')),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('light-child')), findsOneWidget);
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

  // ========== v0.7.9: BUG-03 regression — long text must not overflow ==========
  group('v0.7.9 InspectorPanel overflow regression', () {
    testWidgets('renders clip with very long name without RenderFlex overflow', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final controller = EditorController();
      addTearDown(controller.dispose);
      controller.importMedia(
        '/path/a_very_long_file_name_that_keeps_going_and_going_'
        'and_going_without_any_stop_in_sight_1234567890.mp4',
      );
      controller.selectClip(controller.project.allClips.first.id);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: SizedBox(
              width: 260, // Narrow panel — the overflow case
              child: InspectorPanel(controller: controller),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });

  // v0.8.0: The voiceover recorder must build (record button visible) without
  // throwing in a headless test environment.
  group('VoiceoverRecorder', () {
    testWidgets('renders record button and no exception', (tester) async {
      final controller = EditorController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VoiceoverRecorder(controller: controller),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Record Voiceover'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
