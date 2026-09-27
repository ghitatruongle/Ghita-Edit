import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../controllers/editor_controller.dart';
import '../../models/clip.dart';
import '../theme/app_theme.dart';

/// v1.5.5-beta1: Beta tools.
///  - B1: GPU compositor runtime toggle (wgpu dispatch, default OFF) —
///    the choice is remembered across sessions, and the panel shows REAL
///    evidence (gpu_frames delta) that the GPU path actually ran.
///  - B3: adjustment-graph node chain (Brightness/Contrast/Saturation/
///    Exposure/Vibrance) for the selected clip — edits go through
///    [EditorController.setClipGraph] so they are UNDOABLE, persist in the
///    project file, and are mirrored into the engine by the fingerprint
///    resync (preview + export share the render path).
class BetaPanel extends StatefulWidget {
  final EditorController controller;

  const BetaPanel({super.key, required this.controller});

  @override
  State<BetaPanel> createState() => _BetaPanelState();
}

class _BetaPanelState extends State<BetaPanel> {
  int _newNodeType = 0;
  double _newNodeValue = 0.2;
  Map<String, dynamic> _gpuStats = {};
  int _gpuFramesAtOpen = 0;
  bool _gpuToggleRestored = false;

  /// v1.5.0-T6 coalescing: one slider drag = ONE undo entry.
  int? _dragGestureId;

  static const String _prefsGpuKey = 'beta.gpuEnabled';
  static const List<(int, String)> _nodeKinds = [
    (0, 'Brightness'),
    (1, 'Contrast'),
    (2, 'Saturation'),
    // v1.5.5-beta1 (T1.P3): Exposure + Vibrance join the chain.
    (3, 'Exposure'),
    (4, 'Vibrance'),
  ];

  @override
  void initState() {
    super.initState();
    _refreshGpuStats();
    // Baseline for the "GPU ACTIVE +N" badge: only frames dispatched while
    // THIS sheet is open count as evidence.
    _gpuFramesAtOpen = _gpuFrames;
    _restoreGpuPreference();
  }

  void _refreshGpuStats() {
    setState(() => _gpuStats = widget.controller.engineService.getGpuStats());
  }

