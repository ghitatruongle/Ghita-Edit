import 'package:flutter/material.dart';
import '../../controllers/editor_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/preview_player.dart';
import '../widgets/media_bin.dart';
import '../widgets/inspector_panel.dart';
import '../widgets/timeline_panel.dart';
import '../widgets/export_dialog.dart';

class EditorView extends StatefulWidget {
  const EditorView({super.key});

  @override
  State<EditorView> createState() => _EditorViewState();
}

class _EditorViewState extends State<EditorView> {
  final EditorController _controller = EditorController();

  @override
  void initState() {
    super.initState();
    _controller.init().catchError((Object error, StackTrace stack) {
      debugPrint('GhitaEngine init failed: $error\n$stack');
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        if (!_controller.isEngineReady) {
          return _loadingShell();
        }

        return Scaffold(
          backgroundColor: AppTheme.background,
          body: Column(
            children: [
              _buildTopHeader(context),

              Expanded(
                flex: 6,
                child: Row(
                  children: [
                    SizedBox(
                      width: 280,
                      child: MediaBin(controller: _controller),
                    ),
                    const VerticalDivider(width: 1, color: AppTheme.divider),

                    Expanded(
                      flex: 5,
                      child: PreviewPlayer(controller: _controller),
                    ),
                    const VerticalDivider(width: 1, color: AppTheme.divider),

                    SizedBox(
                      width: 260,
                      child: InspectorPanel(controller: _controller),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1, color: AppTheme.divider),

              Expanded(
                flex: 4,
                child: TimelinePanel(controller: _controller),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _loadingShell() {
    return MaterialApp(
      title: 'Ghita Edit',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
              ),
              const SizedBox(height: 16),
              Text(
                _controller.statusMessage,
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopHeader(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.divider)),
      ),
      child: Row(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppTheme.primary, AppTheme.accent],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.movie_edit, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              const Text(
                "GHITA EDIT",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.card,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppTheme.divider),
                ),
                child: Text(
                  "C++ ENGINE ${AppTheme.appVersion}",
                  style: const TextStyle(color: AppTheme.accent, fontSize: 9, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),

          const SizedBox(width: 24),
          const VerticalDivider(indent: 12, endIndent: 12, color: AppTheme.divider),
          const SizedBox(width: 12),

          _buildTextMenu("File"),
          _buildTextMenu("Edit"),
          _buildTextMenu("Track"),
          _buildTextMenu("Effects"),
          _buildTextMenu("Help"),

          const Spacer(),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _controller.isEngineReady ? Colors.green.withOpacity(0.15) : Colors.amber.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _controller.isEngineReady ? Colors.greenAccent : Colors.amberAccent,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _controller.isEngineReady ? Icons.memory : Icons.hardware,
                  color: _controller.isEngineReady ? Colors.greenAccent : Colors.amberAccent,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Text(
                  _controller.isEngineReady ? "C++ FFI Active" : "Initializing C++ Engine",
                  style: TextStyle(
                    color: _controller.isEngineReady ? Colors.greenAccent : Colors.amberAccent,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 16),

          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              elevation: 4,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.file_upload_outlined, size: 16),
            label: const Text("Export", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            onPressed: () => showDialog(
              context: context,
              builder: (_) => ExportDialog(controller: _controller),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextMenu(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: MenuAnchor(
        builder: (context, controller, child) {
          return InkWell(
            onTap: () => controller.open(),
            onHover: () => controller.open(),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(
                label,
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ),
          );
        },
        menuChildren: [
          MenuItemButton(onPressed: () {}, child: const Text('New Project')),
          MenuItemButton(onPressed: () {}, child: const Text('Open Project...')),
          MenuItemButton(onPressed: () {}, child: const Text('Save As...')),
        ],
      ),
    );
  }
}
