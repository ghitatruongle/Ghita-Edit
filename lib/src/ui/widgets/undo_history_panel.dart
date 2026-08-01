import 'package:flutter/material.dart';
import '../../controllers/editor_controller.dart';
import '../theme/app_theme.dart';

// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

// ============================================================
// UndoHistoryPanel — v0.7.0 Visual Undo/Redo Timeline
// v0.7.8: Stateful — listens to the controller so the list, "steps" counter
// and CURRENT badge actually update when undo/redo happens inside the panel.
// ============================================================

class UndoHistoryPanel extends StatefulWidget {
  final EditorController controller;
  final VoidCallback onClose;

  const UndoHistoryPanel({super.key, required this.controller, required this.onClose});

  @override
  State<UndoHistoryPanel> createState() => _UndoHistoryPanelState();
}

class _UndoHistoryPanelState extends State<UndoHistoryPanel> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final history = controller.commandHistory;
    final undoStack = history.undoStack;
    final redoStack = history.redoStack;

    return Container(
      width: 320,
      height: 400,
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: AppTheme.divider, width: 0.5),
        boxShadow: AppTheme.shadowLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.history_rounded, color: AppTheme.primaryLight, size: 16),
                const SizedBox(width: 8),
                const Text('Undo History', style: TextStyle(color: AppTheme.textMain, fontSize: 14, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('${undoStack.length} steps', style: const TextStyle(color: AppTheme.textMuted, fontSize: 10)),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18, color: AppTheme.textMuted),
                  onPressed: widget.onClose,
                  style: IconButton.styleFrom(padding: const EdgeInsets.all(4)),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: AppTheme.divider),

          // Undo stack (past actions)
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              children: [
                if (undoStack.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No actions yet', style: TextStyle(color: AppTheme.textMuted, fontSize: 12), textAlign: TextAlign.center),
                  )
                else
                  ...undoStack.asMap().entries.map((entry) {
                    final index = entry.key;
                    final cmd = entry.value;
                    final isLast = index == undoStack.length - 1;
                    return _HistoryTile(
                      description: cmd.description,
                      index: index,
                      isLast: isLast,
                      isUndo: true,
                      onTap: () {
                        // Undo to this point
                        while (controller.commandHistory.undoStack.length > index + 1) {
                          controller.undo();
                        }
                        controller.notifyListeners();
                      },
                    );
                  }),

                // Redo stack (future actions)
                if (redoStack.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Text('REDO', style: TextStyle(color: AppTheme.textMuted, fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 1.0)),
                  ),
                  ...redoStack.asMap().entries.map((entry) {
                    final index = entry.key;
                    final cmd = entry.value;
                    return _HistoryTile(
                      description: cmd.description,
                      index: index,
                      isLast: index == redoStack.length - 1,
                      isUndo: false,
                      onTap: () {
                        // v0.7.8: Redo pops from the TOP of the stack, so
                        // "redo to item i" needs (length - i) redos. The old
                        // code ran index+1 redos — tapping the FIRST item
                        // actually redid the LAST one.
                        while (controller.commandHistory.redoStack.length > index) {
                          controller.redo();
                        }
                        controller.notifyListeners();
                      },
                    );
                  }),
                ],
              ],
            ),
          ),

          // Footer actions
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: controller.canUndo
                        ? () {
                            controller.undo();
                            controller.notifyListeners();
                          }
                        : null,
                    icon: const Icon(Icons.undo_rounded, size: 16),
                    label: const Text('Undo'),
                    style: TextButton.styleFrom(foregroundColor: AppTheme.primaryLight),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: controller.canRedo
                        ? () {
                            controller.redo();
                            controller.notifyListeners();
                          }
                        : null,
                    icon: const Icon(Icons.redo_rounded, size: 16),
                    label: const Text('Redo'),
                    style: TextButton.styleFrom(foregroundColor: AppTheme.primaryLight),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: () {
                      controller.commandHistory.clear();
                      controller.notifyListeners();
                    },
                    icon: const Icon(Icons.delete_outline_rounded, size: 16),
                    label: const Text('Clear'),
                    style: TextButton.styleFrom(foregroundColor: AppTheme.error),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// History Tile Widget
// ============================================================

class _HistoryTile extends StatelessWidget {
  final String description;
  final int index;
  final bool isLast;
  final bool isUndo;
  final VoidCallback onTap;

  const _HistoryTile({
    required this.description,
    required this.index,
    required this.isLast,
    required this.isUndo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: isLast ? AppTheme.primary.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        ),
        child: Row(
          children: [
            // Timeline dot
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isUndo ? AppTheme.primaryLight : AppTheme.textMuted,
                shape: BoxShape.circle,
                boxShadow: isLast ? [BoxShadow(color: AppTheme.primaryLight, blurRadius: 4, spreadRadius: -1)] : null,
              ),
            ),
            const SizedBox(width: 8),
            // Index number
            Text(
              '${index + 1}',
              style: TextStyle(
                color: AppTheme.textMuted,
                fontSize: 9,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            // Description
            Expanded(
              child: Text(
                description,
                style: TextStyle(
                  color: isLast ? AppTheme.textMain : AppTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: isLast ? FontWeight.w600 : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isLast)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('CURRENT', style: TextStyle(color: AppTheme.primaryLight, fontSize: 7, fontWeight: FontWeight.w700)),
              ),
          ],
        ),
      ),
    );
  }
}
