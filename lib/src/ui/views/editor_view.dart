import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../controllers/editor_controller.dart';
import '../../models/track.dart';
import '../../models/studio_mode.dart';
import '../theme/app_theme.dart';
import '../widgets/preview_player.dart';
import '../widgets/media_bin.dart';
import '../widgets/inspector_panel.dart';
import '../widgets/timeline_panel.dart';
import '../widgets/audio_daw_panel.dart';
import '../widgets/photo_editor_panel.dart';

// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
import '../widgets/export_dialog.dart';
import '../widgets/undo_history_panel.dart';
import '../widgets/voiceover_recorder.dart';

// ============================================================
// EditorView — CapCut-style Main Layout v0.7.0
// ============================================================

class EditorView extends StatefulWidget {
  final ThemeMode themeMode;
  final Future<void> Function(ThemeMode) onThemeModeChanged;

  const EditorView({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  @override
  State<EditorView> createState() => _EditorViewState();
}

class _EditorViewState extends State<EditorView> {
  final EditorController _controller = EditorController();
  final FocusNode _focusNode = FocusNode();

  // v0.7.0: Collapsible panels state
  bool _mediaBinVisible = true;
  bool _inspectorVisible = true;

  // v1.0.0: Focus mode (Ctrl+Shift+F) — fullscreen preview, panels hidden.
  bool _focusMode = false;

  // v1.0.0: Controlled Media Bin tab so the bottom toolbar tools (Text /
  // Sticker / Filter / Audio) actually switch the bin to the relevant tab
  // instead of showing a dead-end toast. 0=Media 1=Audio 2=Stickers
  // 3=Effects 4=Text.
  int _mediaBinTab = 0;

  // v0.7.0: Active bottom tool
  String _activeTool = 'select';

  // v0.7.0: Toast overlay
  OverlayEntry? _toastOverlay;
  final List<_ToastItem> _toastQueue = [];
  // v1.0.1: Track pending toast timers so dispose() can cancel them.
  final List<Timer> _pendingToastTimers = [];

  // v0.7.0: Bottom toolbar tool definitions
  static const _bottomTools = [
    _BottomTool('select', Icons.touch_app, 'Select', 'Select & Move'),
    _BottomTool('trim', Icons.content_cut, 'Trim', 'Trim Clips'),
    _BottomTool('split', Icons.call_split, 'Split', 'Split at Playhead'),
    _BottomTool('text', Icons.title, 'Text', 'Add Text Overlay'),
    _BottomTool('sticker', Icons.emoji_emotions, 'Sticker', 'Add Stickers'),
    _BottomTool('filter', Icons.auto_fix_high, 'Filter', 'Apply Filters'),
    _BottomTool('audio', Icons.music_note, 'Audio', 'Audio Mixer'),
    _BottomTool('more', Icons.more_horiz, 'More', 'More Tools'),
  ];

  @override
  void initState() {
    super.initState();
    _controller.init().catchError((Object error, StackTrace stack) {
      debugPrint('GhitaEngine init failed: $error\n$stack');
    });
    _checkSessionRecovery();
  }

  // v0.7.0: Session Recovery — check for autosave on startup
  // v0.7.8: Uses a cancellable Timer so dispose() never leaves a pending timer
  Timer? _sessionRecoveryTimer;

  Future<void> _checkSessionRecovery() async {
    // Delay slightly to let engine initialize
    _sessionRecoveryTimer?.cancel();
    _sessionRecoveryTimer = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;

      try {
        final dir = await _getSupportDir();
        final latestAutoSave = await _controller.projectService.getLatestAutoSave(dir);
        if (latestAutoSave != null && mounted) {
          _showRecoveryDialog(latestAutoSave);
        }
      } catch (e) {
        debugPrint('Session recovery check failed: $e');
      }
    });
  }

  Future<String> _getSupportDir() async {
    try {
      final dir = await getApplicationSupportDirectory();
      return dir.path;
    } catch (_) {
      return Directory.systemTemp.path;
    }
  }

