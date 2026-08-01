import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'dart:math';
import '../../controllers/editor_controller.dart';
import '../../controllers/engine_service.dart';
import '../theme/app_theme.dart';

// ============================================================
// PreviewPlayer — v0.7.0 Enhanced
// ============================================================

class PreviewPlayer extends StatefulWidget {
  final EditorController controller;

  const PreviewPlayer({super.key, required this.controller});

  @override
  State<PreviewPlayer> createState() => _PreviewPlayerState();
}

class _PreviewPlayerState extends State<PreviewPlayer> {
  ui.Image? _currentFrameImage;

  // v0.7.0: Split view
  bool _splitView = false;
  double _splitPosition = 0.5;

  // v0.7.0: Safe area guides
  bool _showSafeArea = false;
  bool _showGrid = false;
  bool _showCrosshair = false;

  // v0.7.0: Mini controls visibility
  bool _showMiniControls = true;
  Timer? _miniControlsTimer;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerUpdate);
    _startMiniControlsTimer();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerUpdate);
    _miniControlsTimer?.cancel();
    _currentFrameImage?.dispose();
    super.dispose();
  }

  void _startMiniControlsTimer() {
    _miniControlsTimer?.cancel();
    _miniControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && widget.controller.isPlaying) {
        setState(() => _showMiniControls = false);
      }
    });
  }

  void _resetMiniControlsTimer() {
    setState(() => _showMiniControls = true);
    _startMiniControlsTimer();
  }

  void _onControllerUpdate() {
    final bytes = widget.controller.frameBytes;
    if (bytes != null && bytes.isNotEmpty) {
      ui.decodeImageFromPixels(
        bytes,
        EngineService.renderWidth,
        EngineService.renderHeight,
        ui.PixelFormat.rgba8888,
        (ui.Image image) {
          if (mounted) {
            setState(() {
              _currentFrameImage?.dispose();
              _currentFrameImage = image;
            });
          } else {
            image.dispose();
          }
        },
      );
    }

    // Only update mini-controls visibility state — don't reset timer here
    // (timer reset only happens on user interaction via _resetMiniControlsTimer)
    if (mounted && _showMiniControls && widget.controller.isPlaying) {
      // Keep timer running; don't touch it here
    }
  }

  double _playbackSpeed = 1.0;

  void _changeSpeed(double newSpeed) {
    setState(() { _playbackSpeed = newSpeed; });
    widget.controller.engineService.setPlaybackRate(newSpeed);
    debugPrint('Playback speed: ${newSpeed}x');
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;

    return Container(
      color: AppTheme.surface,
      child: Column(
        children: [
          // Player Screen Canvas
          Expanded(
            child: LayoutBuilder(
              builder: (context, canvasConstraints) {
                final canvasWidth = canvasConstraints.maxWidth;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    // Main canvas
                    Container(
                      margin: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                        boxShadow: AppTheme.shadowLg,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: _currentFrameImage != null
                              ? GestureDetector(
                                  onTap: _resetMiniControlsTimer,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      // v0.7.0: Split view
                                      if (_splitView)
                                        Row(
                                          children: [
                                            // Before side (no filter)
                                            Expanded(
                                              flex: (_splitPosition * 100).toInt(),
                                              child: RawImage(
                                                image: _currentFrameImage,
                                                fit: BoxFit.contain,
                                              ),
                                            ),
                                            // Divider line
                                            Container(
                                              width: 2,
                                              color: Colors.white,
                                            ),
                                            // After side (with filter)
                                            Expanded(
                                              flex: 100 - (_splitPosition * 100).toInt(),
                                              child: RawImage(
                                                image: _currentFrameImage,
                                                fit: BoxFit.contain,
                                              ),
                                            ),
                                          ],
                                        )
                                      else
                                        RawImage(
                                          image: _currentFrameImage,
                                          fit: BoxFit.contain,
                                        ),

                                      // v0.7.0: Safe area guides overlay
                                      if (_showSafeArea) _buildSafeAreaOverlay(),

                                      // v0.7.0: Grid overlay (rule of thirds)
                                      if (_showGrid) _buildGridOverlay(),

                                      // v0.7.0: Crosshair
                                      if (_showCrosshair) _buildCrosshairOverlay(),

                                      // v0.7.0: Split view divider handle
                                      if (_splitView)
                                        Positioned(
                                          left: _splitPosition * canvasWidth - 2,
                                          top: 0,
                                          bottom: 0,
                                          child: GestureDetector(
                                            onHorizontalDragUpdate: (details) {
                                              setState(() {
                                                _splitPosition = (details.localPosition.dx / canvasWidth).clamp(0.05, 0.95);
                                              });
                                            },
                                            child: Container(
                                              width: 4,
                                              color: Colors.white,
                                              child: const Center(
                                                child: Icon(Icons.unfold_more, color: Colors.white, size: 16),
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                )
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: AppTheme.gradientDecoration(
                                        radius: AppTheme.radiusLg,
                                        colors: const [AppTheme.primary, AppTheme.accent],
                                      ),
                                      child: Icon(Icons.movie_edit, color: Colors.white, size: 24),
                                    ),
                                    const SizedBox(height: 16),
                                    // v0.7.8: Spinner only while the engine is actually
                                    // rendering; in Demo Mode (no native engine) show an
                                    // honest message instead of spinning forever.
                                    if (ctrl.isEngineReady) ...[
                                      const CircularProgressIndicator(color: AppTheme.accent, strokeWidth: 2),
                                      const SizedBox(height: 16),
                                      const Text(
                                        'Rendering C++ Native Canvas...',
                                        style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                                      ),
                                    ] else ...[
                                      const Icon(Icons.info_outline_rounded, color: AppTheme.warning, size: 28),
                                      const SizedBox(height: 8),
                                      const Text(
                                        'Demo Mode — native engine not available',
                                        style: TextStyle(
                                          color: AppTheme.textMuted,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      const Text(
                                        'Video preview & export need the native engine.',
                                        style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                                      ),
                                    ],
                                  ],
                                ),
                            ),
                        ),
                    ),

                // v0.7.0: Floating playback badge
                Positioned(
                  top: 16,
                  right: 16,
                  child: AnimatedOpacity(
                    opacity: _showMiniControls ? 1.0 : 0.0,
                    duration: AppTheme.durationFast,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.divider),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: ctrl.isPlaying ? AppTheme.success : AppTheme.warning,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            ctrl.isPlaying ? 'PLAYING' : 'PAUSED',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // v0.7.0: Mini controls overlay (when mouse inactive)
                if (_showMiniControls && _currentFrameImage != null)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: AnimatedContainer(
                      duration: AppTheme.durationNormal,
                      curve: AppTheme.curveStandard,
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.6),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              ctrl.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                            onPressed: () {
                              ctrl.togglePlayPause();
                              _resetMiniControlsTimer();
                            },
                          ),
                          Expanded(
                            child: Slider(
                              value: ctrl.positionMs.clamp(0, ctrl.durationMs).toDouble(),
                              min: 0,
                              max: max(ctrl.durationMs.toDouble(), 1),
                              activeColor: AppTheme.accent,
                              onChanged: (val) {
                                ctrl.seek(val.toInt());
                                _resetMiniControlsTimer();
                              },
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.volume_up_rounded, color: Colors.white, size: 18),
                            onPressed: () {
                              _resetMiniControlsTimer();
                            },
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

          // Player Control Bar (always visible bottom bar)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: const BoxDecoration(
              color: AppTheme.surface,
              border: Border(top: BorderSide(color: AppTheme.divider)),
            ),
            child: Row(
              children: [
                // Timecode Display
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.background,
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    ),
                    child: Text(
                      '${_formatTime(ctrl.positionMs)} / ${_formatTime(ctrl.durationMs)}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        color: AppTheme.accent,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),

                // Speed dropdown
                _SpeedDropdown(
                  currentSpeed: _playbackSpeed,
                  onSpeedChanged: _changeSpeed,
                ),

                const SizedBox(width: 4),

                // Playback controls
                _playBtn(Icons.replay_10_rounded, () => ctrl.seek(ctrl.positionMs - 10000)),
                _playBtn(
                  ctrl.isPlaying ? Icons.pause_circle_rounded : Icons.play_circle_rounded,
                  ctrl.togglePlayPause,
                  isPrimary: true,
                ),
                _playBtn(Icons.forward_10_rounded, () => ctrl.seek(ctrl.positionMs + 10000)),

                const SizedBox(width: 8),

                // Volume
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      ctrl.volume == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                      color: AppTheme.textMuted,
                      size: 16,
                    ),
                    SizedBox(
                      width: 80,
                      child: Slider(
                        value: ctrl.volume,
                        min: 0.0,
                        max: 1.0,
                        activeColor: AppTheme.accent,
                        onChanged: ctrl.setVolume,
                      ),
                    ),
                  ],
                ),

                const SizedBox(width: 4),

                // v0.7.0: View controls
                _iconBtn(Icons.compare, 'Split View (Ctrl+Shift+F)', _splitView ? AppTheme.primaryLight : AppTheme.textMuted, () {
                  setState(() => _splitView = !_splitView);
                  if (_splitView) _showToast('Split view: drag divider to compare');
                }),
                _iconBtn(_showSafeArea ? Icons.crop_free_rounded : Icons.crop_rounded, 'Safe Area Guides', _showSafeArea ? AppTheme.primaryLight : AppTheme.textMuted, () {
                  setState(() => _showSafeArea = !_showSafeArea);
                }),
                _iconBtn(_showGrid ? Icons.grid_on_rounded : Icons.grid_off_rounded, 'Rule of Thirds Grid', _showGrid ? AppTheme.primaryLight : AppTheme.textMuted, () {
                  setState(() => _showGrid = !_showGrid);
                }),
                _iconBtn(Icons.fit_screen_rounded, 'Fit to Screen', AppTheme.textMuted, () {
                  setState(() {
                    _splitView = false;
                    _showSafeArea = false;
                    _showGrid = false;
                    _showCrosshair = false;
                  });
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // Overlay Builders
  // ============================================================

  Widget _buildSafeAreaOverlay() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final marginX = w * 0.1; // 10% margin on each side (9:16 safe area)
        final marginY = h * 0.05;

        return Stack(
          children: [
            // Top safe area
            Positioned(top: marginY, left: marginX, right: marginX, child: Container(height: 1, color: AppTheme.accent.withValues(alpha: 0.4))),
            // Bottom safe area
            Positioned(bottom: marginY, left: marginX, right: marginX, child: Container(height: 1, color: AppTheme.accent.withValues(alpha: 0.4))),
            // Left safe area
            Positioned(left: marginX, top: marginY, bottom: marginY, child: Container(width: 1, color: AppTheme.accent.withValues(alpha: 0.4))),
            // Right safe area
            Positioned(right: marginX, top: marginY, bottom: marginY, child: Container(width: 1, color: AppTheme.accent.withValues(alpha: 0.4))),

            // Corner markers
            ..._buildCornerMarkers(marginX, marginY, w, h),
          ],
        );
      },
    );
  }

  List<Widget> _buildCornerMarkers(double mx, double my, double w, double h) {
    final size = 20.0;
    final corners = [
      {'left': mx - size, 'top': my - size},
      {'right': w - mx - size + 2, 'top': my - size},
      {'left': mx - size, 'bottom': h - my - size + 2},
      {'right': w - mx - size + 2, 'bottom': h - my - size + 2},
    ];

    return corners.map((c) {
      double? left = c['left'];
      double? top = c['top'];
      double? right = c['right'];
      double? bottom = c['bottom'];

      return Positioned(
        left: left,
        top: top,
        right: right,
        bottom: bottom,
        child: Icon(Icons.crop_square_rounded, color: AppTheme.accent.withValues(alpha: 0.6), size: 16),
      );
    }).toList();
  }

  Widget _buildGridOverlay() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final paint = Paint()
          ..color = AppTheme.accent.withValues(alpha: 0.25)
          ..strokeWidth = 0.5;

        return CustomPaint(
          size: Size(w, h),
          painter: GridPainter(linePaint: paint),
        );
      },
    );
  }

  Widget _buildCrosshairOverlay() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        return Center(
          child: CustomPaint(
            size: Size(w, h),
            painter: CrosshairPainter(
              color: AppTheme.accent.withValues(alpha: 0.5),
            ),
          ),
        );
      },
    );
  }

  Widget _playBtn(IconData icon, VoidCallback onPressed, {bool isPrimary = false}) {
    return IconButton(
      icon: Icon(icon, size: isPrimary ? 32 : 20, color: isPrimary ? AppTheme.primaryLight : AppTheme.textSecondary),
      onPressed: () {
        onPressed();
        _resetMiniControlsTimer();
      },
      style: IconButton.styleFrom(padding: const EdgeInsets.all(4)),
    );
  }

  Widget _iconBtn(IconData icon, String tooltip, Color color, VoidCallback onPressed) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 16, color: color),
        onPressed: () {
          onPressed();
          _resetMiniControlsTimer();
        },
        style: IconButton.styleFrom(padding: const EdgeInsets.all(4)),
      ),
    );
  }

  void _showToast(String message) {
    // Use the parent's toast system
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
      ),
    );
  }

  static String _formatTime(int ms) {
    int totalSec = ms ~/ 1000;
    int minutes = totalSec ~/ 60;
    int seconds = totalSec % 60;
    int millis = ms % 1000;
    return '${minutes.toString().padLeft(2, "0")}:${seconds.toString().padLeft(2, "0")}.${(millis ~/ 10).toString().padLeft(2, "0")}';
  }
}

