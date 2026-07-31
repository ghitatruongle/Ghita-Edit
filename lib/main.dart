import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'src/ui/theme/app_theme.dart';
import 'src/ui/views/editor_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GhitaEditApp());
}

class GhitaEditApp extends StatefulWidget {
  const GhitaEditApp({super.key});

  @override
  State<GhitaEditApp> createState() => _GhitaEditAppState();
}

class _GhitaEditAppState extends State<GhitaEditApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getString('theme_mode') ?? 'dark';
    setState(() {
      _themeMode = savedMode == 'light' ? ThemeMode.light : ThemeMode.dark;
    });
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    final modeName = mode == ThemeMode.light ? 'light' : 'dark';
    await prefs.setString('theme_mode', modeName);
    setState(() {
      _themeMode = mode;
    });
  }

  ThemeMode getThemeMode() => _themeMode;

  Future<void> toggleThemeMode() async {
    final newMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    await _setThemeMode(newMode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ghita Edit - High-Performance Multimedia Editor',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _themeMode,
      home: EditorViewWrapper(
        themeMode: _themeMode,
        onThemeModeChanged: _setThemeMode,
      ),
    );
  }
}

class EditorViewWrapper extends StatefulWidget {
  final ThemeMode themeMode;
  final Future<void> Function(ThemeMode) onThemeModeChanged;

  const EditorViewWrapper({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  @override
  State<EditorViewWrapper> createState() => _EditorViewWrapperState();
}

class _EditorViewWrapperState extends State<EditorViewWrapper> {
  @override
  Widget build(BuildContext context) {
    return EditorView(
      themeMode: widget.themeMode,
      onThemeModeChanged: widget.onThemeModeChanged,
    );
  }
}
