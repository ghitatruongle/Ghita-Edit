import 'package:flutter/material.dart';
import '../../controllers/editor_controller.dart';
import '../../models/clip.dart';
import '../theme/app_theme.dart';

/// v1.5.5-demo: Beta tools.
///  - B1: GPU compositor runtime toggle (wgpu dispatch, default OFF).
///  - B3: adjustment-graph node chain (Brightness/Contrast/Saturation) for
///       the selected clip — edits go through [EditorController.setClipGraph]
///       so they are UNDOABLE and persist in the project file; the deferred
///       fingerprint resync mirrors the chain into the engine (preview +
///       export share the render path).
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

  /// v1.5.0-T6 coalescing: one slider drag = ONE undo entry.
  int? _dragGestureId;

  static const List<(int, String)> _nodeKinds = [
    (0, 'Brightness'),
    (1, 'Contrast'),
    (2, 'Saturation'),
  ];

  @override
  void initState() {
    super.initState();
    _refreshGpuStats();
  }

  void _refreshGpuStats() {
    setState(() => _gpuStats = widget.controller.engineService.getGpuStats());
  }

  bool get _gpuAvailable {
    final v = _gpuStats['available'];
    return v is bool && v;
  }

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
                    child: Text('v1.5.5-demo', style: TextStyle(fontSize: 11, color: AppTheme.primaryLight)),
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
                            // Repaint immediately — the engine-side timeline
                            // hash folds in the GPU state, so the next render
                            // is guaranteed fresh.
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
                  IconButton(
                    tooltip: 'Refresh stats',
                    icon: const Icon(Icons.refresh, size: 18),
                    onPressed: _refreshGpuStats,
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
                ],
              ),
              const SizedBox(height: 8),
              if (nodes.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('Chưa có node — thêm Brightness/Contrast/Saturation vào chain.',
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                ),
              for (var i = 0; i < nodes.length; i++) ...[
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.divider),
                      ),
                      child: Text('${i + 1}. ${_nodeLabel(nodes[i].type)}',
                          style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Slider(
                        value: nodes[i].value.clamp(-1.0, 1.0),
                        min: -1.0,
                        max: 1.0,
                        onChangeStart: (_) =>
                            _dragGestureId = DateTime.now().microsecondsSinceEpoch,
                        onChanged: (v) => _commitGraph(
                          [
                            for (var j = 0; j < nodes.length; j++)
                              if (j == i) GraphNodeData(type: nodes[j].type, value: v) else nodes[j],
                          ],
                          drag: true,
                        ),
                        onChangeEnd: (_) => _dragGestureId = null,
                      ),
                    ),
                    Text(nodes[i].value.toStringAsFixed(2),
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    IconButton(
                      tooltip: 'Remove last node',
                      icon: const Icon(Icons.remove_circle_outline, size: 18),
                      onPressed: nodes.isEmpty ? null : _removeLast,
                    ),
                  ],
                ),
              ],
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
                    onPressed: nodes.isEmpty ? _clearAll : null,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Nodes chain IN ORDER sau color correction — preview và export dùng cùng pipeline. Undo/redo được, lưu cùng project file.',
                style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
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

  String _nodeLabel(int type) {
    for (final (t, label) in _nodeKinds) {
      if (t == type) return label;
    }
    return 'Node $type';
  }
}
