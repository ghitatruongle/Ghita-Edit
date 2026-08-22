//! v1.5.0 T3 UI widgets:
//! - NumberFieldWithScrub (#18): math-expression numeric field with
//!   click-drag scrubbing (OpenCut-style).
//! - KeyframeGraphCard (#1): draggable keyframe curve editor with
//!   linear/step/bezier rendering.

import 'package:flutter/material.dart';

import '../../controllers/editor_controller.dart';
import '../../models/clip.dart';
import '../theme/app_theme.dart';

// ============================================================
// v1.5.0 T3 (#18): Number field with scrub + math expressions
// ============================================================

/// A compact numeric field that supports click-drag scrubbing and math
/// expressions: "+10", "-0.5", "*2", "25%", "/2" are applied relative to the
/// current value; plain numbers set the value directly.
class NumberFieldWithScrub extends StatefulWidget {
  const NumberFieldWithScrub({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onChangedStart,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final VoidCallback? onChangedStart;

  @override
  State<NumberFieldWithScrub> createState() => _NumberFieldWithScrubState();
}

class _NumberFieldWithScrubState extends State<NumberFieldWithScrub> {
  late final TextEditingController _text;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.value.toStringAsFixed(2));
  }

  @override
  void didUpdateWidget(covariant NumberFieldWithScrub old) {
    super.didUpdateWidget(old);
    if (!_editing && widget.value != old.value) {
      _text.text = widget.value.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  double _eval(String t, double base) {
    final v = double.tryParse(t.trim());
    if (v != null) return v.clamp(widget.min, widget.max).toDouble();
    double out = base;
    final s = t.trim();
    if (s.startsWith('+')) {
      out = base + (double.tryParse(s.substring(1)) ?? 0);
    } else if (s.startsWith('-') &&
        s.length > 1 &&
        double.tryParse(s.substring(1)) != null) {
      out = base - (double.tryParse(s.substring(1)) ?? 0);
    } else if (s.startsWith('*')) {
      out = base * (double.tryParse(s.substring(1)) ?? 1);
    } else if (s.startsWith('/')) {
      final d = double.tryParse(s.substring(1)) ?? 1;
      if (d != 0) out = base / d;
    } else if (s.endsWith('%')) {
      out = base +
          base * (double.tryParse(s.substring(0, s.length - 1)) ?? 0) / 100;
    }
    return out.clamp(widget.min, widget.max).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
              width: 50,
              child: Text(widget.label,
                  style:
                      const TextStyle(color: AppTheme.textMuted, fontSize: 10))),
          Expanded(
            child: GestureDetector(
              onHorizontalDragStart: (_) {
                widget.onChangedStart?.call();
                setState(() => _editing = true);
              },
              onHorizontalDragUpdate: (d) {
                final step = (widget.max - widget.min) / 100;
                widget.onChanged((widget.value + d.delta.dx * step)
                    .clamp(widget.min, widget.max)
                    .toDouble());
              },
              onHorizontalDragEnd: (_) => setState(() => _editing = false),
              child: TextField(
                controller: _text,
                style: const TextStyle(
                    color: AppTheme.textMain,
                    fontSize: 11,
                    fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  isDense: true,
                  isCollapsed: true,
                  contentPadding:
                      EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                  border: OutlineInputBorder(),
                ),
                onTap: () => setState(() => _editing = true),
                onSubmitted: (t) {
                  setState(() => _editing = false);
                  widget.onChanged(_eval(t, widget.value));
                  _text.text = widget.value.toStringAsFixed(2);
                },
                onChanged: (t) {
                  final v = double.tryParse(t.trim());
                  if (v != null) {
                    widget.onChanged(v.clamp(widget.min, widget.max).toDouble());
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// v1.5.0 T3 (#1): Keyframe graph editor (bezier-capable curve)
// ============================================================

/// Property options for the graph editor (engine enum ids).
const kGraphProperties = <(int, String)>[
  (0, 'Opacity'),
  (1, 'Offset X'),
  (2, 'Scale'),
  (4, 'Filter'),
];

class KeyframeGraphCard extends StatefulWidget {
  const KeyframeGraphCard(
      {super.key, required this.controller, required this.clip});

  final EditorController controller;
  final Clip clip;

  @override
  State<KeyframeGraphCard> createState() => _KeyframeGraphCardState();
}

class _KeyframeGraphCardState extends State<KeyframeGraphCard> {
  int _property = 0;

  List<KeyframeData> get _kfs => widget.clip.keyframes
      .where((k) => k.property == _property)
      .toList()
    ..sort((a, b) => a.timeMs.compareTo(b.timeMs));

  @override
  Widget build(BuildContext context) {
    final clip = widget.clip;
    final kfs = _kfs;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.timeline_rounded,
                  color: AppTheme.primaryLight, size: 14),
              const SizedBox(width: 6),
              // Flexible so the narrow-inspector (260px) regression test
              // cannot overflow — the title ellipsizes instead.
              const Flexible(
                child: Text('KEYFRAME GRAPH',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: AppTheme.textMain,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5)),
              ),
              const SizedBox(width: 6),
              DropdownButton<int>(
                value: _property,
                isDense: true,
                underline: const SizedBox.shrink(),
                items: [
                  for (final (id, name) in kGraphProperties)
                    DropdownMenuItem(
                        value: id,
                        child: Text(name, style: const TextStyle(fontSize: 11))),
                ],
                onChanged: (v) => setState(() => _property = v ?? 0),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Double-tap to add · drag points to edit · right-click to delete',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 9),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 120,
            width: double.infinity,
            child: GestureDetector(
              onDoubleTapDown: (d) => _addAt(d.localPosition),
              onSecondaryTapDown: (d) => _deleteAt(d.localPosition),
              onPanStart: (d) => _dragAt(d.localPosition),
              onPanUpdate: (d) => _dragAt(d.localPosition),
              child: CustomPaint(
                painter: KeyframeGraphPainter(
                  keyframes: kfs,
                  clipStartMs: clip.timelineStartMs,
                  clipDurationMs: clip.durationMs,
                  property: _property,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  (double, double) _range() {
    return switch (_property) {
      1 => (-1.0, 1.0),
      2 => (0.1, 4.0),
      4 => (0.0, 1.0),
      _ => (0.0, 1.0),
    };
  }

  void _addAt(Offset local) {
    final (minV, maxV) = _range();
    final size = context.size ?? const Size(300, 120);
    final t = (local.dx / size.width).clamp(0.0, 1.0);
    final v = (1.0 - local.dy / size.height).clamp(0.0, 1.0);
    final timeMs =
        widget.clip.timelineStartMs + (t * widget.clip.durationMs).round();
    final value = minV + v * (maxV - minV);
    widget.controller.upsertKeyframe(
        widget.clip.id,
        KeyframeData(
            timeMs: timeMs,
            value: value,
            property: _property,
            interpolation: 0));
  }

  void _dragAt(Offset local) {
    final (minV, maxV) = _range();
    final size = context.size ?? const Size(300, 120);
    final t = (local.dx / size.width).clamp(0.0, 1.0);
    final v = (1.0 - local.dy / size.height).clamp(0.0, 1.0);
    final kfs = _kfs;
    if (kfs.isEmpty) return;
    final timeMs =
        widget.clip.timelineStartMs + (t * widget.clip.durationMs).round();
    // Nearest keyframe by time; move it (keep first/last anchors).
    final target = kfs
        .reduce((a, b) =>
            (a.timeMs - timeMs).abs() < (b.timeMs - timeMs).abs() ? a : b);
    widget.controller.upsertKeyframe(
        widget.clip.id,
        KeyframeData(
            timeMs: target.timeMs,
            value: (minV + v * (maxV - minV)).clamp(minV, maxV).toDouble(),
            property: _property,
            interpolation: target.interpolation,
            cp1x: target.cp1x,
            cp1y: target.cp1y,
            cp2x: target.cp2x,
            cp2y: target.cp2y));
  }

  void _deleteAt(Offset local) {
    final size = context.size ?? const Size(300, 120);
    final t = local.dx / size.width;
    final hit = _kfs
        .where((k) =>
            ((k.timeMs - widget.clip.timelineStartMs) /
                        widget.clip.durationMs -
                    t)
                .abs() <
            0.05)
        .toList();
    if (hit.isNotEmpty) {
      widget.controller.removeKeyframe(widget.clip.id, hit.first.timeMs, _property);
    }
  }
}

class KeyframeGraphPainter extends CustomPainter {
  KeyframeGraphPainter({
    required this.keyframes,
    required this.clipStartMs,
    required this.clipDurationMs,
    required this.property,
  });

  final List<KeyframeData> keyframes;
  final int clipStartMs;
  final int clipDurationMs;
  final int property;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = AppTheme.surface.withValues(alpha: 0.6);
    canvas.drawRect(Offset.zero & size, bg);

    final grid = Paint()
      ..color = AppTheme.divider.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (int i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final (minV, maxV) = switch (property) {
      1 => (-1.0, 1.0),
      2 => (0.1, 4.0),
      4 => (0.0, 1.0),
      _ => (0.0, 1.0),
    };
    Offset pt(KeyframeData k) => Offset(
          ((k.timeMs - clipStartMs) / clipDurationMs) * size.width,
          size.height - ((k.value - minV) / (maxV - minV)) * size.height,
        );

    final curve = Paint()
      ..color = AppTheme.primaryLight
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    for (int i = 0; i + 1 < keyframes.length; i++) {
      final a = keyframes[i];
      final b = keyframes[i + 1];
      if (a.interpolation == 1) {
        canvas.drawLine(pt(a), Offset(pt(b).dx, pt(a).dy), curve);
        canvas.drawLine(Offset(pt(b).dx, pt(a).dy), pt(b), curve);
      } else if (a.interpolation == 2) {
        final p0 = pt(a);
        final p3 = pt(b);
        final c1 = Offset(
            p0.dx + a.cp1x * (p3.dx - p0.dx),
            p0.dy - a.cp1y * (p0.dy - p3.dy));
        final c2 = Offset(
            p0.dx + a.cp2x * (p3.dx - p0.dx),
            p0.dy - a.cp2y * (p0.dy - p3.dy));
        final path = Path()
          ..moveTo(p0.dx, p0.dy)
          ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p3.dx, p3.dy);
        canvas.drawPath(path, curve);
      } else {
        canvas.drawLine(pt(a), pt(b), curve);
      }
    }

    final pointFill = Paint()..color = AppTheme.accent;
    for (final k in keyframes) {
      canvas.drawCircle(pt(k), 3.5, pointFill);
    }
  }

  @override
  bool shouldRepaint(covariant KeyframeGraphPainter oldDelegate) {
    return oldDelegate.keyframes != keyframes ||
        oldDelegate.clipDurationMs != clipDurationMs ||
        oldDelegate.property != property;
  }
}
