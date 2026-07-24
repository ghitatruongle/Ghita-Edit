import 'package:flutter/material.dart';
import 'src/ui/theme/app_theme.dart';
import 'src/ui/views/editor_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GhitaEditApp());
}

class GhitaEditApp extends StatelessWidget {
  const GhitaEditApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ghita Edit - High-Performance Multimedia Editor',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const EditorView(),
    );
  }
}
