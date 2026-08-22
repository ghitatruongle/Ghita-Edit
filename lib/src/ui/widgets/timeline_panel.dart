import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import '../../controllers/editor_controller.dart';
import '../../controllers/command_history.dart';
import '../../models/clip.dart' as models;
import '../../models/track.dart';
import '../theme/app_theme.dart';

// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

// ============================================================
// Snap Engine — v0.5.5 (unchanged)
// ============================================================

enum SnapMode { off, halfSecond, oneSecond }

class SnapEngine {
  SnapMode mode;
  final double snapThresholdPx;

  SnapEngine({this.mode = SnapMode.off, this.snapThresholdPx = 8.0});

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

// ============================================================
// Timeline Panel — v0.7.0 Enhanced
// ============================================================

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

  // v1.1.0 (PLAN 1.1/B8): Shared minimum clip duration. The right trim
  // handle clamped to 200ms but the LEFT handle had NO clamp at all —
  // dragging it past the clip's right edge produced durationMs <= 0, which
  // the engine rejects (upsert returns 0) and corrupts rendering/export.
  static const int _kMinClipDurationMs = 100;

  // Multi-select / marquee
  bool _marqueeActive = false;
  Offset? _marqueeStart;
  Offset? _marqueeEnd;
  final Set<String> _marqueeSelectedIds = {};

  // Track dimensions
  double _trackLaneHeight = 0.0;
  final double _rulerHeight = 28.0;
  final double _headerWidth = 120.0;

  // Snap
  SnapMode _snapMode = SnapMode.off;
  late final SnapEngine _snapEngine;

  // v0.7.0: Ripple edit mode
  bool _rippleMode = false;

  // v0.7.0: Group clips (for visual grouping)
  // ignore: unused_field
  // v0.7.8: Removed unused _clipGroupMap (clipId -> groupId) — no backing
  // group logic existed, the field was never read.

  // v0.7.0: Trim drag state — stores original bounds for single undo entry
  final Map<String, _TrimOrigin> _trimOrigins = {};

  @override
  void initState() {
    super.initState();
    _snapEngine = SnapEngine(mode: _snapMode);
  }

  // v1.5.0 T3 (#10/#13): ruler toggles — double-tap = bookmark, long-press = guide.
  void _toggleBookmarkAt(double dx, EditorController ctrl, double pxPerSec) {
    final ms = (dx / pxPerSec * 1000).round();
    final near = ctrl.bookmarks.where((b) => (b.timeMs - ms).abs() < 150).toList();
    if (near.isNotEmpty) {
      ctrl.removeBookmark(near.first.id);
    } else {
      ctrl.addBookmark(ms);
    }
  }

