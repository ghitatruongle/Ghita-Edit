import 'package:flutter/material.dart';
import '../../controllers/editor_controller.dart';
import '../theme/app_theme.dart';

class TimelinePanel extends StatefulWidget {
  final EditorController controller;

  const TimelinePanel({super.key, required this.controller});

  @override
  State<TimelinePanel> createState() => _TimelinePanelState();
}

class _TimelinePanelState extends State<TimelinePanel> {
  double _zoomScale = 1.0; // pixels per second ratio factor

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final totalDurationSec = ctrl.durationMs / 1000.0;
    final currentPosSec = ctrl.positionMs / 1000.0;

    return Container(
      color: AppTheme.card,
      child: Column(
        children: [
          // Timeline Control Toolbar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: const BoxDecoration(
              color: AppTheme.surface,
              border: Border(bottom: BorderSide(color: AppTheme.divider)),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.content_cut, size: 18, color: AppTheme.accent),
                  tooltip: "Split Clip at Playhead",
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Split clip at ${currentPosSec.toStringAsFixed(2)}s')),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                  tooltip: "Delete Selected Clip",
                  onPressed: () {},
                ),
                const VerticalDivider(color: AppTheme.divider, indent: 8, endIndent: 8),
                IconButton(
                  icon: const Icon(Icons.zoom_out, size: 18, color: AppTheme.textMuted),
                  onPressed: () => setState(() => _zoomScale = (_zoomScale - 0.2).clamp(0.5, 3.0)),
                ),
                Text(
                  '${(_zoomScale * 100).toInt()}%',
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                ),
                IconButton(
                  icon: const Icon(Icons.zoom_in, size: 18, color: AppTheme.textMuted),
                  onPressed: () => setState(() => _zoomScale = (_zoomScale + 0.2).clamp(0.5, 3.0)),
                ),
                const Spacer(),
                const Icon(Icons.grid_on, size: 18, color: AppTheme.primaryLight),
                const SizedBox(width: 4),
                const Text("Snap ON", style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
              ],
            ),
          ),

          // Interactive Timeline Area
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final timelineWidth = constraints.maxWidth - 120; // 120px for Track Headers
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
                          Expanded(child: _buildTrackHeaderLabel("Video Track 1", Icons.videocam)),
                          Expanded(child: _buildTrackHeaderLabel("Text / Overlay", Icons.subtitles)),
                          Expanded(child: _buildTrackHeaderLabel("Audio Track 1", Icons.graphic_eq)),
                        ],
                      ),
                    ),

                    // Right Tracks Canvas
                    Expanded(
                      child: GestureDetector(
                        onHorizontalDragUpdate: (details) {
                          final newSec = (details.localPosition.dx / pxPerSec).clamp(0, totalDurationSec);
                          ctrl.seek((newSec * 1000).toInt());
                        },
                        onTapDown: (details) {
                          final newSec = (details.localPosition.dx / pxPerSec).clamp(0, totalDurationSec);
                          ctrl.seek((newSec * 1000).toInt());
                        },
                        child: Stack(
                          children: [
                            Column(
                              children: [
                                // Time Ruler Ticks
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

                                // Video Track Lane
                                Expanded(
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF1B1D2C),
                                      border: Border(bottom: BorderSide(color: AppTheme.divider)),
                                    ),
                                    child: Stack(
                                      children: [
                                        Positioned(
                                          left: 0,
                                          width: totalDurationSec * pxPerSec * 0.8,
                                          top: 4,
                                          bottom: 4,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: AppTheme.primary.withOpacity(0.8),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: AppTheme.primaryLight),
                                            ),
                                            padding: const EdgeInsets.symmetric(horizontal: 8),
                                            child: Row(
                                              children: [
                                                const Icon(Icons.movie, size: 14, color: Colors.white),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: Text(
                                                    ctrl.currentMediaName,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
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

                                // Overlay Track Lane
                                Expanded(
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF181A25),
                                      border: Border(bottom: BorderSide(color: AppTheme.divider)),
                                    ),
                                    child: Stack(
                                      children: [
                                        Positioned(
                                          left: 10 * pxPerSec,
                                          width: 15 * pxPerSec,
                                          top: 4,
                                          bottom: 4,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: Colors.amber.shade800.withOpacity(0.8),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: Colors.amberAccent),
                                            ),
                                            padding: const EdgeInsets.symmetric(horizontal: 8),
                                            child: const Center(
                                              child: Text(
                                                "Title Overlay",
                                                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                // Audio Track Lane
                                Expanded(
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF151722),
                                    ),
                                    child: Stack(
                                      children: [
                                        Positioned(
                                          left: 0,
                                          width: totalDurationSec * pxPerSec,
                                          top: 4,
                                          bottom: 4,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: AppTheme.accent.withOpacity(0.3),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: AppTheme.accent),
                                            ),
                                            child: CustomPaint(
                                              painter: AudioWaveformPainter(color: AppTheme.accent),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            // Red Interactive Playhead Indicator Line
                            Positioned(
                              left: playheadX,
                              top: 0,
                              bottom: 0,
                              child: Container(
                                width: 2,
                                color: Colors.redAccent,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Positioned(
                                      top: -4,
                                      left: -5,
                                      child: Icon(Icons.arrow_drop_down, color: Colors.redAccent, size: 14),
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

    int stepSec = 5; // Tick every 5 seconds
    if (pxPerSec < 10) stepSec = 10;

    for (int s = 0; s <= totalDurationSec; s += stepSec) {
      double x = s * pxPerSec;
      if (x > size.width) break;

      // Draw tick mark
      canvas.drawLine(Offset(x, size.height - 8), Offset(x, size.height), paint);

      // Draw label
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

// Custom Painter for Audio Waveform
class AudioWaveformPainter extends CustomPainter {
  final Color color;

  AudioWaveformPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.7)
      ..strokeWidth = 1.5;

    double midY = size.height / 2;
    for (double x = 0; x < size.width; x += 4) {
      double h = ((x * 0.17) % 1.0) * (size.height * 0.7);
      canvas.drawLine(Offset(x, midY - h / 2), Offset(x, midY + h / 2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
