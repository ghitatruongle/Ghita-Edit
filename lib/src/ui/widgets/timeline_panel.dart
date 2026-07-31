import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import '../../controllers/editor_controller.dart';
import '../../controllers/command_history.dart';
import '../../models/clip.dart' as models;
import '../../models/track.dart';
import '../theme/app_theme.dart';

// ========== Snap Engine ==========

enum SnapMode { off, oneSecond, halfSecond }

class SnapEngine {
  SnapMode mode;
  final double snapThresholdPx;

  SnapEngine({this.mode = SnapMode.off, this.snapThresholdPx = 8.0});

  /// Returns the snapped time in ms, or null if no snap point is within threshold.
  int? snap(int timeMs, double pxPerSec) {
    if (mode == SnapMode.off || pxPerSec <= 0) return null;

    final gridSec = mode == SnapMode.oneSecond ? 1.0 : 0.5;
    final gridMs = (gridSec * 1000).toInt();
    final remainder = timeMs % gridMs;
    if (remainder == 0) return timeMs;

    final distToPrev = remainder;
    final distToNext = gridMs - remainder;
    final prevPx = (distToPrev / 1000.0) * pxPerSec;
    final nextPx = (distToNext / 1000.0) * pxPerSec;

    if (prevPx <= snapThresholdPx) return timeMs - distToPrev;
    if (nextPx <= snapThresholdPx) return timeMs + distToNext;
    return null;
  }

  /// Snap clip edges to nearby clip edges on any track (magnetic snapping).
  int? snapToClipEdges(int timeMs, double pxPerSec, List<Track> tracks, String excludeTrackId, String excludeClipId) {
    if (mode == SnapMode.off || pxPerSec <= 0) return null;
    final thresholdPx = snapThresholdPx * 1.5;
    int? bestSnap;
    double bestDist = thresholdPx;

    for (final track in tracks) {
      if (track.id == excludeTrackId) continue;
      for (final clip in track.clips) {
        if (clip.id == excludeClipId) continue;
        for (final edge in [clip.timelineStartMs, clip.timelineEndMs]) {
          final distPx = ((timeMs - edge).abs() / 1000.0) * pxPerSec;
          if (distPx < bestDist) {
            bestDist = distPx;
            bestSnap = edge;
          }
        }
      }
    }

    // Snap to playhead (0ms)
    final playheadDistPx = (timeMs / 1000.0) * pxPerSec;
    if (playheadDistPx < bestDist) {
      bestSnap = 0;
    }

    return bestSnap;
  }
}

// ========== Timeline Panel ==========

class TimelinePanel extends StatefulWidget {
  final EditorController controller;

  const TimelinePanel({super.key, required this.controller});

  @override
  State<TimelinePanel> createState() => _TimelinePanelState();
}

class _TimelinePanelState extends State<TimelinePanel> {
  // Zoom
  double _zoomScale = 1.0;

  // Clip dragging
  String? _draggingClipId;
  int? _dragStartMs;
  final Map<String, int> _tempClipPositions = {};

  // Trim dragging
  String? _trimmingClipId;
  bool _trimmingStart = false;

  // Multi-select / marquee
  bool _marqueeActive = false;
  Offset? _marqueeStart;
  Offset? _marqueeEnd;
  final Set<String> _marqueeSelectedIds = {};

  // Track lane dimensions (computed during build for marquee)
  double _trackLaneHeight = 0.0;
  final double _rulerHeight = 28.0;
  final double _headerWidth = 120.0;

  // Snap
  SnapMode _snapMode = SnapMode.off;
  late final SnapEngine _snapEngine;

