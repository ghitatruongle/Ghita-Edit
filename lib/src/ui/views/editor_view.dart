import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
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
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller.init().catchError((Object error, StackTrace stack) {
      debugPrint('GhitaEngine init failed: $error\n$stack');
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _controller.handleKeyEvent,
      child: AnimatedBuilder(
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
      ),
    );
  }

  Widget _loadingShell() {
    return Scaffold(
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
          // Logo + Branding
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'assets/logo.png',
                  width: 28,
                  height: 28,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppTheme.primary, AppTheme.accent],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.movie_edit, color: Colors.white, size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'GHITA EDIT',
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
                  'C++ ENGINE ${AppTheme.appVersion}',
                  style: const TextStyle(color: AppTheme.accent, fontSize: 9, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),

          const SizedBox(width: 24),
          const VerticalDivider(indent: 12, endIndent: 12, color: AppTheme.divider),
          const SizedBox(width: 12),

          // Working Menus
          _buildPopupMenu('File', [
            _MenuItem('New Project', Icons.note_add, () => _controller.newProject()),
            _MenuItem('Open Project...', Icons.folder_open, _openProject),
            _MenuItem('Save (Ctrl+S)', Icons.save, () => _saveProject(context)),
            _MenuItem('Save As...', Icons.save_as, () => _saveProjectAs(context)),
            _MenuItem('Import Media...', Icons.video_file, _importMedia),
          ]),
          _buildPopupMenu('Edit', [
            _MenuItem('Undo (Ctrl+Z)', Icons.undo, _controller.canUndo ? _controller.undo : null),
            _MenuItem('Redo (Ctrl+Shift+Z)', Icons.redo, _controller.canRedo ? _controller.redo : null),
            _MenuItem('Copy (Ctrl+C)', Icons.copy, () => _controller.copySelectedClip()),
            _MenuItem('Paste (Ctrl+V)', Icons.paste, _controller.hasClipboard ? _controller.pasteClip : null),
            _MenuItem('Delete (Del)', Icons.delete, () => _controller.deleteSelectedClip()),
          ]),
          _buildPopupMenu('Track', [
            _MenuItem('Split at Playhead (S)', Icons.content_cut, () => _controller.splitAtPlayhead()),
            _MenuItem('Deselect All', Icons.deselect, () => _controller.deselectAll()),
          ]),
          _buildPopupMenu('Effects', [
            _MenuItem('No Filter', Icons.filter_none, () => _controller.setFilter(0, 1.0)),
            _MenuItem('Grayscale', Icons.gradient, () => _controller.setFilter(1, 1.0)),
            _MenuItem('Sepia', Icons.filter_vintage, () => _controller.setFilter(2, 1.0)),
            _MenuItem('Invert', Icons.invert_colors, () => _controller.setFilter(3, 1.0)),
            _MenuItem('Brightness+', Icons.brightness_6, () => _controller.setFilter(4, 0.5)),
          ]),
          _buildPopupMenu('Help', [
            _MenuItem('Keyboard Shortcuts', Icons.keyboard, () => _showShortcutsDialog(context)),
            _MenuItem('About Ghita Edit', Icons.info_outline, () => _showAboutDialog(context)),
          ]),

          const Spacer(),

          // Undo/Redo quick buttons
          IconButton(
            icon: Icon(Icons.undo, color: _controller.canUndo ? AppTheme.textMain : AppTheme.textMuted, size: 18),
            tooltip: _controller.canUndo ? 'Undo: ${_controller.commandHistory.lastUndoDescription}' : 'Nothing to undo',
            onPressed: _controller.canUndo ? _controller.undo : null,
          ),
          IconButton(
            icon: Icon(Icons.redo, color: _controller.canRedo ? AppTheme.textMain : AppTheme.textMuted, size: 18),
            tooltip: _controller.canRedo ? 'Redo: ${_controller.commandHistory.lastRedoDescription}' : 'Nothing to redo',
            onPressed: _controller.canRedo ? _controller.redo : null,
          ),

          const SizedBox(width: 8),

          // Engine Status Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _controller.isEngineReady ? Colors.green.withValues(alpha: 0.15) : Colors.amber.withValues(alpha: 0.15),
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
                  _controller.isEngineReady ? 'C++ FFI Active' : 'Initializing...',
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

          // Export Button
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              elevation: 4,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.file_upload_outlined, size: 16),
            label: const Text('Export', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            onPressed: () => showDialog(
              context: context,
              builder: (_) => ExportDialog(controller: _controller),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPopupMenu(String label, List<_MenuItem> items) {
    return PopupMenuButton<VoidCallback>(
      tooltip: label,
      offset: const Offset(0, 40),
      color: AppTheme.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onSelected: (callback) => callback(),
      itemBuilder: (context) => items.map((item) => PopupMenuItem<VoidCallback>(
        value: item.onTap,
        enabled: item.onTap != null,
        child: Row(
          children: [
            Icon(item.icon, size: 16, color: item.onTap != null ? AppTheme.textMain : AppTheme.textMuted),
            const SizedBox(width: 8),
            Text(item.label, style: TextStyle(
              color: item.onTap != null ? AppTheme.textMain : AppTheme.textMuted,
              fontSize: 12,
            )),
          ],
        ),
      )).toList(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4),
        child: Text(
          label,
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  // ========== Menu Actions ==========

  Future<void> _importMedia() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Import Media File',
        type: FileType.custom,
        allowedExtensions: ['mp4', 'mov', 'avi', 'mkv', 'mp3', 'wav', 'flac', 'png', 'jpg', 'jpeg'],
      );
      if (result != null && mounted) {
        _controller.importMedia(result.files.single.path!);
      }
    } catch (_) {}
  }

  Future<void> _openProject() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Open Ghita Edit Project',
        type: FileType.custom,
        allowedExtensions: ['ghita'],
      );
      if (result != null && mounted) {
        await _controller.loadProject(result.files.single.path!);
      }
    } catch (_) {}
  }

  Future<void> _saveProject(BuildContext context) async {
    final success = await _controller.quickSave();
    if (!success && context.mounted) {
      _saveProjectAs(context);
    }
  }

  Future<void> _saveProjectAs(BuildContext context) async {
    try {
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Project As',
        fileName: '${_controller.project.name}.ghita',
        type: FileType.custom,
        allowedExtensions: ['ghita'],
      );
      if (result != null && mounted) {
        await _controller.saveProject(result);
      }
    } catch (_) {}
  }

  void _showShortcutsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.keyboard, color: AppTheme.accent),
            SizedBox(width: 8),
            Text('Keyboard Shortcuts', style: TextStyle(color: AppTheme.textMain, fontSize: 16)),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _shortcutRow('Space', 'Play / Pause'),
              _shortcutRow('S', 'Split clip at playhead'),
              _shortcutRow('Delete', 'Delete selected clip'),
              _shortcutRow('Ctrl+Z', 'Undo'),
              _shortcutRow('Ctrl+Shift+Z / Ctrl+Y', 'Redo'),
              _shortcutRow('Ctrl+S', 'Quick Save'),
              _shortcutRow('Ctrl+C / Ctrl+V', 'Copy / Paste clip'),
              _shortcutRow('J / K / L', 'Shuttle: -5s / Play-Pause / +5s'),
              _shortcutRow('\u2190 / \u2192', 'Seek -1s / +1s'),
              _shortcutRow('Home / End', 'Go to start / end'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _shortcutRow(String keys, String desc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Text(keys, style: const TextStyle(color: AppTheme.accent, fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 12),
          Text(desc, style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        ],
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.movie_edit, color: AppTheme.primary),
            SizedBox(width: 8),
            Text('About Ghita Edit', style: TextStyle(color: AppTheme.textMain, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Version: ${AppTheme.appVersion}', style: const TextStyle(color: AppTheme.textMain)),
            const SizedBox(height: 8),
            const Text('Cross-platform multimedia editor with native C++ engine.', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
            const SizedBox(height: 8),
            Text('Engine: ${_controller.engineVersion}', style: const TextStyle(color: AppTheme.accent, fontSize: 11)),
            const SizedBox(height: 4),
            Text('Clips: ${_controller.project.allClips.length} | Tracks: ${_controller.tracks.length}', style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }
}

class _MenuItem {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  const _MenuItem(this.label, this.icon, this.onTap);
}