  /// v1.5.5-beta1 (T3.P1): remember the GPU choice between sessions. The
  /// engine defaults to CPU, so a stored "on" is re-applied only when this
  /// build actually reports a GPU — never force-enable on a machine without
  /// an adapter.
  Future<void> _restoreGpuPreference() async {
    if (_gpuToggleRestored) return;
    _gpuToggleRestored = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getBool(_prefsGpuKey) ?? false;
      final engine = widget.controller.engineService;
      final available = _gpuStats['available'] == true;
      if (stored && available && !engine.gpuEnabled) {
        engine.setGpuEnabled(true);
        if (mounted) setState(() {});
      }
    } catch (_) {
      // Prefs unavailable (first run / locked profile) — stay on default.
    }
  }

  Future<void> _persistGpuPreference(bool on) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsGpuKey, on);
    } catch (_) {
      // Non-fatal: the toggle still works for this session.
    }
  }

  bool get _gpuAvailable => _gpuStats['available'] == true;

  int get _gpuFrames {
    final v = _gpuStats['gpu_frames'];
    return v is num ? v.toInt() : 0;
  }

  /// v1.5.5-beta1 (T3.P2): proof the GPU path ran while this sheet was
  /// open, not just "the switch is on".
  int get _gpuFramesDelta => (_gpuFrames - _gpuFramesAtOpen).clamp(0, 1 << 30);

  /// The selected clip, restricted to kinds the graph render path covers
  /// (video/image/overlay go through the decode branch; text/sticker/audio
  /// would silently ignore the chain).
  Clip? get _selectedRenderableClip {
    final clip = widget.controller.selectedClip;
    if (clip == null) return null;
    if (clip.type != ClipType.video &&
        clip.type != ClipType.image &&
        clip.type != ClipType.overlay) {
      return null;
    }
    return clip;
  }

  void _commitGraph(List<GraphNodeData> nodes, {bool drag = false}) {
    final clip = _selectedRenderableClip;
    if (clip == null) return;
    widget.controller.setClipGraph(clip.id, nodes,
        gestureId: drag ? _dragGestureId : null);
  }

  void _addNode() {
    final clip = _selectedRenderableClip;
    if (clip == null) return;
    _commitGraph([
      ...clip.graphNodes,
      GraphNodeData(type: _newNodeType, value: _newNodeValue),
    ]);
  }

  void _removeLast() {
    final clip = _selectedRenderableClip;
    if (clip == null || clip.graphNodes.isEmpty) return;
    _commitGraph(clip.graphNodes.sublist(0, clip.graphNodes.length - 1));
  }

  void _clearAll() {
    final clip = _selectedRenderableClip;
    if (clip == null || clip.graphNodes.isEmpty) return;
    _commitGraph(const []);
  }

  /// v1.5.5-beta1 (T3.P4): drag-reorder. Node ORDER changes the result
  /// (contrast→saturation ≠ saturation→contrast), so reordering is a real
  /// edit and goes through the same undoable path.
  void _reorder(int oldIndex, int newIndex) {
    final clip = _selectedRenderableClip;
    if (clip == null || clip.graphNodes.isEmpty) return;
    final list = List.of(clip.graphNodes);
    // onReorderItem already reports the destination index AFTER the moved
    // item is removed (the framework does the old onReorder's "-1" fixup).
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex.clamp(0, list.length), moved);
    _commitGraph(list);
  }

  @override
  Widget build(BuildContext context) {
    final engine = widget.controller.engineService;
    final clip = _selectedRenderableClip;
    final nodes = clip?.graphNodes ?? const <GraphNodeData>[];
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
      child: Material(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.science_rounded, size: 20, color: AppTheme.primaryLight),
                  const SizedBox(width: 8),
                  Text('Beta Tools', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryLight.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('v1.5.5-beta1', style: TextStyle(fontSize: 11, color: AppTheme.primaryLight)),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ------------------------------------------------------------
              // B1 — GPU compositor toggle
              // ------------------------------------------------------------
              Text('GPU Compositor (B1)',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Row(
                children: [
                  Switch(
                    value: _gpuAvailable && engine.gpuEnabled,
                    onChanged: _gpuAvailable
                        ? (v) {
                            engine.setGpuEnabled(v);
                            _persistGpuPreference(v);
                            widget.controller.seek(widget.controller.positionMs);
                            _refreshGpuStats();
                          }
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _gpuAvailable
                          ? 'GPU: ${_gpuStats['adapter'] ?? 'adapter'} — dispatch khi bật (Grayscale/Sepia/Invert, frame ≥512×256)'
                          : 'GPU không khả dụng trong build này (engine thiếu feature gpu hoặc không có adapter).',
                      style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                  ),
                  if (engine.gpuEnabled && _gpuFramesDelta > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('GPU ACTIVE +$_gpuFramesDelta',
                          style: const TextStyle(fontSize: 10, color: Colors.green)),
                    ),
                  IconButton(
                    tooltip: 'Refresh stats',
                    icon: const Icon(Icons.refresh, size: 18),
                    onPressed: () {
                      _gpuFramesAtOpen = _gpuFrames;
                      _refreshGpuStats();
                    },
                  ),
                ],
              ),
              Text(
                _gpuStats.isEmpty
                    ? 'No GPU telemetry'
                    : 'GPU frames: ${_gpuStats['gpu_frames'] ?? 0} • CPU fallbacks: ${_gpuStats['cpu_fallbacks'] ?? 0}',
                style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
              const Divider(height: 24),

              // ------------------------------------------------------------
              // B3 — Adjustment graph
              // ------------------------------------------------------------
              Row(
                children: [
                  Text('Adjustment Graph (B3)',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      clip == null
                          ? (widget.controller.selectedClip == null
                              ? 'Chọn một clip video/hình trên timeline để chỉnh graph.'
                              : 'Graph chỉ áp dụng cho clip video/hình/overlay (clip ${widget.controller.selectedClip!.type.name} không qua render path này).')
                          : 'Clip: ${clip.displayName}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy chain',
                    icon: const Icon(Icons.copy_all_outlined, size: 18),
                    onPressed: clip == null || nodes.isEmpty
                        ? null
                        : () => widget.controller.copySelectedGraph(),
                  ),
                  IconButton(
                    tooltip: 'Paste chain',
                    icon: const Icon(Icons.content_paste_go, size: 18),
                    onPressed: clip == null || !widget.controller.hasGraphClipboard
                        ? null
                        : () => widget.controller.pasteGraphToSelectedClip(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (nodes.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('Chưa có node — thêm Brightness/Contrast/Saturation/Exposure/Vibrance vào chain.',
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                ),
              // v1.5.5-beta1 (T3.P4): drag handle per row (ReorderableListView
              // inside the sheet's scroll view → shrinkWrap + no own scroll).
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: nodes.length,
                onReorderItem: _reorder,
                itemBuilder: (context, i) {
                  final node = nodes[i];
                  return Container(
                    key: ValueKey('graph_node_$i'),
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        ReorderableDragStartListener(
                          index: i,
                          child: const Icon(Icons.drag_handle, size: 18),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.divider),
                          ),
                          child: Text('${i + 1}. ${_nodeLabel(node.type)}',
                              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Slider(
                            value: node.value.clamp(-1.0, 1.0),
                            min: -1.0,
                            max: 1.0,
                            onChangeStart: (_) =>
                                _dragGestureId = DateTime.now().microsecondsSinceEpoch,
                            onChanged: (v) => _commitGraph(
                              [
                                for (var j = 0; j < nodes.length; j++)
                                  if (j == i)
                                    GraphNodeData(type: nodes[j].type, value: v)
                                  else
                                    nodes[j],
                              ],
                              drag: true,
                            ),
                            onChangeEnd: (_) => _dragGestureId = null,
                          ),
                        ),
                        Text(node.value.toStringAsFixed(2),
                            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                        IconButton(
                          tooltip: 'Remove last node',
                          icon: const Icon(Icons.remove_circle_outline, size: 18),
                          onPressed: nodes.isEmpty ? null : _removeLast,
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  DropdownButton<int>(
                    value: _newNodeType,
                    items: [
                      for (final (t, label) in _nodeKinds)
                        DropdownMenuItem(value: t, child: Text(label)),
                    ],
                    onChanged: (v) => setState(() => _newNodeType = v ?? 0),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 160,
                    child: Row(
                      children: [
                        Expanded(
                          child: Slider(
                            value: _newNodeValue,
                            min: -1.0,
                            max: 1.0,
                            onChanged: (v) => setState(() => _newNodeValue = v),
                          ),
                        ),
                        Text(_newNodeValue.toStringAsFixed(2),
                            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                      ],
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Add node',
                    icon: const Icon(Icons.add_circle, size: 22, color: AppTheme.primaryLight),
                    onPressed: clip == null ? null : _addNode,
                  ),
                  IconButton(
                    tooltip: 'Clear all nodes',
                    icon: const Icon(Icons.delete_sweep_outlined, size: 22),
                    onPressed: nodes.isEmpty ? null : _clearAll,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Thứ tự node CÓ ảnh hưởng (kéo handle để đổi) • Undo/redo được • lưu cùng project file • Ctrl+Shift+B mở panel này.',
                style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _nodeLabel(int type) {
    for (final (t, label) in _nodeKinds) {
      if (t == type) return label;
    }
    return 'Node $type';
  }
}