  @override
  void initState() {
    super.initState();
    _snapEngine = SnapEngine(mode: _snapMode);
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final totalDurationSec = ctrl.durationMs / 1000.0;
    final currentPosSec = ctrl.positionMs / 1000.0;

    return Container(
      color: AppTheme.card,
      child: Column(
        children: [
          _buildToolbar(ctrl, currentPosSec),

          // Interactive Timeline Area
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final timelineWidth = constraints.maxWidth - _headerWidth;
                final pxPerSec = (timelineWidth / (totalDurationSec > 0 ? totalDurationSec : 60)) * _zoomScale;
                final playheadX = currentPosSec * pxPerSec;
                final numTracks = ctrl.tracks.length;
                _trackLaneHeight = numTracks > 0 ? (constraints.maxHeight - _rulerHeight) / numTracks : 40.0;

                return Row(
                  children: [
                    // Left Track Headers
                    SizedBox(
                      width: _headerWidth,
                      child: Column(
                        children: [
                          _buildTrackHeaderLabel('Timecode', Icons.access_time, isRuler: true),
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
                          if (_draggingClipId != null && _trimmingClipId == null) return;
                          if (_marqueeActive) {
                            _updateMarquee(details.localPosition, pxPerSec, ctrl);
                            return;
                          }
                          final newSec = (details.localPosition.dx / pxPerSec).clamp(0.0, totalDurationSec);
                          ctrl.seek((newSec * 1000).toInt());
                        },
                        onTapDown: (details) {
                          if (_marqueeActive) return;
                          final newSec = (details.localPosition.dx / pxPerSec).clamp(0.0, totalDurationSec);
                          ctrl.seek((newSec * 1000).toInt());
                        },
                        onLongPressStart: (_) {
                          _marqueeActive = true;
                          _marqueeStart = Offset(0, 0);
                          _marqueeEnd = Offset(0, 0);
                          _marqueeSelectedIds.clear();
                          ctrl.deselectAll();
                          setState(() {});
                        },
                        onLongPressMoveUpdate: (details) {
                          if (_marqueeActive) {
                            _updateMarquee(details.localPosition, pxPerSec, ctrl);
                          }
                        },
                        onLongPressEnd: (_) {
                          if (_marqueeActive) {
                            _marqueeActive = false;
                            _marqueeStart = null;
                            _marqueeEnd = null;
                            if (_marqueeSelectedIds.isNotEmpty) {
                              ctrl.project.addToSelection(_marqueeSelectedIds);
                              // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
                              ctrl.notifyListeners();
                            }
                            _marqueeSelectedIds.clear();
                            setState(() {});
                          }
                        },
                        child: Stack(
                          children: [
                            Column(
                              children: [
                                // Time Ruler
                                Container(
                                  height: _rulerHeight,
                                  color: AppTheme.surface,
                                  child: CustomPaint(
                                    size: Size(timelineWidth, _rulerHeight),
                                    painter: TimelineRulerPainter(
                                      pxPerSec: pxPerSec,
                                      totalDurationSec: totalDurationSec,
                                      snapEngine: _snapEngine,
                                    ),
                                  ),
                                ),

                                // Track Lanes with real clips
                                ...ctrl.tracks.map((track) => Expanded(
                                  child: _buildTrackLane(track, ctrl, pxPerSec),
                                )),
                              ],
                            ),

                            // Marquee selection rectangle — v0.5.5
                            if (_marqueeActive && _marqueeStart != null && _marqueeEnd != null)
                              _buildMarqueeRect(),

                            // Playhead
                            Positioned(
                              left: playheadX.clamp(0, timelineWidth),
                              top: 0,
                              bottom: 0,
                              child: Container(
                                width: 2,
                                color: Colors.redAccent,
                                child: Stack(
                                  clipBehavior: Clip.none,
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

  // ========== Marquee Selection ==========

  void _updateMarquee(Offset localPos, double pxPerSec, EditorController ctrl) {
    setState(() {
      _marqueeEnd = localPos;
    });

    // Determine which clips intersect the marquee rectangle
    final left = min(_marqueeStart!.dx, _marqueeEnd!.dx);
    final right = max(_marqueeStart!.dx, _marqueeEnd!.dx);
    final top = min(_marqueeStart!.dy, _marqueeEnd!.dy);
    final bottom = max(_marqueeStart!.dy, _marqueeEnd!.dy);

    final newSelection = <String>{};

    for (int trackIdx = 0; trackIdx < ctrl.tracks.length; trackIdx++) {
      final track = ctrl.tracks[trackIdx];
      if (!track.isVisible) continue;

      // Track lane area relative to the canvas (below ruler)
      final laneTop = _rulerHeight + trackIdx * _trackLaneHeight;
      final laneBottom = laneTop + _trackLaneHeight;

      if (bottom < laneTop || top > laneBottom) continue;

      for (final clip in track.clips) {
        final clipLeft = (clip.timelineStartMs / 1000.0) * pxPerSec;
        final clipRight = ((clip.timelineStartMs + clip.durationMs) / 1000.0) * pxPerSec;
        if (clipRight >= left && clipLeft <= right) {
          newSelection.add(clip.id);
        }
      }
    }

    _marqueeSelectedIds
      ..clear()
      ..addAll(newSelection);
  }

  Widget _buildMarqueeRect() {
    final left = min(_marqueeStart!.dx, _marqueeEnd!.dx);
    final top = min(_marqueeStart!.dy, _marqueeEnd!.dy);
    final width = (_marqueeEnd!.dx - _marqueeStart!.dx).abs();
    final height = (_marqueeEnd!.dy - _marqueeStart!.dy).abs();

    return Positioned(
      left: left + _headerWidth,
      top: top + _rulerHeight,
      width: width,
      height: height,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.accent, width: 1),
          color: AppTheme.accent.withValues(alpha: 0.1),
        ),
      ),
    );
  }

  // ========== Toolbar ==========

  Widget _buildToolbar(EditorController ctrl, double currentPosSec) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.divider)),
      ),
      child: Row(
        children: [
          _toolButton(Icons.content_cut, 'Split at Playhead (S)', AppTheme.accent, ctrl.splitAtPlayhead),
          _toolButton(Icons.delete_outline, 'Delete Selected (Del)', Colors.redAccent, ctrl.deleteSelectedClip),

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

          const VerticalDivider(color: AppTheme.divider, indent: 8, endIndent: 8),

          // Snap toggle — v0.5.5: replaces fake "Snap ON"
          _buildSnapToggle(),

          const Spacer(),

          // Status info
          Text(
            '${ctrl.project.allClips.length} clips${ctrl.selectedClipCount > 1 ? ' • ${ctrl.selectedClipCount} selected' : ''} • ${(ctrl.durationMs / 1000).toStringAsFixed(1)}s',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildSnapToggle() {
    String label;
    Color color;
    IconData icon;
    switch (_snapMode) {
      case SnapMode.off:
        label = 'Snap: Off';
        color = AppTheme.textMuted;
        icon = Icons.grid_off;
        break;
      case SnapMode.halfSecond:
        label = 'Snap: 0.5s';
        color = AppTheme.primaryLight;
        icon = Icons.grid_on;
        break;
      case SnapMode.oneSecond:
        label = 'Snap: 1s';
        color = AppTheme.accent;
        icon = Icons.grid_on;
        break;
    }

    return InkWell(
      onTap: () {
        setState(() {
          _snapMode = SnapMode.values[(_snapMode.index + 1) % SnapMode.values.length];
          _snapEngine.mode = _snapMode;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
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

  // ========== Track Headers ==========

  Widget _buildTrackHeader(Track track, EditorController ctrl) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
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
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              track.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.textMain, fontSize: 10),
            ),
          ),
          // Visibility toggle — v0.5.5
          GestureDetector(
            onTap: () => setState(() => track.isVisible = !track.isVisible),
            child: Icon(
              track.isVisible ? Icons.visibility : Icons.visibility_off,
              size: 12,
              color: track.isVisible ? AppTheme.textMuted : AppTheme.textMuted.withValues(alpha: 0.3),
            ),
          ),
          const SizedBox(width: 2),
          // Mute toggle
          GestureDetector(
            onTap: () {
              ctrl.setTrackMute(track.id, !track.isMuted);
              setState(() {});
            },
            child: Icon(
              track.isMuted ? Icons.volume_off : Icons.volume_up,
              size: 12,
              color: track.isMuted ? Colors.redAccent : AppTheme.textMuted,
            ),
          ),
          const SizedBox(width: 2),
          // Lock toggle
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

  // ========== Track Lanes ==========

  Widget _buildTrackLane(Track track, EditorController ctrl, double pxPerSec) {
    if (!track.isVisible) {
      return Container(
        decoration: const BoxDecoration(
          color: AppTheme.background,
          border: Border(bottom: BorderSide(color: AppTheme.divider)),
        ),
        child: const Center(
          child: Text('Track Hidden', style: TextStyle(color: AppTheme.textMuted, fontSize: 10, fontStyle: FontStyle.italic)),
        ),
      );
    }

    final laneColor = _colorForTrackType(track.type);

    return DragTarget<Map<String, dynamic>>(
      onAcceptWithDetails: (details) {
        final item = details.data;
        // v0.5.5: Drop media from MediaBin onto timeline track
        final clipData = item['clip'] as models.Clip?;
        if (clipData == null) return;
        final newClip = models.Clip(
          id: 'clip_${DateTime.now().millisecondsSinceEpoch}',
          sourceFilePath: clipData.sourceFilePath,
          displayName: clipData.displayName,
          timelineStartMs: track.durationMs,
          durationMs: clipData.durationMs,
          sourceInMs: clipData.sourceInMs,
          sourceOutMs: clipData.sourceOutMs,
          trackIndex: track.trackTypeIndex,
          type: clipData.type,
          speed: clipData.speed,
          opacity: clipData.opacity,
        );
        final cmd = AddClipCommand(trackId: track.id, clip: newClip, positionMs: track.durationMs);
        ctrl.commandHistory.execute(cmd, ctrl.project);
        // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
        ctrl.notifyListeners();
      },
      builder: (context, candidateData, rejectedData) {
        return Container(
          decoration: BoxDecoration(
            color: candidateData.isNotEmpty
                ? laneColor.withValues(alpha: 0.15)
                : laneColor.withValues(alpha: 0.05),
            border: const Border(bottom: BorderSide(color: AppTheme.divider)),
          ),
          child: Stack(
            children: [
              ...track.clips.map((clip) => _buildClipWidget(clip, track, ctrl, pxPerSec)),

              if (track.clips.isEmpty)
                Center(
                  child: Text(
                    candidateData.isNotEmpty ? 'Drop here' : 'Drop media here or import file',
                    style: TextStyle(
                      color: candidateData.isNotEmpty ? AppTheme.accent : AppTheme.textMuted.withValues(alpha: 0.5),
                      fontSize: 10,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ========== Clip Widget ==========

  Widget _buildClipWidget(models.Clip clip, Track track, EditorController ctrl, double pxPerSec) {
    final displayStartMs = _tempClipPositions[clip.id] ?? clip.timelineStartMs;
    final leftPx = (displayStartMs / 1000.0) * pxPerSec;
    final widthPx = (clip.durationMs / 1000.0) * pxPerSec;
    final clipColor = _colorForClipType(clip.type);
    final isMultiSelected = ctrl.selectedClipCount > 1 && ctrl.selectedClips.any((c) => c.id == clip.id);

    return Positioned(
      left: leftPx,
      width: widthPx.clamp(20, double.infinity),
      top: 3,
      bottom: 3,
      child: Stack(
        children: [
          // Left trim handle — v0.5.5
          if (clip.isSelected || isMultiSelected)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 6,
              child: _TrimHandle(
                onDragStart: (_) {
                  _trimmingClipId = clip.id;
                  _trimmingStart = true;
                },
                onDragUpdate: (details) {
                  if (_trimmingClipId != clip.id) return;
                  final deltaMs = (details.delta.dx / pxPerSec * 1000).toInt();
                  final currentStart = _tempClipPositions[clip.id] ?? clip.timelineStartMs;
                  final newStart = max(0, currentStart + deltaMs);
                  final snapped = _snapEngine.snap(newStart, pxPerSec) ?? newStart;
                  final snapped2 = _snapEngine.snapToClipEdges(snapped, pxPerSec, ctrl.tracks, track.id, clip.id) ?? snapped;
                  if (snapped2 != clip.timelineStartMs) {
                    ctrl.trimClipStart(clip.id, snapped2);
                    _tempClipPositions[clip.id] = snapped2;
                    setState(() {});
                  }
                },
                onDragEnd: (_) {
                  _trimmingClipId = null;
                  _trimmingStart = false;
                },
              ),
            ),

          // Right trim handle — v0.5.5
          if (clip.isSelected || isMultiSelected)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 6,
              child: _TrimHandle(
                onDragStart: (_) {
                  _trimmingClipId = clip.id;
                  _trimmingStart = false;
                },
                onDragUpdate: (details) {
                  if (_trimmingClipId != clip.id) return;
                  final deltaMs = (details.delta.dx / pxPerSec * 1000).toInt();
                  final currentEnd = clip.timelineEndMs + deltaMs;
                  final newDuration = max(200, currentEnd - clip.timelineStartMs);
                  final snappedEnd = _snapEngine.snap(clip.timelineStartMs + newDuration, pxPerSec)
                    ?? (clip.timelineStartMs + newDuration);
                  if (snappedEnd > clip.timelineStartMs + 100) {
                    ctrl.trimClipEnd(clip.id, snappedEnd);
                    setState(() {});
                  }
                },
                onDragEnd: (_) {
                  _trimmingClipId = null;
                  _trimmingStart = false;
                },
              ),
            ),

          // Main clip body
          Positioned(
            left: (_trimmingClipId == clip.id && _trimmingStart) ? 6 : 0,
            right: (_trimmingClipId == clip.id && !_trimmingStart) ? 6 : 0,
            top: 0,
            bottom: 0,
            child: GestureDetector(
              onTap: () {
                final ctrlPressed = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
                final shiftPressed = HardwareKeyboard.instance.isShiftPressed;

                if (ctrlPressed) {
                  ctrl.toggleClipSelection(clip.id);
                } else if (shiftPressed && ctrl.selectedClip != null && ctrl.selectedClip!.id != clip.id) {
                  ctrl.selectRange(ctrl.selectedClip!.id, clip.id);
                } else {
                  ctrl.selectClip(clip.id);
                }
                setState(() {});
              },
              onHorizontalDragStart: (_) {
                if (_trimmingClipId != null) return;
                // If this clip is NOT in current selection, clear and select only it
                if (!ctrl.selectedClips.any((c) => c.id == clip.id)) {
                  ctrl.selectClip(clip.id);
                }
                _draggingClipId = clip.id;
                _dragStartMs = displayStartMs;
              },
              onHorizontalDragUpdate: (details) {
                if (_trimmingClipId != null) return;
                if (track.isLocked) return;
                final deltaMs = (details.delta.dx / pxPerSec * 1000).toInt();

                if (ctrl.selectedClipCount > 1) {
                  // Move all selected clips by same delta
                  for (final selClip in ctrl.selectedClips) {
                    final currentPos = _tempClipPositions[selClip.id] ?? selClip.timelineStartMs;
                    final newPos = max(0, currentPos + deltaMs);
                    _tempClipPositions[selClip.id] = newPos;
                  }
                } else {
                  final newStart = max(0, displayStartMs + deltaMs);
                  final snapped = _snapEngine.snap(newStart, pxPerSec) ?? newStart;
                  final snapped2 = _snapEngine.snapToClipEdges(snapped, pxPerSec, ctrl.tracks, track.id, clip.id) ?? snapped;
                  _tempClipPositions[clip.id] = snapped2;
                }
                setState(() {});
              },
              onHorizontalDragEnd: (_) {
                if (_draggingClipId != null && _dragStartMs != null) {
                  if (ctrl.selectedClipCount > 1) {
                    for (final selClip in ctrl.selectedClips) {
                      final currentPos = _tempClipPositions[selClip.id] ?? selClip.timelineStartMs;
                      final selTrack = ctrl.project.trackForClip(selClip.id);
                      if (selTrack != null && currentPos != selClip.timelineStartMs) {
                        ctrl.moveClipFrom(selTrack.id, selClip.id, selClip.timelineStartMs, currentPos);
                      }
                    }
                  } else {
                    final currentPos = _tempClipPositions[clip.id] ?? clip.timelineStartMs;
                    if (currentPos != _dragStartMs) {
                      ctrl.moveClipFrom(track.id, clip.id, _dragStartMs!, currentPos);
                    }
                  }
                  _tempClipPositions.clear();
                  _draggingClipId = null;
                  _dragStartMs = null;
                  setState(() {});
                }
              },
              child: Container(
                decoration: BoxDecoration(
                  color: clip.isSelected ? clipColor.withValues(alpha: 0.9) : clipColor.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: clip.isSelected ? Colors.white : clipColor,
                    width: clip.isSelected ? 2 : 1,
                  ),
                  boxShadow: clip.isSelected ? [
                    BoxShadow(color: clipColor.withValues(alpha: 0.4), blurRadius: 8),
                  ] : null,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8),
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
                    // Multi-select index badge — v0.5.5
                    if (isMultiSelected)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          '${ctrl.selectedClips.indexOf(clip) + 1}',
                          style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ========== Track Header Label ==========

  Widget _buildTrackHeaderLabel(String title, IconData icon, {bool isRuler = false}) {
    return Container(
      height: isRuler ? _rulerHeight : double.infinity,
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

  // ========== Helpers ==========

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

// ========== Trim Handle Widget — v0.5.5 ==========

class _TrimHandle extends StatelessWidget {
  final Function(DragStartDetails) onDragStart;
  final Function(DragUpdateDetails) onDragUpdate;
  final Function(DragEndDetails) onDragEnd;

  const _TrimHandle({
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        onHorizontalDragStart: onDragStart,
        onHorizontalDragUpdate: onDragUpdate,
        onHorizontalDragEnd: onDragEnd,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Center(
            child: Container(
              width: 2,
              height: 20,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ========== Timeline Ruler Painter ==========

class TimelineRulerPainter extends CustomPainter {
  final double pxPerSec;
  final double totalDurationSec;
  final SnapEngine? snapEngine;

  TimelineRulerPainter({required this.pxPerSec, required this.totalDurationSec, this.snapEngine});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.textMuted.withValues(alpha: 0.5)
      ..strokeWidth = 1.0;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    int stepSec = 5;
    if (pxPerSec < 8) stepSec = 10;
    if (pxPerSec < 4) stepSec = 30;

    for (int s = 0; s <= totalDurationSec; s += stepSec) {
      double x = s * pxPerSec;
      if (x > size.width) break;

      canvas.drawLine(Offset(x, size.height - 8), Offset(x, size.height), paint);

      // Sub-grid snap indicators
      if (snapEngine != null && snapEngine!.mode != SnapMode.off) {
        final gridSec = snapEngine!.mode == SnapMode.oneSecond ? 1.0 : 0.5;
        if (gridSec < stepSec) {
          for (int sub = 1; sub < (stepSec / gridSec); sub++) {
            final subX = (s + sub * gridSec) * pxPerSec;
            if (subX > 0 && subX < size.width) {
              canvas.drawLine(Offset(subX, size.height - 4), Offset(subX, size.height), paint..color = AppTheme.divider);
            }
          }
        }
      }

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
    return oldDelegate.pxPerSec != pxPerSec ||
        oldDelegate.totalDurationSec != totalDurationSec ||
        oldDelegate.snapEngine != snapEngine;
  }
}
