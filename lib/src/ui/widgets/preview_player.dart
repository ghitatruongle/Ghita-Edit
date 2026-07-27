import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../controllers/editor_controller.dart';
import '../../controllers/engine_service.dart';
import '../theme/app_theme.dart';

class PreviewPlayer extends StatefulWidget {
  final EditorController controller;

  const PreviewPlayer({super.key, required this.controller});

  @override
  State<PreviewPlayer> createState() => _PreviewPlayerState();
}

class _PreviewPlayerState extends State<PreviewPlayer> {
  ui.Image? _currentFrameImage;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerUpdate);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerUpdate);
    _currentFrameImage?.dispose();
    super.dispose();
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
  }

  String _formatTime(int ms) {
    int totalSec = ms ~/ 1000;
    int minutes = totalSec ~/ 60;
    int seconds = totalSec % 60;
    int millis = ms % 1000;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.${(millis ~/ 10).toString().padLeft(2, '0')}';
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
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  margin: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: _currentFrameImage != null
                          ? RawImage(
                              image: _currentFrameImage,
                              fit: BoxFit.contain,
                            )
                          : Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  CircularProgressIndicator(color: AppTheme.accent),
                                  SizedBox(height: 12),
                                  Text(
                                    'Rendering C++ Native Canvas...',
                                    style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),
                ),

                // Floating Playback Badge
                Positioned(
                  top: 24,
                  right: 24,
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
                            color: ctrl.isPlaying ? Colors.greenAccent : Colors.amberAccent,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          ctrl.isPlaying ? 'PLAYING 60FPS' : 'PAUSED',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Player Control Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              color: AppTheme.card,
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
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${_formatTime(ctrl.positionMs)} / ${_formatTime(ctrl.durationMs)}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        color: AppTheme.accent,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),

                // Playback Transport Controls
                IconButton(
                  icon: const Icon(Icons.replay_10, color: AppTheme.textMain),
                  onPressed: () => ctrl.seek(ctrl.positionMs - 10000),
                ),
                IconButton(
                  icon: Icon(
                    ctrl.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                    color: AppTheme.primaryLight,
                    size: 36,
                  ),
                  onPressed: ctrl.togglePlayPause,
                ),
                IconButton(
                  icon: const Icon(Icons.forward_10, color: AppTheme.textMain),
                  onPressed: () => ctrl.seek(ctrl.positionMs + 10000),
                ),

                const SizedBox(width: 8),

                // Volume slider
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      ctrl.volume == 0 ? Icons.volume_off : Icons.volume_up,
                      color: AppTheme.textMuted,
                      size: 18,
                    ),
                    SizedBox(
                      width: 90,
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