  void _toggleGuideAt(double dx, EditorController ctrl, double pxPerSec) {
    final ms = (dx / pxPerSec * 1000).round();
    final near = ctrl.guideMs.where((g) => (g - ms).abs() < 150).toList();
    if (near.isNotEmpty) {
      ctrl.removeGuide(near.first);
    } else {
      ctrl.addGuide(ms);
    }
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
                final timelineWidth = max(constraints.maxWidth - _headerWidth, _headerWidth);
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
                          _buildTrackHeaderLabel('Timecode', Icons.access_time_rounded, isRuler: true),
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
                        onLongPressStart: (details) {
                          _marqueeActive = true;
                          _marqueeStart = details.localPosition;
                          _marqueeEnd = details.localPosition;
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
                                  child: GestureDetector(
                                    // v1.5.0 T3: double-tap toggles a bookmark
                                    // at that time; long-press toggles a guide.
                                    onDoubleTapDown: (d) => _toggleBookmarkAt(d.localPosition.dx, ctrl, pxPerSec),
                                    onLongPressStart: (d) => _toggleGuideAt(d.localPosition.dx, ctrl, pxPerSec),
                                    child: CustomPaint(
                                      size: Size(timelineWidth, _rulerHeight),
                                      painter: TimelineRulerPainter(
                                        pxPerSec: pxPerSec,
                                        totalDurationSec: totalDurationSec,
                                        snapEngine: _snapEngine,
                                        bookmarks: ctrl.bookmarks
                                            .map((b) => (b.timeMs, b.color))
                                            .toList(),
                                        guides: ctrl.guideMs,
                                      ),
                                    ),
                                  ),
                                ),

                                // Track Lanes
                                ...ctrl.tracks.map((track) => Expanded(
                                  child: _buildTrackLane(track, ctrl, pxPerSec),
                                )),
                              ],
                            ),

                            // v1.5.0 T3 (#13): vertical guides across the lanes.
                            Positioned.fill(
                              child: IgnorePointer(
                                child: CustomPaint(
                                  painter: GuidesPainter(
                                      guides: ctrl.guideMs, pxPerSec: pxPerSec),
                                ),
                              ),
                            ),

                            // Marquee selection rectangle
                            if (_marqueeActive && _marqueeStart != null && _marqueeEnd != null)
                              _buildMarqueeRect(),

                            // Playhead
                            Positioned(
                              left: playheadX.clamp(0, timelineWidth),
                              top: 0,
                              bottom: 0,
                              child: Container(
                                width: 2,
                                color: AppTheme.accent,
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
                                          color: AppTheme.accent,
                                          shape: BoxShape.circle,
                                          boxShadow: [BoxShadow(color: AppTheme.accent, blurRadius: 6, spreadRadius: -2)],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // v0.7.0: Mini-map overview bar
                            if (totalDurationSec > 10)
                              Positioned(
                                right: 8,
                                top: 4,
                                child: _buildMiniMap(ctrl, pxPerSec),
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

  // ============================================================
  // Mini-map Overview (v0.7.0)
  // ============================================================

  Widget _buildMiniMap(EditorController ctrl, double pxPerSec) {
    final totalWidth = 120.0;
    final totalDur = ctrl.durationMs / 1000.0;
    final scale = totalWidth / (totalDur * pxPerSec);

    return Container(
      width: totalWidth,
      height: 8,
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppTheme.divider, width: 0.5),
      ),
      child: CustomPaint(
        painter: MiniMapPainter(
          tracks: ctrl.tracks,
          totalWidth: totalWidth,
          scale: scale,
          playheadSec: ctrl.positionMs / 1000.0,
          pxPerSec: pxPerSec,
        ),
      ),
    );
  }

  // ============================================================
  // Marquee Selection
  // ============================================================

  void _updateMarquee(Offset localPos, double pxPerSec, EditorController ctrl) {
    setState(() {
      _marqueeEnd = localPos;
    });

    final left = min(_marqueeStart!.dx, _marqueeEnd!.dx);
    final right = max(_marqueeStart!.dx, _marqueeEnd!.dx);
    final top = min(_marqueeStart!.dy, _marqueeEnd!.dy);
    final bottom = max(_marqueeStart!.dy, _marqueeEnd!.dy);

    final newSelection = <String>{};

    for (int trackIdx = 0; trackIdx < ctrl.tracks.length; trackIdx++) {
      final track = ctrl.tracks[trackIdx];
      if (!track.isVisible) continue;

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

    // v0.7.8: Coordinates already originate INSIDE the content stack (the
    // marquee GestureDetector sits below the header/ruler) — the previous
    // _headerWidth/_rulerHeight offsets drew the rectangle ~120px right and
    // ~28px down from the actual selection area.
    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.accent, width: 1),
          color: AppTheme.accent.withValues(alpha: 0.08),
        ),
      ),
    );
  }

  // ============================================================
  // Toolbar
  // ============================================================

  Widget _buildToolbar(EditorController ctrl, double currentPosSec) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: const Border(bottom: BorderSide(color: AppTheme.divider)),
      ),
      child: Row(
        children: [
          _toolButton(Icons.call_split_rounded, 'Split (S)', AppTheme.accent, ctrl.splitAtPlayhead),
          _toolButton(Icons.delete_outline_rounded, 'Delete (Del)', AppTheme.error, ctrl.deleteSelectedClip),

          const VerticalDivider(color: AppTheme.divider, indent: 6, endIndent: 6),

          // Zoom
          IconButton(
            icon: const Icon(Icons.zoom_out_rounded, size: 16, color: AppTheme.textMuted),
            onPressed: () => setState(() => _zoomScale = (_zoomScale - 0.2).clamp(0.4, 4.0)),
          ),
          Text('${(_zoomScale * 100).toInt()}%', style: const TextStyle(color: AppTheme.textMuted, fontSize: 10)),
          IconButton(
            icon: const Icon(Icons.zoom_in_rounded, size: 16, color: AppTheme.textMuted),
            onPressed: () => setState(() => _zoomScale = (_zoomScale + 0.2).clamp(0.4, 4.0)),
          ),

          const VerticalDivider(color: AppTheme.divider, indent: 6, endIndent: 6),

          // Snap toggle
          _buildSnapToggle(),

          // v0.7.0: Ripple toggle
          _buildRippleToggle(),

          const Spacer(),

          // Status info
          Text(
            '${ctrl.project.allClips.length} clips${ctrl.selectedClipCount > 1 ? ' • ${ctrl.selectedClipCount} selected' : ''} • ${(ctrl.durationMs / 1000).toStringAsFixed(1)}s',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
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
        icon = Icons.grid_off_rounded;
        break;
      case SnapMode.halfSecond:
        label = 'Snap: 0.5s';
        color = AppTheme.primaryLight;
        icon = Icons.grid_on_rounded;
        break;
      case SnapMode.oneSecond:
        label = 'Snap: 1s';
        color = AppTheme.accent;
        icon = Icons.grid_on_rounded;
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 3),
            Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildRippleToggle() {
    return InkWell(
      onTap: () {
        setState(() => _rippleMode = !_rippleMode);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: _rippleMode ? AppTheme.success.withValues(alpha: 0.1) : AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _rippleMode ? AppTheme.success : AppTheme.divider, width: 0.5),
        ),
        child: Row(
          children: [
            Icon(
              _rippleMode ? Icons.graphic_eq : Icons.waves,
              size: 13,
              color: _rippleMode ? AppTheme.success : AppTheme.textMuted,
            ),
            const SizedBox(width: 3),
            Text(
              'Ripple',
              style: TextStyle(
                color: _rippleMode ? AppTheme.success : AppTheme.textMuted,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolButton(IconData icon, String tooltip, Color color, VoidCallback onPressed) {
    return IconButton(
      icon: Icon(icon, size: 16, color: color),
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(padding: const EdgeInsets.all(4)),
    );
  }

  // ============================================================
  // Track Headers
  // ============================================================

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
          Icon(_iconForTrackType(track.type), size: 12, color: AppTheme.textMuted),
          const SizedBox(width: 3),
          Expanded(
            child: Text(
              track.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.textMain, fontSize: 9),
            ),
          ),
          GestureDetector(
            onTap: () => ctrl.setTrackVisible(track.id, !track.isVisible),
            child: Icon(
              track.isVisible ? Icons.visibility_rounded : Icons.visibility_off_rounded,
              size: 10,
              color: track.isVisible ? AppTheme.textMuted : AppTheme.textMuted.withValues(alpha: 0.3),
            ),
          ),
          const SizedBox(width: 1),
          GestureDetector(
            onTap: () {
              ctrl.setTrackMute(track.id, !track.isMuted);
              setState(() {});
            },
            child: Icon(
              track.isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              size: 10,
              color: track.isMuted ? AppTheme.error : AppTheme.textMuted,
            ),
          ),
          const SizedBox(width: 1),
          GestureDetector(
            onTap: () => ctrl.setTrackLock(track.id, !track.isLocked),
            child: Icon(
              track.isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
              size: 10,
              color: track.isLocked ? AppTheme.warning : AppTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackHeaderLabel(String title, IconData icon, {bool isRuler = false}) {
    return Container(
      height: _rulerHeight,
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
          Icon(icon, size: 12, color: isRuler ? AppTheme.accent : AppTheme.textMuted),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isRuler ? AppTheme.accent : AppTheme.textMain,
                fontSize: 9,
                fontWeight: isRuler ? FontWeight.w700 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // Track Lanes
  // ============================================================

  Widget _buildTrackLane(Track track, EditorController ctrl, double pxPerSec) {
    if (!track.isVisible) {
      return Container(
        decoration: const BoxDecoration(
          color: AppTheme.background,
          border: Border(bottom: BorderSide(color: AppTheme.divider)),
        ),
        child: const Center(
          child: Text('Track Hidden', style: TextStyle(color: AppTheme.textMuted, fontSize: 9, fontStyle: FontStyle.italic)),
        ),
      );
    }

    final laneColor = _colorForTrackType(track.type);

    return DragTarget<Map<String, dynamic>>(
      onAcceptWithDetails: (details) {
        // v1.0.2: Locked tracks must reject drops too — the body-drag and
        // trim paths already guard locks, but this one accepted drops.
        if (track.isLocked) return;
        final item = details.data;
        final clipData = item['clip'] as models.Clip?;
        if (clipData == null) return;
        // v0.7.9: Deep-review — the hand-rolled Clip(...) constructor silently
        // dropped color-correction/text/sticker/transition properties when
        // dragging a media-bin item onto a track. copyWith keeps everything.
        final newClip = clipData.copyWith(
          id: models.Clip.nextId(),
          timelineStartMs: track.durationMs,
          trackIndex: track.trackTypeIndex,
        );
        final cmd = AddClipCommand(trackId: track.id, clip: newClip, positionMs: track.durationMs);
        ctrl.commandHistory.execute(cmd, ctrl.project);
        ctrl.notifyListeners();
      },
      builder: (context, candidateData, rejectedData) {
        return Container(
          decoration: BoxDecoration(
            color: candidateData.isNotEmpty ? laneColor.withValues(alpha: 0.1) : laneColor.withValues(alpha: 0.04),
            border: const Border(bottom: BorderSide(color: AppTheme.divider)),
          ),
          child: Stack(
            children: [
              // v0.7.0: Audio waveform on audio tracks
              if (track.type == TrackType.audio) _buildAudioWaveform(track, ctrl, pxPerSec),

              ...track.clips.map((clip) => _buildClipWidget(clip, track, ctrl, pxPerSec)),

              if (track.clips.isEmpty && track.type != TrackType.audio)
                Center(
                  child: Text(
                    candidateData.isNotEmpty ? 'Drop here' : 'Drop media here',
                    style: TextStyle(
                      color: candidateData.isNotEmpty ? AppTheme.accent : AppTheme.textMuted.withValues(alpha: 0.4),
                      fontSize: 9,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // Audio Waveform (v0.7.0)
  // ============================================================

  Widget _buildAudioWaveform(Track track, EditorController ctrl, double pxPerSec) {
    // v1.1.0 (PLAN 2.10): Skip the FFI waveform fetch when the track has no
    // audio-bearing clip — previously every build of an empty audio track
    // called into the native waveform path (and cached a useless entry).
    // Track 3 (PLAN 3.7) replaces this with a real timeline waveform.
    final hasAudioSource = track.clips.any((c) =>
        c.type == models.ClipType.audio || c.type == models.ClipType.video);
    if (!hasAudioSource) return const SizedBox.shrink();

    // v1.1.0 (PLAN 3.7): REAL timeline waveform — peak per bucket from the
    // engine's mix pipeline (PLAN 3.7), which reflects the actual timeline
    // (trims/moves/speed/multi-clip). The old getAudioWaveform read the
    // legacy single loadMedia() decoder and ignored the timeline entirely.
    final waveform = ctrl.engineService
        .getTimelineWaveform(200, ctrl.tracks.indexOf(track));
    if (waveform.isEmpty) return const SizedBox.shrink();

    return Positioned.fill(
      child: CustomPaint(
        painter: WaveformPainter(
          samples: waveform,
          color: AppTheme.clipAudio,
          pxPerSec: pxPerSec,
        ),
      ),
    );
  }

  // ============================================================
  // Clip Widget
  // ============================================================

  Widget _buildClipWidget(models.Clip clip, Track track, EditorController ctrl, double pxPerSec) {
    final displayStartMs = _tempClipPositions[clip.id] ?? clip.timelineStartMs;
    final leftPx = (displayStartMs / 1000.0) * pxPerSec;
    final widthPx = (clip.durationMs / 1000.0) * pxPerSec;
    final clipColor = _colorForClipType(clip.type);
    final isMultiSelected = ctrl.selectedClipCount > 1 && ctrl.selectedClips.any((c) => c.id == clip.id);

    // v0.7.0: Group color
    final groupColor = clip.groupId != null ? AppTheme.success.withValues(alpha: 0.3) : null;

    return Positioned(
      left: leftPx,
      width: widthPx.clamp(20, double.infinity),
      top: 3,
      bottom: 3,
      child: Stack(
        children: [
          // Left trim handle — v1.0.2: ALWAYS visible (CapCut-style) so users
          // can grab and stretch any clip without knowing it must be selected
          // first. Previously handles only appeared after selection.
          if (!track.isLocked && !clip.isLocked)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 6,
              child: _TrimHandle(
                onDragStart: (_) {
                  _trimmingClipId = clip.id;
                  final track = ctrl.project.trackForClip(clip.id);
                  if (track != null) {
                    _trimOrigins[clip.id] = _TrimOrigin(
                      track.id,
                      clip.timelineStartMs,
                      clip.durationMs,
                    );
                  }
                },
                onDragUpdate: (details) {
                  if (_trimmingClipId != clip.id) return;
                  final deltaMs = (details.delta.dx / pxPerSec * 1000).toInt();
                  final currentStart = _tempClipPositions[clip.id] ?? clip.timelineStartMs;
                  final newStart = max(0, currentStart + deltaMs);
                  final snapped = _snapEngine.snap(newStart, pxPerSec) ?? newStart;
                  final snapped2 = _snapEngine.snapToClipEdges(snapped, pxPerSec, ctrl.tracks, track.id, clip.id) ?? snapped;
                  if (snapped2 != clip.timelineStartMs) {
                    // v0.7.8: Capture the end BEFORE mutating the start —
                    // timelineEndMs is derived from timelineStartMs, so the
                    // old code computed durationMs from the NEW start and the
                    // clip visually stretched instead of trimming.
                    final endMs = clip.timelineEndMs;
                    // v1.1.0 (PLAN 1.1/B8): Never allow the trim to eat the
                    // whole clip — mirror the right handle's minimum duration
                    // (same shared constant) so durationMs can never hit 0.
                    // min() instead of clamp: snapped2 is already >= 0 and
                    // min<int> keeps the static type int.
                    final clampedStart =
                        min(snapped2, endMs - _kMinClipDurationMs);
                    clip.timelineStartMs = clampedStart;
                    clip.durationMs = endMs - clampedStart;
                    _tempClipPositions[clip.id] = clampedStart;
                    ctrl.notifyListeners();
                  }
                },
                onDragEnd: (_) {
                  // Create single undo entry for the entire trim operation
                  final origin = _trimOrigins.remove(clip.id);
                  if (origin != null && clip.timelineStartMs != origin.originalStartMs) {
                    final cmd = TrimClipCommand(
                      trackId: origin.trackId,
                      clipId: clip.id,
                      trimStart: true,
                      newBoundaryMs: clip.timelineStartMs,
                    );
                    // Temporarily swap clip back to original, then execute command
                    clip.timelineStartMs = origin.originalStartMs;
                    clip.durationMs = origin.originalDurationMs;
                    ctrl.commandHistory.execute(cmd, ctrl.project);
                  }
                  // v1.0.2: Clear the temp entry — otherwise after an undo the
                  // clip rendered at the trimmed x-position while its data was
                  // back at the original (visible desync until the next drag).
                  _tempClipPositions.remove(clip.id);
                  _trimmingClipId = null;
                },
                onDragCancel: () {
                  // v0.7.8: Restore the clip when the gesture is cancelled —
                  // the in-drag mutation must not stick without an undo entry.
                  final origin = _trimOrigins.remove(clip.id);
                  if (origin != null) {
                    clip.timelineStartMs = origin.originalStartMs;
                    clip.durationMs = origin.originalDurationMs;
                  }
                  _tempClipPositions.remove(clip.id);
                  _trimmingClipId = null;
                  ctrl.notifyListeners();
                },
              ),
            ),

          // Right trim handle — v1.0.2: always visible (CapCut-style), same
          // rationale as the left handle above.
          if (!track.isLocked && !clip.isLocked)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 6,
              child: _TrimHandle(
                onDragStart: (_) {
                  _trimmingClipId = clip.id;
                  final track = ctrl.project.trackForClip(clip.id);
                  if (track != null) {
                    _trimOrigins[clip.id] = _TrimOrigin(
                      track.id,
                      clip.timelineStartMs,
                      clip.durationMs,
                    );
                  }
                },
                onDragUpdate: (details) {
                  if (_trimmingClipId != clip.id) return;
                  final deltaMs = (details.delta.dx / pxPerSec * 1000).toInt();
                  final currentEnd = clip.timelineEndMs + deltaMs;
                  // v1.1.0 (PLAN 1.1/B8): Unified minimum duration — the
                  // shared constant now backs both trim handles.
                  final newDuration = max(_kMinClipDurationMs, currentEnd - clip.timelineStartMs);
                  final snappedEnd = _snapEngine.snap(clip.timelineStartMs + newDuration, pxPerSec)
                    ?? (clip.timelineStartMs + newDuration);
                  if (snappedEnd > clip.timelineStartMs + 100) {
                    // Direct mutation during drag — single undo entry on drag end
                    clip.durationMs = snappedEnd - clip.timelineStartMs;
                    ctrl.notifyListeners();
                  }
                },
                onDragEnd: (_) {
                  final origin = _trimOrigins.remove(clip.id);
                  if (origin != null && clip.durationMs != origin.originalDurationMs) {
                    final cmd = TrimClipCommand(
                      trackId: origin.trackId,
                      clipId: clip.id,
                      trimStart: false,
                      newBoundaryMs: clip.timelineEndMs,
                    );
                    clip.durationMs = origin.originalDurationMs;
                    ctrl.commandHistory.execute(cmd, ctrl.project);
                  }
                  // v1.0.2: Same cleanup as the start-trim path (see above).
                  _tempClipPositions.remove(clip.id);
                  _trimmingClipId = null;
                },
                onDragCancel: () {
                  // v0.7.8: Restore the clip when the gesture is cancelled —
                  // the in-drag mutation must not stick without an undo entry.
                  final origin = _trimOrigins.remove(clip.id);
                  if (origin != null) {
                    clip.timelineStartMs = origin.originalStartMs;
                    clip.durationMs = origin.originalDurationMs;
                  }
                  _tempClipPositions.remove(clip.id);
                  _trimmingClipId = null;
                  ctrl.notifyListeners();
                },
              ),
            ),

          // Main clip body
          // v1.0.2: The body must NOT cover the trim handles — it used to
          // start at inset 0 (handles only got 6px when a trim was already
          // active), so the body's horizontal-drag GestureDetector swallowed
          // every grab at the clip edges and clips could not be stretched.
          // Now the body yields 6px to each handle whenever they are visible
          // (track/clip unlocked).
          Positioned(
            left: (!track.isLocked && !clip.isLocked) ? 6 : 0,
            right: (!track.isLocked && !clip.isLocked) ? 6 : 0,
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
                if (_trimmingClipId != null || track.isLocked || clip.isLocked) return;
                if (!ctrl.selectedClips.any((c) => c.id == clip.id)) {
                  ctrl.selectClip(clip.id);
                }
                _draggingClipId = clip.id;
                _dragStartMs = displayStartMs;
              },
              onHorizontalDragUpdate: (details) {
                if (_trimmingClipId != null) return;
                if (track.isLocked || clip.isLocked) return;
                final deltaMs = (details.delta.dx / pxPerSec * 1000).toInt();

                if (ctrl.selectedClipCount > 1) {
                  for (final selClip in ctrl.selectedClips) {
                    final currentPos = _tempClipPositions[selClip.id] ?? selClip.timelineStartMs;
                    final newPos = max(0, currentPos + deltaMs);
                    final snapped = _snapEngine.snap(newPos, pxPerSec) ?? newPos;
                    final selTrack = ctrl.project.trackForClip(selClip.id);
                    final snapped2 = selTrack != null
                        ? (_snapEngine.snapToClipEdges(snapped, pxPerSec, ctrl.tracks, selTrack.id, selClip.id) ?? snapped)
                        : snapped;
                    _tempClipPositions[selClip.id] = snapped2;
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
                    // v1.0.2: Compute the ripple delta BEFORE the move loop —
                    // moveClipFrom overwrites timelineStartMs, so computing it
                    // after always yielded 0 and ripple silently never ran in
                    // multi-select mode.
                    int? rightmostDelta;
                    if (_rippleMode) {
                      final sortedSelected = ctrl.selectedClips.toList()
                        ..sort((a, b) => a.timelineEndMs.compareTo(b.timelineEndMs));
                      if (sortedSelected.isNotEmpty) {
                        final rightmostClip = sortedSelected.last;
                        final selTrack = ctrl.project.trackForClip(rightmostClip.id);
                        if (selTrack != null) {
                          final rightmostCurrent = _tempClipPositions[rightmostClip.id] ?? rightmostClip.timelineStartMs;
                          rightmostDelta = rightmostCurrent - rightmostClip.timelineStartMs;
                          if (rightmostDelta != 0) {
                            _applyRipple(selTrack, rightmostClip, rightmostDelta, ctrl);
                          }
                        }
                      }
                    }
                    // Move all selected clips
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
                      if (_rippleMode) {
                        final delta = currentPos - _dragStartMs!;
                        _applyRipple(track, clip, delta, ctrl);
                      }
                      ctrl.moveClipFrom(track.id, clip.id, _dragStartMs!, currentPos);
                    }
                  }
                  _tempClipPositions.clear();
                  _draggingClipId = null;
                  _dragStartMs = null;
                  setState(() {});
                }
              },
              // v0.7.8: A cancelled drag used to leave _draggingClipId set
              // forever — every later body-drag and timeline scrub was blocked.
              onHorizontalDragCancel: () {
                _tempClipPositions.clear();
                _draggingClipId = null;
                _dragStartMs = null;
                setState(() {});
              },
              child: Container(
                decoration: BoxDecoration(
                  color: clip.isSelected ? clipColor.withValues(alpha: 0.85) : clipColor.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: groupColor != null ? AppTheme.success : (clip.isSelected ? Colors.white : clipColor),
                    width: clip.isSelected ? 1.5 : 0.8,
                  ),
                  boxShadow: clip.isSelected ? [BoxShadow(color: clipColor.withValues(alpha: 0.3), blurRadius: 6)] : null,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Stack(
                  children: [
                    Row(
                      // v1.0.2: RenderFlex overflow when a clip is very thin
                      // (e.g. right after a split/drag): the icon + gap alone
                      // (15px) overflowed a 2.4px-wide clip. Hide decoration
                      // below sensible widths so only the (squeezable)
                      // Expanded text label remains.
                      children: [
                        if (widthPx > 20)
                          Icon(_iconForClipType(clip.type), size: 11, color: Colors.white),
                        if (widthPx > 20)
                          const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            clip.displayName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (clip.filterType > 0 && widthPx > 40)
                          const Icon(Icons.auto_fix_high_rounded, size: 9, color: Colors.amberAccent),
                        if (clip.isLocked && widthPx > 40)
                          const Icon(Icons.lock_rounded, size: 9, color: AppTheme.warning),
                        if (isMultiSelected && widthPx > 40)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              '${ctrl.selectedClips.indexOf(clip) + 1}',
                              style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w700),
                            ),
                          ),
                      ],
                    ),
                    // v1.5.0 T3 (#3): keyframe lane strip at the bottom of the clip.
                    if (clip.keyframes.isNotEmpty && widthPx > 16)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 1,
                        height: 5,
                        child: CustomPaint(
                          painter: KeyframeLanePainter(
                            keyframeTimesMs: [
                              for (final k in clip.keyframes) k.timeMs,
                            ],
                            clipStartMs: clip.timelineStartMs,
                            clipDurationMs: clip.durationMs,
                          ),
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

  // ============================================================
  // Ripple Edit Helper (v0.7.0)
  // ============================================================

  void _applyRipple(Track track, models.Clip movedClip, int deltaMs, EditorController ctrl) {
    for (final clip in track.clips) {
      if (clip.id == movedClip.id) continue;
      if (clip.timelineStartMs > movedClip.timelineStartMs) {
        // Shift clip by delta
        final newStart = clip.timelineStartMs + deltaMs;
        if (newStart >= 0) {
          ctrl.moveClipFrom(track.id, clip.id, clip.timelineStartMs, newStart);
        }
      }
    }
  }

  // ============================================================
  // Helpers
  // ============================================================

  Color _colorForTrackType(TrackType type) {
    switch (type) {
      case TrackType.video: return AppTheme.clipVideo.withValues(alpha: 0.06);
      case TrackType.overlay: return AppTheme.clipOverlay.withValues(alpha: 0.06);
      case TrackType.audio: return AppTheme.clipAudio.withValues(alpha: 0.04);
    }
  }

  Color _colorForClipType(models.ClipType type) {
    switch (type) {
      case models.ClipType.video: return AppTheme.clipVideo;
      case models.ClipType.audio: return AppTheme.clipAudio;
      case models.ClipType.image: return AppTheme.clipImage;
      case models.ClipType.text: return AppTheme.clipText;
      case models.ClipType.overlay: return AppTheme.clipOverlay;
      case models.ClipType.sticker: return AppTheme.clipSticker;
    }
  }

  IconData _iconForTrackType(TrackType type) {
    switch (type) {
      case TrackType.video: return Icons.videocam_rounded;
      case TrackType.overlay: return Icons.subtitles_rounded;
      case TrackType.audio: return Icons.graphic_eq_rounded;
    }
  }

  IconData _iconForClipType(models.ClipType type) {
    switch (type) {
      case models.ClipType.video: return Icons.movie_rounded;
      case models.ClipType.audio: return Icons.music_note_rounded;
      case models.ClipType.image: return Icons.image_rounded;
      case models.ClipType.text: return Icons.title_rounded;
      case models.ClipType.overlay: return Icons.layers_rounded;
      case models.ClipType.sticker: return Icons.emoji_emotions_rounded;
    }
  }
}

// ============================================================
// Trim Origin Helper (v0.7.0 — stores pre-drag bounds for single undo entry)
// ============================================================

class _TrimOrigin {
  final String trackId;
  final int originalStartMs;
  final int originalDurationMs;
  const _TrimOrigin(this.trackId, this.originalStartMs, this.originalDurationMs);
}

// ============================================================
// Trim Handle Widget
// ============================================================

class _TrimHandle extends StatelessWidget {
  final Function(DragStartDetails) onDragStart;
  final Function(DragUpdateDetails) onDragUpdate;
  final Function(DragEndDetails) onDragEnd;
  final Function()? onDragCancel;

  const _TrimHandle({
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    this.onDragCancel,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        onHorizontalDragStart: onDragStart,
        onHorizontalDragUpdate: onDragUpdate,
        onHorizontalDragEnd: onDragEnd,
        // v0.7.8: Without this, a cancelled gesture (mouse left the window /
        // gesture arena lost) left _trimmingClipId set forever, blocking all
        // subsequent drags and scrubbing.
        onHorizontalDragCancel: onDragCancel,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Center(
            child: Container(
              width: 2,
              height: 16,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Timeline Ruler Painter — v0.7.0 Enhanced
// ============================================================

/// v1.5.0 T3 (#3): keyframe diamonds along the bottom of a clip row.
class KeyframeLanePainter extends CustomPainter {
  final List<int> keyframeTimesMs;
  final int clipStartMs;
  final int clipDurationMs;

  KeyframeLanePainter({
    required this.keyframeTimesMs,
    required this.clipStartMs,
    required this.clipDurationMs,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppTheme.accent;
    for (final ms in keyframeTimesMs) {
      final t = (ms - clipStartMs) / clipDurationMs;
      if (t < -0.01 || t > 1.01) continue;
      final x = t * size.width;
      final path = Path()
        ..moveTo(x, 0)
        ..lineTo(x + 3, 2.5)
        ..lineTo(x, 5)
        ..lineTo(x - 3, 2.5)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant KeyframeLanePainter oldDelegate) {
    return oldDelegate.keyframeTimesMs != keyframeTimesMs ||
        oldDelegate.clipDurationMs != clipDurationMs;
  }
}

/// v1.5.0 T3 (#13): full-height vertical guide lines over the lanes.
class GuidesPainter extends CustomPainter {
  final List<int> guides;
  final double pxPerSec;

  GuidesPainter({required this.guides, required this.pxPerSec});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.accent.withValues(alpha: 0.45)
      ..strokeWidth = 1.5;
    for (final ms in guides) {
      final x = ms / 1000.0 * pxPerSec;
      if (x < 0 || x > size.width) continue;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant GuidesPainter oldDelegate) {
    return oldDelegate.guides != guides || oldDelegate.pxPerSec != pxPerSec;
  }
}

class TimelineRulerPainter extends CustomPainter {
  final double pxPerSec;
  final double totalDurationSec;
  final SnapEngine? snapEngine;

  /// v1.5.0 T3 (#10): bookmark markers (timeMs, color) on the ruler.
  final List<(int, int)> bookmarks;

  /// v1.5.0 T3 (#13): vertical guide positions (timeMs).
  final List<int> guides;

  TimelineRulerPainter(
      {required this.pxPerSec,
      required this.totalDurationSec,
      this.snapEngine,
      this.bookmarks = const [],
      this.guides = const []});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.textMuted.withValues(alpha: 0.4)
      ..strokeWidth = 1.0;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    // v1.5.0 T3 (#13): guides first (under the ticks).
    for (final ms in guides) {
      final x = ms / 1000.0 * pxPerSec;
      if (x < 0 || x > size.width) continue;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height),
          paint..color = AppTheme.accent.withValues(alpha: 0.35));
    }

    // v1.5.0 T3 (#10): bookmark markers (flag on the ruler).
    for (final (ms, color) in bookmarks) {
      final x = ms / 1000.0 * pxPerSec;
      if (x < 0 || x > size.width) continue;
      final flag = Paint()
        ..color = Color(color).withValues(alpha: 0.9)
        ..style = PaintingStyle.fill;
      final path = Path()
        ..moveTo(x - 4, 2)
        ..lineTo(x + 4, 2)
        ..lineTo(x + 4, 10)
        ..lineTo(x, 8)
        ..lineTo(x - 4, 10)
        ..close();
      canvas.drawPath(path, flag);
    }

    int stepSec = 5;
    if (pxPerSec < 8) stepSec = 10;
    if (pxPerSec < 4) stepSec = 30;

    for (int s = 0; s <= totalDurationSec; s += stepSec) {
      double x = s * pxPerSec;
      if (x > size.width) break;

      // Major tick
      canvas.drawLine(Offset(x, size.height - 10), Offset(x, size.height), paint..color = AppTheme.textSecondary.withValues(alpha: 0.5));

      // Sub-grid snap indicators
      if (snapEngine != null && snapEngine!.mode != SnapMode.off) {
        final gridSec = snapEngine!.mode == SnapMode.oneSecond ? 1.0 : 0.5;
        if (gridSec < stepSec) {
          for (int sub = 1; sub < (stepSec / gridSec); sub++) {
            final subX = (s + sub * gridSec) * pxPerSec;
            if (subX > 0 && subX < size.width) {
              canvas.drawLine(Offset(subX, size.height - 5), Offset(subX, size.height), paint..color = AppTheme.divider);
            }
          }
        }
      }

      // Time label
      textPainter.text = TextSpan(
        text: '${s}s',
        style: TextStyle(color: AppTheme.textMuted, fontSize: 9, fontFamily: 'monospace'),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x + 2, 3));
    }
  }

  @override
  bool shouldRepaint(covariant TimelineRulerPainter oldDelegate) {
    return oldDelegate.pxPerSec != pxPerSec ||
        oldDelegate.totalDurationSec != totalDurationSec ||
        oldDelegate.snapEngine != snapEngine ||
        oldDelegate.bookmarks != bookmarks ||
        oldDelegate.guides != guides;
  }
}

// ============================================================
// Waveform Painter (v0.7.0)
// ============================================================

class WaveformPainter extends CustomPainter {
  final Float32List samples;
  final Color color;
  final double pxPerSec;

  WaveformPainter({required this.samples, required this.color, required this.pxPerSec});

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;

    final paint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    final midY = size.height / 2;
    final sampleWidth = size.width / samples.length;

    // Draw waveform bars
    for (int i = 0; i < samples.length; i++) {
      final sample = samples[i];
      final barHeight = (sample * size.height * 0.8).clamp(1.0, size.height * 0.9);
      final x = i * sampleWidth;
      final y = midY - barHeight / 2;

      paint.color = color.withValues(alpha: 0.3 + (sample.abs() * 0.4));
      canvas.drawRect(Rect.fromLTRB(x, y, x + sampleWidth - 1, y + barHeight), paint);
    }

    // Center line
    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..strokeWidth = 0.5;
    canvas.drawLine(Offset(0, midY), Offset(size.width, midY), linePaint);
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) {
    return oldDelegate.samples != samples || oldDelegate.color != color || oldDelegate.pxPerSec != pxPerSec;
  }
}

// ============================================================
// Mini-map Painter (v0.7.0)
// ============================================================

class MiniMapPainter extends CustomPainter {
  final List<Track> tracks;
  final double totalWidth;
  final double scale;
  final double playheadSec;
  final double pxPerSec;

  MiniMapPainter({
    required this.tracks,
    required this.totalWidth,
    required this.scale,
    required this.playheadSec,
    required this.pxPerSec,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final barHeight = size.height / max(tracks.length, 1);

    for (int i = 0; i < tracks.length; i++) {
      final track = tracks[i];
      if (!track.isVisible) continue;

      final color = _colorForTrackType(track.type);
      for (final clip in track.clips) {
        final left = (clip.timelineStartMs / 1000.0 * pxPerSec) * scale;
        final width = (clip.durationMs / 1000.0 * pxPerSec) * scale;
        final top = i * barHeight;

        canvas.drawRect(
          Rect.fromLTRB(left.clamp(0, totalWidth), top + 0.5, (left + width).clamp(0, totalWidth), top + barHeight - 0.5),
          Paint()..color = color.withValues(alpha: 0.5),
        );
      }
    }

    // Playhead indicator
    final playheadX = playheadSec * pxPerSec * scale;
    canvas.drawLine(
      Offset(playheadX.clamp(0, totalWidth), 0),
      Offset(playheadX.clamp(0, totalWidth), size.height),
      Paint()..color = AppTheme.accent..strokeWidth = 1.5,
    );
  }

  Color _colorForTrackType(TrackType type) {
    switch (type) {
      case TrackType.video: return AppTheme.clipVideo;
      case TrackType.overlay: return AppTheme.clipOverlay;
      case TrackType.audio: return AppTheme.clipAudio;
    }
  }

  @override
  bool shouldRepaint(covariant MiniMapPainter oldDelegate) {
    if (oldDelegate.tracks != tracks ||
        oldDelegate.playheadSec != playheadSec ||
        oldDelegate.pxPerSec != pxPerSec ||
        oldDelegate.scale != scale) {
      return true;
    }
    // v1.0.2: The tracks List instance never changes across clip moves/trims,
    // so the old identity check alone left the mini-map stale. Compare the
    // actual clip positions (cheap at timeline scales).
    return _clipSignature() != oldDelegate._clipSignature();
  }

  /// v1.0.2: Snapshot of every clip's id + start position — changes whenever
  /// a clip is moved, trimmed, added or removed.
  String _clipSignature() {
    final buf = StringBuffer();
    for (final t in tracks) {
      for (final c in t.clips) {
        buf.write('${c.id}:${c.timelineStartMs};');
      }
    }
    return buf.toString();
  }
}