// ============================================================
// Speed Dropdown Widget
// ============================================================

class _SpeedDropdown extends StatelessWidget {
  final double currentSpeed;
  final Function(double) onSpeedChanged;

  const _SpeedDropdown({required this.currentSpeed, required this.onSpeedChanged});

  static const _speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 4.0];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: AppTheme.divider, width: 0.5),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<double>(
          value: currentSpeed,
          isDense: true,
          dropdownColor: AppTheme.surface,
          style: const TextStyle(color: AppTheme.accent, fontSize: 10, fontWeight: FontWeight.w600),
          items: _speeds.map((s) => DropdownMenuItem(value: s, child: Text('${s}x'))).toList(),
          onChanged: (val) {
            if (val != null) onSpeedChanged(val);
          },
        ),
      ),
    );
  }
}

// ============================================================
// Grid Painter (Rule of Thirds)
// ============================================================

class GridPainter extends CustomPainter {
  final Paint linePaint;

  GridPainter({required this.linePaint});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Vertical lines at 1/3 and 2/3
    for (int i = 1; i <= 2; i++) {
      final x = w * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, h), linePaint);
    }

    // Horizontal lines at 1/3 and 2/3
    for (int i = 1; i <= 2; i++) {
      final y = h * i / 3;
      canvas.drawLine(Offset(0, y), Offset(w, y), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant GridPainter oldDelegate) => false;
}

// ============================================================
// Crosshair Painter
// ============================================================

class CrosshairPainter extends CustomPainter {
  final Color color;

  CrosshairPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    // Vertical line
    canvas.drawLine(Offset(cx, 0), Offset(cx, h), paint);
    // Horizontal line
    canvas.drawLine(Offset(0, cy), Offset(w, cy), paint);

    // Center circle
    final circlePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(Offset(cx, cy), 8, circlePaint);
  }

  @override
  bool shouldRepaint(covariant CrosshairPainter oldDelegate) => false;
}
