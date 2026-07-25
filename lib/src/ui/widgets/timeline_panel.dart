import 'package:flutter/material.dart';
import '../../controllers/editor_controller.dart';
import '../../models/clip.dart' as models;
import '../../models/track.dart';
import '../theme/app_theme.dart';

class TimelinePanel extends StatefulWidget {
  final EditorController controller;

  const TimelinePanel({super.key, required this.controller});

  @override
  State<TimelinePanel> createState() => _TimelinePanelState();
}

class _TimelinePanelState extends State<TimelinePanel> {
  double _zoomScale = 1.0;
  String? _draggingClipId;
  int? _dragStartMs;

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final totalDurationSec = ctrl.durationMs / 1000.0;
    final currentPosSec = ctrl.positionMs / 1000.0;

    return Container(
      color: AppTheme.card,
      child: Column(
        children: [
          // Timeline Toolbar
          _buildToolbar(ctrl, currentPosSec),

          // Interactive Timeline Area
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final timelineWidth = constraints.maxWidth - 120;
                final pxPerSec = (timelineWidth / (totalDurationSec > 0 ? totalDurationSec : 60)) * _zoomScale;
                final playheadX = currentPosSec * pxPerSec;

                return Row(
                  children: [
                    // Left Track Headers
                    SizedBox(
                      width: 120,
                      child: Column(
                        children: [
                          _buildTrackHeaderLabel("Timecode", Icons.access_time, isRuler: true),
                          ...ctrl.tracks.map((track) => Expanded(
                            child: _buildTrackHeader(track, ctrl),
                          )),
                        ],
                      ),
                    ),

                    // Right Tracks Canvas
                    Expanded(
                      child: GestureDetector(
                        onHorizontalDragUpdate: (details) {
                          if (_draggingClipId != null) return; // Don't seek while dragging
                          final newSec = (details.localPosition.dx / pxPerSec).clamp(0.0, totalDurationSec);
                          ctrl.seek((newSec * 1000).toInt());
                        },
                        onTapDown: (details) {
                          final newSec = (details.localPosition.dx / pxPerSec).clamp(0.0, totalDurationSec);
                          ctrl.seek((newSec * 1000).toInt());
                        },
                        child: Stack(
                          children: [
                            Column(
                              children: [
                                // Time Ruler
                                Container(
                                  height: 28,
                                  color: AppTheme.surface,
                                  child: CustomPaint(
                                    size: Size(constraints.maxWidth, 28),
                                    painter: TimelineRulerPainter(
                                      pxPerSec: pxPerSec,
                                      totalDurationSec: totalDurationSec,
                                    ),
                                  ),
                                ),

                                // Track Lanes with real clips
                                ...ctrl.tracks.map((track) => Expanded(
                                  child: _buildTrackLane(track, ctrl, pxPerSec, totalDurationSec),
                                )),
                              ],
                            ),

                            // Playhead
                            Positioned(
                              left: playheadX.clamp(0, constraints.maxWidth - 120),
                              top: 0,
                              bottom: 0,
                              child: Container(
                                width: 2,
                                color: Colors.redAccent,
                                child: Stack(
                                  clipBehavior: Clip.none, // Flutter's Clip enum
                                  children: [
                                    Positioned(
                                      top: -2,
                                      left: -5,
                                      child: Container(
                                        width: 12,
                                        height: 12,
                                        decoration: const BoxDecoration(
                                          color: Colors.redAccent,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(EditorController ctrl, double currentPosSec) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.divider)),
      ),
      child: Row(
        children: [
          // Split button
          _toolButton(Icons.content_cut, "Split at Playhead (S)", AppTheme.accent, ctrl.splitAtPlayhead),
          _toolButton(Icons.delete_outline, "Delete Selected (Del)", Colors.redAccent, ctrl.deleteSelectedClip),

          const VerticalDivider(color: AppTheme.divider, indent: 8, endIndent: 8),

          // Zoom controls
          IconButton(
            icon: const Icon(Icons.zoom_out, size: 18, color: AppTheme.textMuted),
            onPressed: () => setState(() => _zoomScale = (_zoomScale - 0.2).clamp(0.4, 4.0)),
          ),
          Text(
            '${(_zoomScale * 100).toInt()}%',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
          ),
          IconButton(
            icon: const Icon(Icons.zoom_in, size: 18, color: AppTheme.textMuted),
            onPressed: () => setState(() => _zoomScale = (_zoomScale + 0.2).clamp(0.4, 4.0)),
          ),

          const Spacer(),

          // Status info
          Text(
            '${ctrl.project.allClips.length} clips • ${(ctrl.durationMs / 1000).toStringAsFixed(1)}s',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
          ),
          const SizedBox(width: 12),
          const Icon(Icons.grid_on, size: 18, color: AppTheme.primaryLight),
          const SizedBox(width: 4),
          const Text("Snap ON", style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _toolButton(IconData icon, String tooltip, Color color, VoidCallback onPressed) {
    return IconButton(
      icon: Icon(icon, size: 18, color: color),
      tooltip: tooltip,
      onPressed: onPressed,
    );
  }

  Widget _buildTrackHeader(Track track, EditorController ctrl) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: AppTheme.card,
        border: Border(
          right: BorderSide(color: AppTheme.divider),
          bottom: BorderSide(color: AppTheme.divider),
        ),
      ),
      child: Row(
        children: [
          Icon(_iconForTrackType(track.type), size: 14, color: AppTheme.textMuted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              track.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.textMain, fontSize: 11),
            ),
          ),
          // Mute/Lock buttons
          GestureDetector(
            onTap: () => setState(() => track.isMuted = !track.isMuted),
            child: Icon(
              track.isMuted ? Icons.volume_off : Icons.volume_up,
              size: 12,
              color: track.isMuted ? Colors.redAccent : AppTheme.textMuted,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => setState(() => track.isLocked = !track.isLocked),
            child: Icon(
              track.isLocked ? Icons.lock : Icons.lock_open,
              size: 12,
              color: track.isLocked ? Colors.amberAccent : AppTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackLane(Track track, EditorController ctrl, double pxPerSec, double totalDurationSec) {
    final laneColor = _colorForTrackType(track.type);

    return Container(
      decoration: BoxDecoration(
        color: laneColor.withOpacity(0.05),
        border: const Border(bottom: BorderSide(color: AppTheme.divider)),
      ),
      child: Stack(
        children: [
          // Render all clips in this track
          ...track.clips.map((clip) => _buildClipWidget(clip, track, ctrl, pxPerSec)),

          // Show "empty track" hint if no clips
          if (track.clips.isEmpty)
            Center(
              child: Text(
                "Drop media here or import file",
                style: TextStyle(color: AppTheme.textMuted.withOpacity(0.5), fontSize: 10),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildClipWidget(models.Clip clip, Track track, EditorController ctrl, double pxPerSec) {
    final leftPx = (clip.timelineStartMs / 1000.0) * pxPerSec;
    final widthPx = (clip.durationMs / 1000.0) * pxPerSec;
    final clipColor = _colorForClipType(clip.type);

    return Positioned(
      left: leftPx,
      width: widthPx.clamp(20, double.infinity),
      top: 3,
      bottom: 3,
      child: GestureDetector(
        onTap: () => ctrl.selectClip(clip.id),
        onHorizontalDragStart: (_) {
          _draggingClipId = clip.id;
          _dragStartMs = clip.timelineStartMs; // Capture BEFORE mutation
          ctrl.selectClip(clip.id);
        },
        onHorizontalDragUpdate: (details) {
          if (track.isLocked) return;
          final deltaMs = (details.delta.dx / pxPerSec * 1000).toInt();
          final newStart = (clip.timelineStartMs + deltaMs).clamp(0, ctrl.durationMs);
          clip.timelineStartMs = newStart;
          setState(() {});
        },
        onHorizontalDragEnd: (_) {
          if (_draggingClipId != null && _dragStartMs != null) {
            // Only record command if position actually changed
            if (clip.timelineStartMs != _dragStartMs) {
              ctrl.moveClipFrom(track.id, clip.id, _dragStartMs!, clip.timelineStartMs);
            }
            _draggingClipId = null;
            _dragStartMs = null;
          }
        },
        child: Container(
          decoration: BoxDecoration(
            color: clip.isSelected ? clipColor.withOpacity(0.9) : clipColor.withOpacity(0.7),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: clip.isSelected ? Colors.white : clipColor,
              width: clip.isSelected ? 2 : 1,
            ),
            boxShadow: clip.isSelected ? [
              BoxShadow(color: clipColor.withOpacity(0.4), blurRadius: 8),
            ] : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              Icon(_iconForClipType(clip.type), size: 12, color: Colors.white),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  clip.displayName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (clip.filterType > 0)
                const Icon(Icons.auto_fix_high, size: 10, color: Colors.amberAccent),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrackHeaderLabel(String title, IconData icon, {bool isRuler = false}) {
    return Container(
      height: isRuler ? 28 : double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: isRuler ? AppTheme.surface : AppTheme.card,
        border: const Border(
          right: BorderSide(color: AppTheme.divider),
          bottom: BorderSide(color: AppTheme.divider),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: isRuler ? AppTheme.accent : AppTheme.textMuted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isRuler ? AppTheme.accent : AppTheme.textMain,
                fontSize: 11,
                fontWeight: isRuler ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconForTrackType(TrackType type) {
    switch (type) {
      case TrackType.video: return Icons.videocam;
      case TrackType.overlay: return Icons.subtitles;
      case TrackType.audio: return Icons.graphic_eq;
    }
  }

  Color _colorForTrackType(TrackType type) {
    switch (type) {
      case TrackType.video: return AppTheme.primary;
      case TrackType.overlay: return Colors.amber;
      case TrackType.audio: return AppTheme.accent;
    }
  }

  Color _colorForClipType(models.ClipType type) {
    switch (type) {
      case models.ClipType.video: return AppTheme.primary;
      case models.ClipType.audio: return AppTheme.accent;
      case models.ClipType.image: return Colors.teal;
      case models.ClipType.text: return Colors.amber;
      case models.ClipType.overlay: return Colors.orange;
    }
  }

  IconData _iconForClipType(models.ClipType type) {
    switch (type) {
      case models.ClipType.video: return Icons.movie;
      case models.ClipType.audio: return Icons.music_note;
      case models.ClipType.image: return Icons.image;
      case models.ClipType.text: return Icons.title;
      case models.ClipType.overlay: return Icons.layers;
    }
  }
}

// Custom Painter for Timeline Ruler
class TimelineRulerPainter extends CustomPainter {
  final double pxPerSec;
  final double totalDurationSec;

  TimelineRulerPainter({required this.pxPerSec, required this.totalDurationSec});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.textMuted.withOpacity(0.5)
      ..strokeWidth = 1.0;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    int stepSec = 5;
    if (pxPerSec < 8) stepSec = 10;
    if (pxPerSec < 4) stepSec = 30;

    for (int s = 0; s <= totalDurationSec; s += stepSec) {
      double x = s * pxPerSec;
      if (x > size.width) break;

      canvas.drawLine(Offset(x, size.height - 8), Offset(x, size.height), paint);

      textPainter.text = TextSpan(
        text: '${s}s',
        style: const TextStyle(color: AppTheme.textMuted, fontSize: 9),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x + 2, 4));
    }
  }

  @override
  bool shouldRepaint(covariant TimelineRulerPainter oldDelegate) {
    return oldDelegate.pxPerSec != pxPerSec || oldDelegate.totalDurationSec != totalDurationSec;
  }
}
