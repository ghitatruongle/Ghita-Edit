import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghita_edit/src/controllers/editor_controller.dart';
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
      expect(titleMedium.fontSize, equals(16));

      final bodySmall = theme.textTheme.bodySmall!;
      expect(bodySmall.color, equals(AppTheme.textMuted));
      expect(bodySmall.fontSize, equals(11));

      final labelSmall = theme.textTheme.labelSmall!;
      expect(labelSmall.fontSize, equals(10));
    });

    test('appVersion string matches pubspec convention', () {
      expect(AppTheme.appVersion, startsWith('v'));
      expect(AppTheme.appVersion, endsWith('+2'));
    });
  });

  group('EditorView rendering', () {
    testWidgets('renders full editor layout after init attempt', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: EditorView(),
        ),
      );

      // Allow init() future to complete
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.text('GHITA EDIT'), findsOneWidget);
      expect(find.text('C++ ENGINE v0.1.0+2'), findsOneWidget);
      expect(find.text('File'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Track'), findsOneWidget);
      expect(find.text('Effects'), findsOneWidget);
      expect(find.text('Help'), findsOneWidget);
      expect(find.text('Export'), findsOneWidget);

      expect(find.byType(MediaBin), findsOneWidget);
      expect(find.byType(PreviewPlayer), findsOneWidget);
      expect(find.byType(InspectorPanel), findsOneWidget);
      expect(find.byType(TimelinePanel), findsOneWidget);

      expect(tester.takeException(), isEmpty);
    });

    testWidgets('play/pause controls exist in PreviewPlayer', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: EditorView(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.play_circle_filled), findsWidgets);
      expect(find.byIcon(Icons.replay_10), findsWidgets);
      expect(find.byIcon(Icons.forward_10), findsWidgets);
    });

    testWidgets('MediaBin has Import File button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: EditorView(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Import File'), findsWidgets);
    });

    testWidgets('Export dialog appears when pressed while engine ready', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: EditorView(),
        ),
      );
      await tester.pumpAndSettle();

      final exportButton = find.text('Export');
      if (exportButton.evaluate().isNotEmpty) {
        await tester.tap(exportButton);
        await tester.pumpAndSettle();
        expect(find.text('Export Media Project'), findsOneWidget);
      }
    });

    testWidgets('menu items render without error', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: EditorView(),
        ),
      );
      await tester.pumpAndSettle();

      for (final label in ['File', 'Edit', 'Track', 'Effects', 'Help']) {
        expect(find.text(label), findsOneWidget, reason: 'Menu item "$label" missing');
      }

      await tester.tap(find.text('File'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isEmpty);
    });
  });

  group('EditorView animation smoke test', () {
    testWidgets('animates multiple frames without exception', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: EditorView(),
        ),
      );

      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(tester.takeException(), isEmpty);
      expect(find.text('GHITA EDIT'), findsOneWidget);
    });
  });
}