  void _showRecoveryDialog(String autoSavePath) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusLg)),
        title: Row(
          children: [
            Icon(Icons.restore_rounded, color: AppTheme.warning, size: 20),
            const SizedBox(width: 10),
            const Text('Session Recovery', style: TextStyle(color: AppTheme.textMain, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('A previous session was not closed properly.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            const SizedBox(height: 8),
            Text('Recover from: $autoSavePath', style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, fontFamily: 'monospace')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showToast('Session discarded');
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.textMuted),
            child: const Text('Discard'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final success = await _controller.loadProject(autoSavePath);
              _showToast(success ? 'Session recovered!' : 'Recovery failed');
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.primaryLight),
            child: const Text('Recover'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _sessionRecoveryTimer?.cancel();
    _focusNode.dispose();
    // v1.0.1: Cancel pending toast timers — otherwise they fire after
    // dispose and call remove() on stale OverlayEntries.
    for (final timer in _pendingToastTimers) {
      timer.cancel();
    }
    _pendingToastTimers.clear();
    // v1.0.1: Guard against a stale reference — the current toast may already
    // have been removed by its timer (double-removing an OverlayEntry crashes).
    try {
      _toastOverlay?.remove();
    } catch (_) {}
    _toastOverlay = null;
    // Remove any queued toast entries that haven't been shown yet.
    for (final item in _toastQueue) {
      try {
        item.entry.remove();
      } catch (_) {}
    }
    _toastQueue.clear();
    _controller.dispose();
    super.dispose();
  }

  // ============================================================
  // Toast System (v0.7.0)
  // ============================================================

  void _showToast(String message, {Duration duration = AppTheme.durationToast}) {
    if (!mounted) return;

    final entry = OverlayEntry(
      builder: (context) => _ToastOverlay(message: message, duration: duration),
    );

    _toastQueue.add(_ToastItem(entry, message, duration));
      if (_toastQueue.length == 1) {
        _showNextToast();
      }
  }

  void _showNextToast([OverlayState? overlay]) {
    overlay ??= Overlay.of(context);
    if (_toastQueue.isEmpty) return;
    final item = _toastQueue.removeAt(0);
    // v1.0.1: The previous entry may already have been removed by its timer
    // (guard in case the reference is stale) — double-removing crashes.
    try {
      _toastOverlay?.remove();
    } catch (_) {}
    _toastOverlay = item.entry;
    overlay.insert(item.entry);

    // v1.0.1: Track the timer so dispose() can cancel it.
    late final Timer timer;
    timer = Timer(item.duration, () {
      _pendingToastTimers.remove(timer);
      if (!mounted) return;
      try {
        item.entry.remove();
      } catch (_) {}
      // v1.0.1: Clear the reference when the toast expires — otherwise
      // OverlayEntry.remove() is called AGAIN on this detached entry by
      // _showNextToast()/dispose() and crashes ('should be removed only
      // once': assert in debug, null-check TypeError in release).
      if (_toastOverlay == item.entry) {
        _toastOverlay = null;
      }
      if (_toastQueue.isNotEmpty) {
        Future.microtask(() => _showNextToast(overlay));
      }
    });
    _pendingToastTimers.add(timer);
  }

  // ============================================================
  // Build
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      // v0.7.9: UX-04 — Ctrl+T toggles the theme at the view level (the
      // controller only knows the editor, not the theme), everything else
      // falls through to the controller's shortcut handler.
      onKeyEvent: _handleKeyEvent,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          // v1.0.1: Show the loading shell only while init() is running.
          // Once init completes (engine ready OR demo mode), show the full
          // editor layout — previously the app was stuck on the loading
          // shell forever when no native DLL was present.
          if (!_controller.isInitComplete) {
            return _loadingShell();
          }

          return Scaffold(
            backgroundColor: AppTheme.background,
            body: Column(
              children: [
                // ====== Top Header Bar ======
                _buildTopHeader(),

                const Divider(height: 1, color: AppTheme.divider),

                // ====== Main Content Area (Triple-Studio Suite v1.0.0) ======
                Expanded(
                  child: Builder(
                    builder: (context) {
                      if (_controller.activeStudioMode == StudioMode.audioDaw) {
                        return AudioDawPanel(controller: _controller);
                      }
                      if (_controller.activeStudioMode == StudioMode.photo) {
                        return PhotoEditorPanel(controller: _controller);
                      }

                      // Default: Video Studio (CapCut & WinK Pro)
                      // v1.0.0: Focus mode (Ctrl+Shift+F) — preview only,
                      // panels hidden, for a fullscreen editing view.
                      if (_focusMode) {
                        return Stack(
                          children: [
                            PreviewPlayer(controller: _controller),
                            Positioned(
                              top: 12,
                              right: 12,
                              child: Tooltip(
                                message: 'Exit Focus Mode (Ctrl+Shift+F)',
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.card,
                                    foregroundColor: AppTheme.textMain,
                                    elevation: 4,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
                                  ),
                                  icon: const Icon(Icons.fullscreen_exit_rounded, size: 16),
                                  label: const Text('Exit Focus', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                  onPressed: () => setState(() => _focusMode = false),
                                ),
                              ),
                            ),
                          ],
                        );
                      }

                      return Row(
                        children: [
                          // Media Bin (collapsible)
                          if (_mediaBinVisible) ...[
                            // v1.0.2: RepaintBoundary — the parent rebuilds at
                            // ~30 fps during playback; isolate each panel's
                            // paint so a dirty frame in one doesn't repaint all.
                            RepaintBoundary(
                              child: AnimatedContainer(
                                duration: AppTheme.durationNormal,
                                curve: AppTheme.curveStandard,
                                width: 280,
                                child: MediaBin(controller: _controller, initialTab: _mediaBinTab),
                              ),
                            ),
                            _buildPanelDivider(
                              onTap: () => setState(() => _mediaBinVisible = !_mediaBinVisible),
                            ),
                          ],

                          // Center: Preview + Timeline
                          Expanded(
                            child: Column(
                              children: [
                                // Preview Player
                                Expanded(
                                  flex: 5,
                                  child: RepaintBoundary(
                                    child: PreviewPlayer(controller: _controller),
                                  ),
                                ),

                                const Divider(height: 1, color: AppTheme.divider),

                                // Timeline Panel
                                Expanded(
                                  flex: 4,
                                  child: RepaintBoundary(
                                    child: TimelinePanel(controller: _controller),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Inspector Panel (collapsible)
                          if (_inspectorVisible) ...[
                            _buildPanelDivider(
                              onTap: () => setState(() => _inspectorVisible = !_inspectorVisible),
                            ),
                            RepaintBoundary(
                              child: AnimatedContainer(
                                duration: AppTheme.durationNormal,
                                curve: AppTheme.curveStandard,
                                width: 320,
                                child: InspectorPanel(controller: _controller),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),

                // v0.5.5: Status bar
                Container(
                  height: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: const BoxDecoration(
                    color: AppTheme.surface,
                    border: Border(top: BorderSide(color: AppTheme.divider)),
                  ),
                  child: Row(
                    children: [
                      Text(
                        'v${AppTheme.appVersion}',
                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
                      ),
                                  const SizedBox(width: 16),
                                  Text(
                                    '${_controller.project.allClips.length} clips',
                                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${_controller.tracks.length} tracks',
                                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
                                  ),
                                  if (_controller.selectedClipCount > 0) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      '⎵ ${_controller.selectedClipCount} sel',
                                      style: TextStyle(color: AppTheme.primaryLight, fontSize: 10, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppTheme.card,
                                      borderRadius: BorderRadius.circular(3),
                                      border: Border.all(color: AppTheme.divider),
                                    ),
                                    // v1.5.0-T3 (P1): the timecode listens to
                                    // the O(1) playhead notifier — playback
                                    // ticks no longer rebuild the status bar.
                                    child: ValueListenableBuilder<int>(
                                      valueListenable: _controller.playheadMs,
                                      builder: (context, posMs, _) => Text(
                                        formatTime(posMs),
                                        style: const TextStyle(color: AppTheme.textMain, fontSize: 10, fontFamily: 'monospace'),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  // v1.1.0 (PLAN_REVIEW A.2): removed the
                                  // DUPLICATED engine badge — the full badge
                                  // already lives in the top header; the
                                  // status bar shows a compact one-line state.
                                  Text(
                                    _controller.isEngineReady ? 'FFI Active' : 'Demo Mode',
                                    style: TextStyle(
                                      color: _controller.isEngineReady
                                          ? AppTheme.success
                                          : AppTheme.warning,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                // ====== Bottom Toolbar (v0.7.0 CapCut-style) ======
                _buildBottomToolbar(),
              ],
            ),
          );
        },
      ),
    );
  }

  // ============================================================
  // Top Header Bar
  // ============================================================

  Widget _buildTopHeader() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: const Border(bottom: BorderSide(color: AppTheme.divider)),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Row(
        children: [
          // Logo + Branding
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: AppTheme.gradientDecoration(
                  radius: AppTheme.radiusSm,
                  colors: const [AppTheme.primary, AppTheme.accent],
                  shadows: AppTheme.shadowGlow,
                ),
                child: Icon(Icons.movie_edit, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 10),
              AppTheme.gradientText(
                text: 'GHITA EDIT',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
                ),
                child: Text(
                  AppTheme.appVersion,
                  style: const TextStyle(color: AppTheme.primaryLight, fontSize: 9, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),

          const SizedBox(width: 16),
          Container(width: 1, height: 20, color: AppTheme.divider),
          const SizedBox(width: 12),

          // Working Menus
          _buildPopupMenu('File', [
            _MenuItem('New Project', Icons.note_add_rounded, () => _controller.newProject()),
            _MenuItem('Open Project...', Icons.folder_open_rounded, _openProject),
            _MenuItem('Save (Ctrl+S)', Icons.save_rounded, () => _saveProject(context)),
            _MenuItem('Save As...', Icons.save_as_rounded, () => _saveProjectAs(context)),
            _MenuItem('Import Media...', Icons.video_file, _importMedia),
          ]),
          _buildPopupMenu('Edit', [
            _MenuItem('Undo (Ctrl+Z)', Icons.undo_rounded, () {
              if (_controller.canUndo) { _controller.undo(); _showToast('Undone'); }
            }),
            _MenuItem('Redo (Ctrl+Y)', Icons.redo_rounded, () {
              if (_controller.canRedo) { _controller.redo(); _showToast('Redone'); }
            }),
            // v0.7.9: Cut now really cuts (copy + delete) — previously the
            // menu item only copied, unlike the Ctrl+X shortcut.
            _MenuItem('Cut (Ctrl+X)', Icons.cut_rounded, () {
              _controller.copySelectedClip();
              _controller.deleteSelectedClip();
              _showToast('Cut clip');
            }),
            _MenuItem('Copy (Ctrl+C)', Icons.copy_rounded, () {
              _controller.copySelectedClip(); _showToast('Copied clip');
            }),
            _MenuItem('Paste (Ctrl+V)', Icons.paste_rounded, () {
              if (_controller.hasClipboard) { _controller.pasteClip(); _showToast('Pasted clip'); }
            }),
            _MenuItem('Delete (Del)', Icons.delete_outline_rounded, () {
              _controller.deleteSelectedClip(); _showToast('Deleted clip');
            }),
            // v0.7.9: Select All now reports how many clips were selected.
            _MenuItem('Select All (Ctrl+A)', Icons.select_all_rounded, () {
              final count = _controller.project.allClips.length;
              _controller.project.selectAll();
              // v1.5.0-T1: refresh selection-dependent UI immediately — the
              // menu path used to leave highlights stale until the next event.
              if (count > 0) _controller.notifyListeners();
              _showToast(count > 0 ? 'Selected $count clips' : 'No clips to select');
            }),
          ]),
          _buildPopupMenu('Track', [
            _MenuItem('Split at Playhead (S)', Icons.call_split, () => _controller.splitAtPlayhead()),
            _MenuItem('Add Video Track', Icons.videocam_rounded, () => _addTrack('Video Track', 'video')),
            _MenuItem('Add Audio Track', Icons.audiotrack_rounded, () => _addTrack('Audio Track', 'audio')),
            _MenuItem('Add Overlay Track', Icons.subtitles_rounded, () => _addTrack('Overlay Track', 'overlay')),
            _MenuItem('Deselect All', Icons.deselect_rounded, () => _controller.deselectAll()),
          ]),
          _buildPopupMenu('View', [
            _MenuItem(
              widget.themeMode == ThemeMode.dark ? 'Switch to Light Theme' : 'Switch to Dark Theme',
              widget.themeMode == ThemeMode.dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              () async {
                final newMode = widget.themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
                await widget.onThemeModeChanged(newMode);
              },
            ),
            _MenuItem('Always Light', Icons.light_mode_rounded, () => widget.onThemeModeChanged(ThemeMode.light)),
            _MenuItem('Always Dark', Icons.dark_mode_rounded, () => widget.onThemeModeChanged(ThemeMode.dark)),
            _MenuItem('Toggle Media Bin', Icons.folder_rounded, () => setState(() => _mediaBinVisible = !_mediaBinVisible)),
            _MenuItem('Toggle Inspector', Icons.tune_rounded, () => setState(() => _inspectorVisible = !_inspectorVisible)),
          ]),
          _buildPopupMenu('Help', [
            _MenuItem('Keyboard Shortcuts', Icons.keyboard_rounded, () => _showShortcutsDialog(context)),
            _MenuItem('Undo History', Icons.history_rounded, () => _showUndoHistoryPanel(context)),
            _MenuItem('Project Templates', Icons.dashboard_rounded, () => _showTemplatesDialog(context)),
            _MenuItem('About Ghita Edit', Icons.info_outline_rounded, () => _showAboutDialog(context)),
          ]),

          const SizedBox(width: 16),
          Container(width: 1, height: 20, color: AppTheme.divider),
          const SizedBox(width: 12),

          // Triple-Studio Mode Switcher (v1.0.0)
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: StudioMode.values.map((mode) {
                final isActive = _controller.activeStudioMode == mode;
                return InkWell(
                  onTap: () {
                    _controller.setStudioMode(mode);
                    _showToast('Switched to ${mode.displayName}');
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: AnimatedContainer(
                    duration: AppTheme.durationFast,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isActive ? AppTheme.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: isActive ? AppTheme.shadowSm : null,
                    ),
                    child: Row(
                      children: [
                        Text(
                          mode.displayName.split(' ')[0],
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          mode.displayName.substring(2).trim(),
                          style: TextStyle(
                            color: isActive ? Colors.white : AppTheme.textMuted,
                            fontSize: 11,
                            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          const Spacer(),

          // Undo/Redo buttons
          _buildToolbarIconButton(
            Icons.undo_rounded,
            _controller.canUndo ? AppTheme.textSecondary : AppTheme.textMuted,
            _controller.canUndo ? 'Undo: ${_controller.commandHistory.lastUndoDescription}' : 'Nothing to undo',
            () {
              _controller.undo();
              _showToast('Undone');
            },
          ),
          _buildToolbarIconButton(
            Icons.redo_rounded,
            _controller.canRedo ? AppTheme.textSecondary : AppTheme.textMuted,
            _controller.canRedo ? 'Redo: ${_controller.commandHistory.lastRedoDescription}' : 'Nothing to redo',
            () {
              _controller.redo();
              _showToast('Redone');
            },
          ),

          const SizedBox(width: 8),

          // v0.7.9: UX-04 — visible theme toggle button (Ctrl+T).
          _buildToolbarIconButton(
            widget.themeMode == ThemeMode.dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
            AppTheme.textSecondary,
            widget.themeMode == ThemeMode.dark ? 'Switch to Light Theme (Ctrl+T)' : 'Switch to Dark Theme (Ctrl+T)',
            _toggleTheme,
          ),

          const SizedBox(width: 8),

          // Engine Status Badge
          _buildEngineStatusBadge(),

          const SizedBox(width: 12),

          // Export Button
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _controller.isExporting ? AppTheme.textMuted : AppTheme.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusSm + 4),
              ),
            ),
            icon: _controller.isExporting
                ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.upload_rounded, size: 16),
            label: Text(
              _controller.isExporting ? 'Exporting...' : 'Export',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
            onPressed: !_controller.isExporting
                ? () => showDialog(
                    context: context,
                    builder: (_) => ExportDialog(controller: _controller),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // Bottom Toolbar (v0.7.0 CapCut-style)
  // ============================================================

  Widget _buildBottomToolbar() {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: const Border(top: BorderSide(color: AppTheme.divider)),
        boxShadow: AppTheme.shadowMd,
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),

          // Tool buttons
          ..._bottomTools.map((tool) {
            final isActive = _activeTool == tool.id;
            return _BottomToolButton(
              tool: tool,
              isActive: isActive,
              onTap: () {
                setState(() => _activeTool = tool.id);
                _onToolSelected(tool.id);
              },
            );
          }),

          const Spacer(),

          // Quick action: Undo/Redo
          _buildToolbarIconButton(
            Icons.undo_rounded, AppTheme.textSecondary, 'Undo',
            () { _controller.undo(); _showToast('Undone'); },
            size: 20,
          ),
          _buildToolbarIconButton(
            Icons.redo_rounded, AppTheme.textSecondary, 'Redo',
            () { _controller.redo(); _showToast('Redone'); },
            size: 20,
          ),

          const SizedBox(width: 12),

          // Divider
          Container(width: 1, height: 28, color: AppTheme.divider),
          const SizedBox(width: 8),

          // Toggle panels buttons
          _buildToolbarIconButton(
            _mediaBinVisible ? Icons.folder_open : Icons.folder_off,
            _mediaBinVisible ? AppTheme.primaryLight : AppTheme.textMuted,
            _mediaBinVisible ? 'Hide Media Bin' : 'Show Media Bin',
            () => setState(() => _mediaBinVisible = !_mediaBinVisible),
            size: 18,
          ),
          _buildToolbarIconButton(
            Icons.tune,
            _inspectorVisible ? AppTheme.primaryLight : AppTheme.textMuted,
            _inspectorVisible ? 'Hide Inspector' : 'Show Inspector',
            () => setState(() => _inspectorVisible = !_inspectorVisible),
            size: 18,
          ),
        ],
      ),
    );
  }

  void _onToolSelected(String toolId) {
    switch (toolId) {
      case 'trim':
        // v1.0.0: Select the clip under the playhead so trim handles are
        // immediately actionable, instead of a dead-end toast.
        for (final track in _controller.tracks) {
          final clip = track.clipAtPosition(_controller.positionMs);
          if (clip != null) {
            _controller.selectClip(clip.id);
            break;
          }
        }
        _showToast('Trim mode: drag clip edges to trim');
        break;
      case 'split':
        _controller.splitAtPlayhead();
        _showToast('Split at playhead');
        break;
      case 'text':
        // v1.0.0: actually switch the Media Bin to the Text tab.
        _switchMediaBinTab(4);
        break;
      case 'sticker':
        _switchMediaBinTab(2);
        break;
      case 'filter':
        _switchMediaBinTab(3);
        break;
      case 'audio':
        // v0.8.0: The Audio tool opens the voiceover recorder (record
        // mic → WAV → timeline clip) instead of a dead-end toast.
        _showVoiceoverSheet();
        break;
      case 'more':
        _showMoreToolsDialog();
        break;
      default:
        break;
    }
  }

  /// v1.0.0: Switch the Media Bin to [tab] (0=Media 1=Audio 2=Stickers
  /// 3=Effects 4=Text), showing it first if hidden. The toolbar's Text /
  /// Sticker / Filter tools now navigate to the right tab instead of
  /// showing a toast.
  void _switchMediaBinTab(int tab) {
    setState(() {
      if (!_mediaBinVisible) _mediaBinVisible = true;
      _mediaBinTab = tab;
    });
  }

  // v0.7.9: UX-04 — view-level key handling: Ctrl+T toggles the theme;
  // every other key falls through to the editor controller.
  // v1.0.0: Ctrl+B / Ctrl+I toggle the Media Bin / Inspector panels;
  // Ctrl+Shift+F toggles Focus mode (fullscreen preview) — these were
  // advertised in the shortcuts dialog but never handled.
  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (ctrl) {
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.keyT) {
        _toggleTheme();
        return true;
      }
      if (key == LogicalKeyboardKey.keyB) {
        setState(() => _mediaBinVisible = !_mediaBinVisible);
        _showToast(_mediaBinVisible ? 'Media Bin shown' : 'Media Bin hidden');
        return true;
      }
      if (key == LogicalKeyboardKey.keyI) {
        setState(() => _inspectorVisible = !_inspectorVisible);
        _showToast(_inspectorVisible ? 'Inspector shown' : 'Inspector hidden');
        return true;
      }
      if (shift && key == LogicalKeyboardKey.keyF) {
        setState(() => _focusMode = !_focusMode);
        _showToast(_focusMode ? 'Focus mode on' : 'Focus mode off');
        return true;
      }
      // v1.5.0 T3 (#18): action search palette (Ctrl+P).
      if (key == LogicalKeyboardKey.keyP) {
        _showActionSearch(context);
        return true;
      }
    }
    return _controller.handleKeyEvent(event);
  }

  // v1.5.0 T3 (#18): searchable action palette (Ctrl+P).
  void _showActionSearch(BuildContext context) {
    final ctrl = _controller;
    final actions = <(String, IconData, VoidCallback)>[
      ('Show Media Bin', Icons.add_rounded, () => setState(() => _mediaBinVisible = true)),
      ('Undo', Icons.undo_rounded, ctrl.undo),
      ('Redo', Icons.redo_rounded, ctrl.redo),
      ('Copy Selected Clip', Icons.content_copy_rounded, ctrl.copySelectedClip),
      ('Paste Clip', Icons.content_paste_rounded, ctrl.pasteClip),
      ('Toggle Media Bin', Icons.video_library_rounded,
          () => setState(() => _mediaBinVisible = !_mediaBinVisible)),
      ('Toggle Inspector', Icons.tune_rounded,
          () => setState(() => _inspectorVisible = !_inspectorVisible)),
      ('Toggle Theme', Icons.wb_sunny_rounded, _toggleTheme),
      ('Focus Mode', Icons.fullscreen_rounded,
          () => setState(() => _focusMode = !_focusMode)),
      ('Add Bookmark at Playhead', Icons.bookmark_add_rounded, () {
        ctrl.addBookmark(ctrl.positionMs);
      }),
    ];
    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        var query = '';
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final results = actions
                .where((a) =>
                    a.$1.toLowerCase().contains(query.toLowerCase()))
                .toList();
            return AlertDialog(
              backgroundColor: AppTheme.card,
              title: const Text('Action Search',
                  style: TextStyle(fontSize: 14, color: AppTheme.textMain)),
              content: SizedBox(
                width: 320,
                height: 320,
                child: Column(
                  children: [
                    TextField(
                      autofocus: true,
                      style: const TextStyle(
                          color: AppTheme.textMain, fontSize: 12),
                      decoration: InputDecoration(
                        hintText: 'Type to filter actions…',
                        hintStyle: const TextStyle(
                            color: AppTheme.textMuted, fontSize: 12),
                        prefixIcon: const Icon(Icons.search_rounded,
                            size: 16, color: AppTheme.textMuted),
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusSm)),
                      ),
                      onChanged: (v) => setDialogState(() => query = v),
                      onSubmitted: (_) {
                        if (results.isNotEmpty) {
                          Navigator.pop(dialogCtx);
                          results.first.$3();
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: results.length,
                        itemBuilder: (_, i) => ListTile(
                          dense: true,
                          leading: Icon(results[i].$2,
                              size: 16, color: AppTheme.primaryLight),
                          title: Text(results[i].$1,
                              style: const TextStyle(
                                  color: AppTheme.textMain, fontSize: 12)),
                          onTap: () {
                            Navigator.pop(dialogCtx);
                            results[i].$3();
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // v0.7.9: UX-04 — theme toggle with toast feedback (also used by the
  // header button and the View menu).
  Future<void> _toggleTheme() async {
    final newMode = widget.themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    await widget.onThemeModeChanged(newMode);
    _showToast('Theme switched to ${newMode.name}');
  }

  // v0.8.0: The Audio tool opens the voiceover recorder in a bottom sheet.
  void _showVoiceoverSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: VoiceoverRecorder(controller: _controller),
      ),
    );
  }

  void _showMoreToolsDialog() {    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusLg)),
        title: const Text('More Tools', style: TextStyle(color: AppTheme.textMain, fontSize: 16)),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _moreToolTile(Icons.call_split, 'Split at Playhead', 'S', () { _controller.splitAtPlayhead(); Navigator.pop(context); }),
              _moreToolTile(Icons.delete_outline_rounded, 'Delete Selected', 'Del', () { _controller.deleteSelectedClip(); Navigator.pop(context); }),
              _moreToolTile(Icons.copy_rounded, 'Copy Clip', 'Ctrl+C', () { _controller.copySelectedClip(); Navigator.pop(context); }),
              _moreToolTile(Icons.paste_rounded, 'Paste Clip', 'Ctrl+V', () { _controller.pasteClip(); Navigator.pop(context); }),
              _moreToolTile(Icons.undo_rounded, 'Undo', 'Ctrl+Z', () { if (_controller.canUndo) { _controller.undo(); _showToast('Undone'); } Navigator.pop(context); }),
              _moreToolTile(Icons.redo_rounded, 'Redo', 'Ctrl+Y', () { if (_controller.canRedo) { _controller.redo(); _showToast('Redone'); } Navigator.pop(context); }),
              _moreToolTile(Icons.save_rounded, 'Save Project', 'Ctrl+S', () { _saveProject(context); Navigator.pop(context); }),
              _moreToolTile(Icons.add_circle_outline_rounded, 'New Track', '', () { _addTrack('Video Track', 'video'); Navigator.pop(context); }),
              // v0.7.8: pop the More Tools dialog FIRST, then push the new
              // one — the old order pushed then popped, instantly closing the
              // freshly opened dialog and leaving More Tools open.
              _moreToolTile(Icons.history_rounded, 'Undo History', '', () { Navigator.pop(context); _showUndoHistoryPanel(context); }),
              _moreToolTile(Icons.dashboard_rounded, 'Templates', '', () { Navigator.pop(context); _showTemplatesDialog(context); }),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  // v0.7.0: Undo History Panel
  void _showUndoHistoryPanel(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => UndoHistoryPanel(
        controller: _controller,
        onClose: () => Navigator.pop(context),
      ),
    );
  }

  // v0.7.0: Project Templates Dialog
  void _showTemplatesDialog(BuildContext context) {
    final templates = [
      {'name': 'YouTube Video', 'icon': Icons.play_circle_filled, 'w': 1920, 'h': 1080, 'fps': 60, 'desc': 'Full HD • 60fps • Landscape'},
      {'name': 'YouTube Shorts', 'icon': Icons.smartphone, 'w': 1080, 'h': 1920, 'fps': 30, 'desc': '9:16 • 30fps • Vertical'},
      {'name': 'TikTok / Reels', 'icon': Icons.phone_iphone, 'w': 1080, 'h': 1920, 'fps': 30, 'desc': '9:16 • 30fps • Vertical'},
      {'name': 'Instagram Story', 'icon': Icons.camera_alt, 'w': 1080, 'h': 1920, 'fps': 30, 'desc': '9:16 • 30fps • Story'},
      {'name': 'Instagram Post', 'icon': Icons.camera, 'w': 1080, 'h': 1080, 'fps': 30, 'desc': '1:1 • 30fps • Square'},
      {'name': 'Twitter / X', 'icon': Icons.chat, 'w': 1280, 'h': 720, 'fps': 30, 'desc': '720p • 30fps • Landscape'},
      {'name': 'Podcast', 'icon': Icons.mic_rounded, 'w': 1920, 'h': 1080, 'fps': 30, 'desc': 'Full HD • 30fps • Talking head'},
      {'name': 'Gaming', 'icon': Icons.sports_esports_rounded, 'w': 1920, 'h': 1080, 'fps': 60, 'desc': 'Full HD • 60fps • High action'},
      {'name': 'Wedding', 'icon': Icons.favorite_rounded, 'w': 1920, 'h': 1080, 'fps': 30, 'desc': 'Full HD • 30fps • Cinematic'},
      {'name': 'Custom', 'icon': Icons.tune, 'w': 1920, 'h': 1080, 'fps': 60, 'desc': 'Custom resolution and FPS'},
    ];

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusLg)),
        title: const Row(
          children: [
            Icon(Icons.dashboard_rounded, color: AppTheme.primaryLight, size: 18),
            SizedBox(width: 10),
            Text('Project Templates', style: TextStyle(color: AppTheme.textMain, fontSize: 16)),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1.4,
            ),
            itemCount: templates.length,
            itemBuilder: (context, index) {
              final t = templates[index];
              return _TemplateCard(
                name: t['name'] as String,
                icon: t['icon'] as IconData,
                desc: t['desc'] as String,
                onTap: () {
                  _controller.project.outputWidth = t['w'] as int;
                  _controller.project.outputHeight = t['h'] as int;
                  _controller.project.outputFps = t['fps'] as int;
                  _controller.project.markModified();
                  _controller.notifyListeners();
                  Navigator.pop(context);
                  _showToast('Template applied: ${t['name']}');
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(foregroundColor: AppTheme.textMuted),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _moreToolTile(IconData icon, String label, String shortcut, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppTheme.textSecondary),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: const TextStyle(color: AppTheme.textMain, fontSize: 13))),
            if (shortcut.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(shortcut, style: const TextStyle(color: AppTheme.textMuted, fontSize: 10, fontFamily: 'monospace')),
              ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // Panel Divider
  // ============================================================

  Widget _buildPanelDivider({required VoidCallback onTap}) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 4,
          color: AppTheme.divider,
          child: Center(
            child: Container(
              width: 2,
              height: 32,
              decoration: BoxDecoration(
                color: AppTheme.textMuted.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // Toolbar Icon Button Helper
  // ============================================================

  Widget _buildToolbarIconButton(IconData icon, Color color, String tooltip, VoidCallback onPressed, {double size = 18}) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: size, color: color),
        onPressed: onPressed,
        style: IconButton.styleFrom(
          padding: const EdgeInsets.all(6),
        ),
      ),
    );
  }

  // ============================================================
  // Engine Status Badge
  // ============================================================

  Widget _buildEngineStatusBadge() {
    final isReady = _controller.isEngineReady;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: isReady ? AppTheme.success.withValues(alpha: 0.1) : AppTheme.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isReady ? AppTheme.success : AppTheme.warning,
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isReady ? Icons.memory_rounded : Icons.hardware_rounded,
            size: 12,
            color: isReady ? AppTheme.success : AppTheme.warning,
          ),
          const SizedBox(width: 4),
          Text(
            isReady ? 'FFI Active' : 'Demo Mode',
            style: TextStyle(
              color: isReady ? AppTheme.success : AppTheme.warning,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // Popup Menu Builder
  // ============================================================

  Widget _buildPopupMenu(String label, List<_MenuItem> items) {
    return PopupMenuButton<VoidCallback>(
      tooltip: label,
      offset: const Offset(0, 36),
      color: AppTheme.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
      elevation: 16,
      onSelected: (callback) => callback(),
      itemBuilder: (context) => items.map((item) => PopupMenuItem<VoidCallback>(
        value: item.onTap,
        enabled: item.onTap != null,
        child: Row(
          children: [
            Icon(item.icon, size: 16, color: item.onTap != null ? AppTheme.textSecondary : AppTheme.textMuted),
            const SizedBox(width: 10),
            Text(item.label, style: TextStyle(
              color: item.onTap != null ? AppTheme.textMain : AppTheme.textMuted,
              fontSize: 12,
              height: 1.4,
            )),
          ],
        ),
      )).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        ),
        child: Text(
          label,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  // ============================================================
  // Loading Shell
  // ============================================================

  Widget _loadingShell() {
    // v1.0.1: While initializing, show a spinner. The full editor layout
    // appears once init() completes (handled by isInitComplete in build()).
    final initializing = !_controller.isInitComplete;
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: AppTheme.gradientDecoration(
                radius: AppTheme.radiusLg,
                colors: const [AppTheme.primary, AppTheme.accent],
                shadows: AppTheme.shadowGlow,
              ),
              child: Icon(Icons.movie_edit, color: Colors.white, size: 32),
            ),
            const SizedBox(height: 24),
            if (initializing) ...[
              const CircularProgressIndicator(color: AppTheme.primaryLight, strokeWidth: 2),
              const SizedBox(height: 24),
            ],
            Text(
              _controller.statusMessage,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14, height: 1.5),
              textAlign: TextAlign.center,
            ),
            if (!_controller.isEngineReady) ...[
              const SizedBox(height: 12),
              Text(
                'Running in demo mode — no native C++ engine loaded',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12, fontStyle: FontStyle.italic),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ============================================================
  // Menu Actions
  // ============================================================

  Future<void> _importMedia() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Import Media File',
        type: FileType.custom,
        allowedExtensions: ['mp4', 'mov', 'avi', 'mkv', 'mp3', 'wav', 'flac', 'png', 'jpg', 'jpeg', 'webm', 'gif'],
      );
      if (result != null && mounted) {
        // v1.0.1: Null-safe — path can be null on some platforms (web).
        final path = result.files.single.path;
        if (path == null || path.isEmpty) {
          _showToast('Import cancelled — no file selected');
          return;
        }
        _controller.importMedia(path);
        _showToast('Imported: ${result.files.single.name}');
      }
    } catch (e) {
      _showToast('Import failed', duration: const Duration(seconds: 3));
    }
  }

  Future<void> _openProject() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Open Ghita Edit Project',
        type: FileType.custom,
        allowedExtensions: ['ghita'],
      );
      if (result != null && mounted) {
        // v1.5.0-T1: path can be null on some platforms — never force-unwrap.
        final path = result.files.single.path;
        if (path == null || path.isEmpty) {
          _showToast('Open cancelled — no file selected');
          return;
        }
        final success = await _controller.loadProject(path);
        _showToast(success ? 'Project loaded' : 'Failed to load project', duration: const Duration(seconds: 3));
      }
    } catch (e) {
      _showToast('Error loading project', duration: const Duration(seconds: 3));
    }
  }

  Future<void> _saveProject(BuildContext context) async {
    final success = await _controller.quickSave();
    _showToast(success ? 'Project saved' : 'No path set — use Save As', duration: const Duration(seconds: 2));
  }

  Future<void> _saveProjectAs(BuildContext context) async {
    try {
      final path = await _pickSavePath();
      if (path != null && mounted) {
        final success = await _controller.saveProject(path);
        _showToast(success ? 'Project saved' : 'Save failed', duration: const Duration(seconds: 3));
      }
    } catch (e) {
      _showToast('Error saving project', duration: const Duration(seconds: 3));
    }
  }

  Future<String?> _pickSavePath() async {
    try {
      // v1.5.0-T1: pickFiles opens a LOAD dialog — creating a NEW .ghita file
      // was impossible. saveFile is the actual Save As dialog on desktop.
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Project As',
        fileName: 'untitled.ghita',
        type: FileType.custom,
        allowedExtensions: ['ghita'],
      );
      return result;
    } catch (e) {
      debugPrint('Save path selection error: $e');
      return null;
    }
  }

  void _addTrack(String name, String type) {
    _controller.addNewTrack(name, type == 'video' ? TrackType.video : type == 'audio' ? TrackType.audio : TrackType.overlay);
    _showToast('Added: $name');
  }

  // ============================================================
  // Dialogs
  // ============================================================

  // v0.7.9: UX-04 — shortcuts dialog with live search filter.
  void _showShortcutsDialog(BuildContext context) {
    final sections = <String, List<(String, String)>>{
      'Playback': [
        ('Space', 'Play / Pause'),
        ('J / K / L', 'Shuttle: -5s / Play-Pause / +5s'),
        ('← / →', 'Seek -1s / +1s'),
        ('Home / End', 'Go to start / end'),
      ],
      'Editing': [
        ('Ctrl+Z', 'Undo'),
        ('Ctrl+Shift+Z / Ctrl+Y', 'Redo'),
        ('Ctrl+S', 'Quick Save'),
        ('Ctrl+X', 'Cut'),
        ('Ctrl+C / Ctrl+V', 'Copy / Paste clip'),
        ('S', 'Split clip at playhead'),
        ('Delete', 'Delete selected clip'),
        ('Ctrl+A', 'Select all clips'),
      ],
      'View': [
        ('Ctrl+T', 'Toggle theme'),
        ('Ctrl+G', 'Group selected clips'),
        ('Ctrl+Shift+G', 'Ungroup clips'),
        ('Ctrl+B', 'Toggle Media Bin'),
        ('Ctrl+I', 'Toggle Inspector'),
        ('Ctrl+Shift+F', 'Focus mode (fullscreen preview)'),
      ],
    };

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) {
          final query = _shortcutsQuery;
          final filtered = <String, List<(String, String)>>{};
          sections.forEach((title, rows) {
            final match = rows.where((r) {
              final q = query.toLowerCase();
              return r.$1.toLowerCase().contains(q) ||
                  r.$2.toLowerCase().contains(q) ||
                  title.toLowerCase().contains(q);
            }).toList();
            if (match.isNotEmpty) filtered[title] = match;
          });
          final anyMatch = filtered.isNotEmpty;

          return AlertDialog(
            backgroundColor: AppTheme.card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusLg)),
            title: const Row(
              children: [
                Icon(Icons.keyboard_rounded, color: AppTheme.primaryLight),
                SizedBox(width: 10),
                Text('Keyboard Shortcuts', style: TextStyle(color: AppTheme.textMain, fontSize: 16)),
              ],
            ),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    autofocus: false,
                    decoration: InputDecoration(
                      hintText: 'Search shortcuts...',
                      hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                      prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textMuted, size: 16),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSm), borderSide: BorderSide.none),
                      fillColor: AppTheme.surfaceVariant,
                      filled: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    style: const TextStyle(color: AppTheme.textMain, fontSize: 12),
                    onChanged: (value) => setState(() => _shortcutsQuery = value),
                  ),
                  const SizedBox(height: 12),
                  if (!anyMatch)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('No shortcuts found',
                          style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                    )
                  else
                    ...filtered.entries.expand((entry) => [
                          _shortcutSection(entry.key,
                              entry.value.map((r) => _shortcutRow(r.$1, r.$2)).toList()),
                          const SizedBox(height: 12),
                        ]),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  _shortcutsQuery = '';
                  Navigator.pop(context);
                },
                style: TextButton.styleFrom(foregroundColor: AppTheme.primaryLight),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  // v0.7.9: UX-04 — persistent search text for the shortcuts dialog.
  String _shortcutsQuery = '';

  Widget _shortcutSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: AppTheme.accent, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
        const SizedBox(height: 6),
        ...children,
      ],
    );
  }

  Widget _shortcutRow(String keys, String desc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(keys, style: const TextStyle(color: AppTheme.primaryLight, fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(desc, style: const TextStyle(color: AppTheme.textMuted, fontSize: 12))),
        ],
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusLg)),
        title: const Row(
          children: [
            Icon(Icons.movie_edit, color: AppTheme.primary),
            SizedBox(width: 10),
            Text('About Ghita Edit', style: TextStyle(color: AppTheme.textMain, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Version: ${AppTheme.appVersion}', style: const TextStyle(color: AppTheme.textMain, fontSize: 13)),
            const SizedBox(height: 6),
            const Text('Cross-platform multimedia editor with native C++ engine.', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
            const SizedBox(height: 6),
            Text('Engine: ${_controller.engineVersion}', style: const TextStyle(color: AppTheme.accent, fontSize: 11)),
            const SizedBox(height: 4),
            Text('Clips: ${_controller.project.allClips.length} | Tracks: ${_controller.tracks.length}', style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
            const SizedBox(height: 8),
            Text('v0.7.0: CapCut-style UI • Bottom toolbar • Rich text • Stickers • Audio waveform • Keyframes • Color correction • PIP • Split view',
                style: const TextStyle(color: AppTheme.primaryLight, fontSize: 9, fontStyle: FontStyle.italic)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(foregroundColor: AppTheme.primaryLight),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // Time Formatting
  // ============================================================

  static String formatTime(int ms) {
    final seconds = (ms / 1000).floor();
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    final millis = ms % 1000;
    return '${mins.toString().padLeft(2, "0")}:${secs.toString().padLeft(2, "0")}.${millis.toString().padLeft(3, "0")}';
  }
}

// ============================================================
// Bottom Tool Button Widget (v0.7.0)
// ============================================================

class _BottomToolButton extends StatelessWidget {
  final _BottomTool tool;
  final bool isActive;
  final VoidCallback onTap;

  const _BottomToolButton({
    required this.tool,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tool.description,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: AnimatedContainer(
          duration: AppTheme.durationFast,
          curve: AppTheme.curveSnap,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isActive ? AppTheme.primary.withValues(alpha: 0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                tool.icon,
                size: 20,
                color: isActive ? AppTheme.primaryLight : AppTheme.textSecondary,
              ),
              const SizedBox(height: 3),
              Text(
                tool.label,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  color: isActive ? AppTheme.primaryLight : AppTheme.textMuted,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomTool {
  final String id;
  final IconData icon;
  final String label;
  final String description;
  const _BottomTool(this.id, this.icon, this.label, this.description);
}

// ============================================================
// Toast Overlay Widget (v0.7.0)
// ============================================================

class _ToastOverlay extends StatefulWidget {
  final String message;
  final Duration duration;

  const _ToastOverlay({required this.message, required this.duration});

  @override
  State<_ToastOverlay> createState() => _ToastOverlayState();
}

class _ToastOverlayState extends State<_ToastOverlay> {
  late double _opacity;
  // v1.0.2: A cancellable Timer instead of Future.delayed — the fade-out
  // callback can now be cancelled in dispose(), so an early-dismissed toast
  // (new toast replacing it) can never fire setState after disposal.
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _opacity = 0;
    Future.microtask(() {
      if (mounted) setState(() => _opacity = 1);
    });
    // Auto-dismiss after the widget's duration — fade out only. The overlay
    // entry itself is removed by _showNextToast; v0.7.8 removed the
    // Navigator.maybePop() here, which used to close whatever dialog was on
    // top (Export, Shortcuts, ...) when the toast expired.
    _dismissTimer = Timer(widget.duration, () {
      if (mounted) {
        setState(() => _opacity = 0);
      }
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 48,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        opacity: _opacity,
        duration: AppTheme.durationFast,
        curve: AppTheme.curveDecelerate,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              border: Border.all(color: AppTheme.divider, width: 0.5),
              boxShadow: AppTheme.shadowLg,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_rounded, size: 16, color: AppTheme.success),
                const SizedBox(width: 8),
                Text(
                  widget.message,
                  style: const TextStyle(color: AppTheme.textMain, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToastItem {
  final OverlayEntry entry;
  final String message;
  final Duration duration;
  const _ToastItem(this.entry, this.message, this.duration);
}

// ============================================================
// Menu Item Helper
// ============================================================

class _MenuItem {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  const _MenuItem(this.label, this.icon, this.onTap);
}

// ============================================================
// Template Card Widget (v0.7.0)
// ============================================================

class _TemplateCard extends StatelessWidget {
  final String name;
  final IconData icon;
  final String desc;
  final VoidCallback onTap;

  const _TemplateCard({required this.name, required this.icon, required this.desc, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(color: AppTheme.divider, width: 0.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: AppTheme.primaryLight),
            const SizedBox(height: 6),
            Text(name, style: const TextStyle(color: AppTheme.textMain, fontSize: 11, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
            const SizedBox(height: 2),
            Text(desc, style: const TextStyle(color: AppTheme.textMuted, fontSize: 9), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
