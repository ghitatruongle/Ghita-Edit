import 'dart:async';
import 'dart:ffi';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../controllers/editor_controller.dart';
import '../theme/app_theme.dart';

class ExportDialog extends StatefulWidget {
  final EditorController controller;

  const ExportDialog({super.key, required this.controller});

  @override
  State<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<ExportDialog> {
  // Preset selection
  String? _selectedPreset;
  bool _customMode = false;

  // Manual settings (used when _customMode is true)
  String _selectedRes = '1080p (Full HD)';
  String _selectedFps = '60 FPS';
  String _selectedFormat = 'MP4';
  String _selectedCodec = 'H.264';
  double _bitrateMbps = 10.0;
  bool _includeAudio = true;

  String? _outputPath;
  bool _isExporting = false;
  double _exportProgress = 0.0;
  int _exportFileSizeBytes = 0;
  Timer? _progressTimer;
  DateTime? _exportStartTime;

  // v0.7.0: Enhanced export presets
  static const _presets = <ExportPreset>[
    ExportPreset(
      name: 'YouTube 1080p',
      label: 'YouTube 1080p',
      icon: Icons.play_circle_filled,
      width: 1920, height: 1080, fps: 60,
      format: 'MP4', codec: 'H.264', bitrateMbps: 10.0, includeAudio: true,
      description: 'H.264 • 10 Mbps • 60fps',
    ),
    ExportPreset(
      name: 'YouTube 4K',
      label: 'YouTube 4K',
      icon: Icons.high_quality,
      width: 3840, height: 2160, fps: 60,
      format: 'MP4', codec: 'H.265', bitrateMbps: 35.0, includeAudio: true,
      description: 'H.265 • 35 Mbps • 60fps',
    ),
    ExportPreset(
      name: 'YouTube Shorts',
      label: 'YouTube Shorts',
      icon: Icons.smartphone,
      width: 1080, height: 1920, fps: 30,
      format: 'MP4', codec: 'H.264', bitrateMbps: 8.0, includeAudio: true,
      description: '9:16 • H.264 • 8 Mbps • 30fps',
    ),
    ExportPreset(
      name: 'TikTok 9:16',
      label: 'TikTok / Reels',
      icon: Icons.phone_iphone,
      width: 1080, height: 1920, fps: 30,
      format: 'MP4', codec: 'H.264', bitrateMbps: 8.0, includeAudio: true,
      description: '9:16 • H.264 • 8 Mbps • 30fps',
    ),
    ExportPreset(
      name: 'Instagram Story',
      label: 'Instagram Story',
      icon: Icons.camera_alt,
      width: 1080, height: 1920, fps: 30,
      format: 'MP4', codec: 'H.264', bitrateMbps: 7.0, includeAudio: true,
      description: '9:16 • H.264 • 7 Mbps • 30fps',
    ),
    ExportPreset(
      name: 'Instagram 1:1',
      label: 'Instagram 1:1',
      icon: Icons.camera,
      width: 1080, height: 1080, fps: 30,
      format: 'MP4', codec: 'H.264', bitrateMbps: 6.0, includeAudio: true,
      description: '1:1 • H.264 • 6 Mbps • 30fps',
    ),
    ExportPreset(
      name: 'Twitter 720p',
      label: 'Twitter / X',
      icon: Icons.chat,
      width: 1280, height: 720, fps: 30,
      format: 'MP4', codec: 'H.264', bitrateMbps: 5.0, includeAudio: true,
      description: '720p • H.264 • 5 Mbps • 30fps',
    ),
    ExportPreset(
      name: 'Web VP9',
      label: 'Web (VP9)',
      icon: Icons.public,
      width: 1920, height: 1080, fps: 30,
      format: 'MP4', codec: 'VP9', bitrateMbps: 8.0, includeAudio: true,
      description: 'VP9 • 8 Mbps • 30fps',
    ),
    // v1.1.0 (PLAN 3.12): GIF preset REMOVED — the engine cannot produce a
    // valid GIF: the libavcodec gif encoder only accepts pal8 (palette
    // quantization), and the v1.0.0 claim "GIF export animated thật" never
    // actually worked (muxer rejects the audio stream / encoder rejects the
    // pixel format). Honest: no GIF entry until the engine implements
    // palette generation. The engine reports the failure loudly — it does
    // not silently substitute another codec.
    ExportPreset(
      name: 'Audio Only',
      label: 'Audio Only (MP3)',
      icon: Icons.audiotrack_rounded,
      width: 0, height: 0, fps: 0,
      format: 'MP3', codec: 'MP3', bitrateMbps: 0.128, includeAudio: true,
      description: 'MP3 • 128 kbps',
    ),
    ExportPreset(
      name: 'Archive H264',
      label: 'Archive (H.264)',
      icon: Icons.archive,
      width: 1920, height: 1080, fps: 60,
      format: 'MOV', codec: 'H.264', bitrateMbps: 200.0, includeAudio: true,
      // v1.1.0 (PLAN 3.10): The old "Archive (ProRes)" preset silently
      // exported H.264 into a .mov while claiming ProRes — the engine now
      // looks up a real ProRes encoder and fails loudly when absent. The
      // preset is renamed honestly to what it actually produces.
      description: 'H.264 • 200 Mbps • 60fps • MOV',
    ),
    ExportPreset(
      name: 'Custom',
      label: 'Custom...',
      icon: Icons.tune,
      width: 1920, height: 1080, fps: 60,
      format: 'MP4', codec: 'H.264', bitrateMbps: 10.0, includeAudio: true,
      description: 'Manual configuration',
    ),
  ];

  @override
  void initState() {
    super.initState();
    // Default to first preset
    _selectedPreset = _presets.first.name;
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  ExportPreset? _getPreset(String name) {
    try {
      return _presets.firstWhere((p) => p.name == name);
    } on StateError {
      return null;
    }
  }

  int get resWidth {
    if (!_customMode && _selectedPreset != null) {
      final preset = _getPreset(_selectedPreset!);
      if (preset != null) return preset.width;
    }
    switch (_selectedRes) {
      case '720p (HD)': return 1280;
      case '4K (Ultra HD)': return 3840;
      case '1080p (Full HD)': return 1920;
      default:
        // v0.7.8: GIF sizes like '240p'/'480p' fell through to 1920×1080 —
        // parse the numeric height and derive a 16:9 width.
        final match = RegExp(r'^(\d+)').firstMatch(_selectedRes);
        if (match != null) {
          final h = int.parse(match.group(1)!);
          if (h > 0) return (h * 16 / 9).round();
        }
        return 1920;
    }
  }

  int get resHeight {
    if (!_customMode && _selectedPreset != null) {
      final preset = _getPreset(_selectedPreset!);
      if (preset != null) return preset.height;
    }
    switch (_selectedRes) {
      case '720p (HD)': return 720;
      case '4K (Ultra HD)': return 2160;
      case '1080p (Full HD)': return 1080;
      default:
        // v0.7.8: parse GIF sizes ('240p' → 240, etc.)
        final match = RegExp(r'^(\d+)').firstMatch(_selectedRes);
        if (match != null) {
          final h = int.parse(match.group(1)!);
          if (h > 0) return h;
        }
        return 1080;
    }
  }

  int get _fps {
    if (!_customMode && _selectedPreset != null) {
      final preset = _getPreset(_selectedPreset!);
      if (preset != null) return preset.fps;
    }
    // v0.7.8: Parse the actual number — '24 FPS'/'10 FPS'/'15 FPS' used to
    // all export at 60 fps.
    final match = RegExp(r'^(\d+)').firstMatch(_selectedFps);
    if (match != null) {
      final fps = int.tryParse(match.group(1)!);
      if (fps != null && fps > 0) return fps;
    }
    return 60;
  }

  String get _formatExtension {
    if (!_customMode && _selectedPreset != null) {
      final preset = _getPreset(_selectedPreset!);
      if (preset != null) {
        if (preset.format == 'MP4') return 'mp4';
        if (preset.format == 'MOV') return 'mov';
        if (preset.format == 'GIF') return 'gif';
        if (preset.format == 'MP3') return 'mp3';
      }
    }
    if (_selectedFormat == 'MOV') return 'mov';
    if (_selectedFormat == 'GIF') return 'gif';
    if (_selectedFormat == 'MP3') return 'mp3';
    return 'mp4';
  }

  String get _nativeCodecName {
    if (!_customMode && _selectedPreset != null) {
      final preset = _getPreset(_selectedPreset!);
      if (preset != null) {
        switch (preset.codec) {
          case 'H.265': return 'h265';
          case 'VP9': return 'vp9';
          case 'ProRes': return 'prores';
          // v1.0.0: GIF/MP3 used to silently fall through to 'h264' —
          // sending H.264 bytes down a `.gif`/`.mp3` filename produced an
          // unusable file. Now they pass their intended codec through.
          case 'GIF': return 'gif';
          case 'MP3': return 'mp3';
          default: return 'h264';
        }
      }
    }
    switch (_selectedCodec) {
      case 'H.265': return 'h265';
      case 'VP9': return 'vp9';
      case 'ProRes': return 'prores';
      case 'GIF': return 'gif';
      case 'MP3': return 'mp3';
      default: return 'h264';
    }
  }

  /// v1.0.0: True for audio-only exports (custom MP3 or Audio Only preset) —
  /// used to skip the misleading "0×0 • 0 FPS" spec line.
  bool get _isAudioOnly {
    if (_customMode) return _selectedFormat == 'MP3';
    final p = _getPreset(_selectedPreset ?? '');
    return p != null && p.format == 'MP3';
  }

  String get _estimatedFileSize {
    final totalSeconds = widget.controller.durationMs ~/ 1000;
    if (totalSeconds <= 0) return 'Unknown';
    // v1.0.0: GIF and MP3 don't use a video bitrate — estimating with the
    // Mbps value reported absurd sizes (e.g. a 10s MP3 shown as 3.7 MB).
    if (_isAudioOnly) {
      final kbps = _exportBitrate ~/ 1000;
      final bytes = (kbps * 1000 ~/ 8) * totalSeconds;
      if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    final preset = _customMode ? null : _getPreset(_selectedPreset ?? '');
    final bitrate = (preset?.bitrateMbps ?? _bitrateMbps) * 1000000;
    final bits = bitrate * totalSeconds;
    final bytes = bits ~/ 8;
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  // v1.0.0: Format elapsed/positioned ms as "M:SS" — used by the audio-only
  // export progress row (the regular video path uses frame counts).
  String _formatTime(double ms) {
    final total = (ms / 1000).round().clamp(0, 1 << 30);
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// v1.0.0: Bitrate passed to the native engine for this export. For MP3
  /// audio-only exports, parse the user-selected kbps (e.g. "192 kbps")
  /// from the kbps dropdown; otherwise fall back to the preset's Mbps.
  int get _exportBitrate {
    if (_isAudioOnly) {
      if (_customMode && _selectedFps.endsWith('kbps')) {
        final m = RegExp(r'^(\d+)').firstMatch(_selectedFps);
        if (m != null) {
          final kbps = int.tryParse(m.group(1)!);
          if (kbps != null && kbps >= 32 && kbps <= 320) {
            return kbps * 1000;
          }
        }
      }
      // Preset path or unrecognized custom value: use the preset's kbps.
      final preset = _getPreset(_selectedPreset ?? '');
      if (preset != null) {
        return (preset.bitrateMbps * 1000000).toInt();
      }
      return 128000;
    }
    return ((_customMode ? _bitrateMbps : (_getPreset(_selectedPreset ?? '')?.bitrateMbps ?? 10.0)) * 1000000).toInt();
  }

  // v0.7.9: UX-01 — estimated time remaining, extrapolated from progress.
  String get _estimatedTimeRemaining {
    if (_exportStartTime == null || _exportProgress <= 0.01) return '--:--';
    final elapsedMs = DateTime.now().difference(_exportStartTime!).inMilliseconds;
    final totalMs = elapsedMs / _exportProgress;
    final remaining = Duration(milliseconds: totalMs.round() - elapsedMs);
    if (remaining <= Duration.zero) return '--:--';
    if (remaining.inHours > 0) {
      return '${remaining.inHours}:${remaining.inMinutes.remainder(60).toString().padLeft(2, '0')}:${remaining.inSeconds.remainder(60).toString().padLeft(2, '0')}';
    }
    return '${remaining.inMinutes}:${remaining.inSeconds.remainder(60).toString().padLeft(2, '0')}';
  }

  // v0.7.9: UX-01 — coarse phase label so the user knows what stage the
  // pipeline is at, not just a percentage.
  // v1.0.0: Audio-only exports never touch video frames — replacing the
  // misleading "Encoding video frames..." with audio-appropriate copy.
  String get _exportPhase {
    final p = _exportProgress;
    if (_isAudioOnly) {
      if (p < 0.2) return 'Initializing audio encoder...';
      if (p < 0.85) return 'Mixing & encoding audio...';
      return 'Finalizing MP3 file...';
    }
    if (p < 0.2) return 'Initializing encoder...';
    if (p < 0.5) return 'Encoding video frames...';
    if (p < 0.85) return 'Processing audio / muxing...';
    return 'Finalizing output...';
  }

  String get _aspectRatioLabel {
    final w = resWidth;
    final h = resHeight;
    // v1.0.2: Audio Only (MP3) has width/height 0 — guard the division
    // (_gcd(0,0) == 0 → `0 ~/ 0` threw IntegerDivisionByZeroException
    // on every rebuild while that preset was selected).
    if (w <= 0 || h <= 0) return 'Audio Only';
    final gcd = _gcd(w, h);
    return '${w ~/ gcd}:${h ~/ gcd}';
  }

  int _gcd(int a, int b) {
    while (b != 0) { final t = b; b = a % b; a = t; }
    return a;
  }

  Future<void> _pickOutputPath() async {
    try {
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Export to...',
        fileName: 'GhitaEdit_Export.$_formatExtension',
        type: FileType.custom,
        allowedExtensions: [_formatExtension],
      );
      if (result != null) {
        setState(() => _outputPath = result);
      }
    } catch (_) {}
  }

  void _applyPreset(String presetName) {
    setState(() {
      _selectedPreset = presetName;
      _customMode = presetName == 'Custom';
      if (!_customMode) {
        final preset = _presets.firstWhere((p) => p.name == presetName);
        _selectedFormat = preset.format;
        _selectedCodec = preset.codec;
        _bitrateMbps = preset.bitrateMbps.toDouble();
        _includeAudio = preset.includeAudio;
        // Map resolution
        if (preset.width == 3840) {
          _selectedRes = '4K (Ultra HD)';
        } else if (preset.width == 1280) {
          _selectedRes = '720p (HD)';
        } else {
          _selectedRes = '1080p (Full HD)';
        }
        _selectedFps = '${preset.fps} FPS';
      }
    });
  }

  void _startExport() {
    if (!_widgetReady) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('C++ Engine is not ready yet.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final outputPath = _outputPath ?? 'Videos/GhitaEdit_Export.$_formatExtension';

    setState(() {
      _isExporting = true;
      _exportProgress = 0.0;
      _exportFileSizeBytes = 0;
      _exportStartTime = DateTime.now();
    });

    final engineService = widget.controller.engineService;
    if (!engineService.isReady) {
      setState(() => _isExporting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Native engine not available.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final result = engineService.startExportEx(
      outputPath,
      resWidth,
      resHeight,
      _fps,
      _nativeCodecName,
      // v1.0.0: MP3 audio exports use the user-selected kbps (default 128),
      // not the video Mbps value. The native side honors this for codec=='mp3'
      // — it caps and clamps to the 32k–320k valid MP3 range.
      _exportBitrate,
      _includeAudio,
    );

    if (!result) {
      setState(() => _isExporting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Export failed to start.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    // Poll native export progress
    final bindings = engineService.bindings;
    final ctx = engineService.ctx;

    _progressTimer = Timer.periodic(const Duration(milliseconds: 150), (timer) {
      if (!mounted) {
        timer.cancel();
        bindings?.cancelExport(ctx);
        return;
      }

      // v1.0.1: Null-safe — bindings may be null if the native library
      // failed to load. Previously `bindings!.isExporting` threw NPE here.
      if (bindings == null || ctx == nullptr) {
        timer.cancel();
        setState(() => _isExporting = false);
        return;
      }

      final isExporting = bindings.isExporting(ctx);
      final progress = bindings.getExportProgress(ctx);
      final fileSize = engineService.getExportFileSize();

      setState(() {
        _exportProgress = progress.clamp(0.0, 1.0);
        _exportFileSizeBytes = fileSize;
      });

      if (!isExporting || _exportProgress >= 1.0) {
        timer.cancel();
        // v0.7.8: C++ sets progress=1.0 ONLY on success and stores the file
        // size before finishing — so a sub-1.0 progress or empty output means
        // the pipeline failed silently (bad path, missing codec, avio error).
        final success = _exportProgress >= 1.0 && _exportFileSizeBytes > 0;
        setState(() {
          _isExporting = false;
          if (success) _exportProgress = 1.0;
        });
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? 'Export completed! Saved to: $outputPath'
                  : 'Export failed — check output path and codec support.',
            ),
            backgroundColor: success ? Colors.green : Colors.redAccent,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    });
  }

  void _cancelExport() {
    _progressTimer?.cancel();
    final engineService = widget.controller.engineService;
    // v1.0.1: Null-safe — ctx may be nullptr when no native engine.
    final ctx = engineService.ctx;
    if (ctx != nullptr) {
      engineService.bindings?.cancelExport(ctx);
    }
    setState(() {
      _isExporting = false;
      _exportProgress = 0.0;
    });
  }

  bool get _widgetReady => widget.controller.isEngineReady;

  List<String> get _codecOptions {
    if (!_customMode) return [];
    switch (_selectedFormat) {
      case 'MOV': return ['H.264']; // v1.1.0 (PLAN 3.10): ProRes removed — the engine fails loudly when the build lacks the encoder, but the preset UI no longer advertises it.
      // v1.1.0 (PLAN 3.12): 'GIF' case removed — no GIF container support.
      case 'MP3': return ['MP3'];
      default: return ['H.264', 'H.265', 'VP9'];
    }
  }

  @override
  Widget build(BuildContext context) {
    // v0.7.8: While exporting, block dismissal (barrier click / Esc / back) —
    // the native export thread used to keep running orphaned, with no UI left
    // to cancel or report completion. Dismissal now cancels the export first.
    // (PopScope intercepts barrier taps too, so no barrierDismissible needed.)
    return PopScope(
      canPop: !_isExporting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isExporting) {
          _cancelExport();
        }
      },
      child: AlertDialog(
      backgroundColor: AppTheme.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.output, color: AppTheme.accent),
          const SizedBox(width: 8),
          const Text('Export Media Project', style: TextStyle(color: AppTheme.textMain, fontSize: 16)),
          const Spacer(),
          if (!_isExporting)
            Text(
              '${widget.controller.project.allClips.length} clips',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
            ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: _isExporting ? _buildExportingView() : _buildSettingsView(),
      ),
      actions: _isExporting
          ? [
              TextButton(
                onPressed: _cancelExport,
                child: const Text('Cancel Export', style: TextStyle(color: Colors.redAccent)),
              ),
            ]
          : [
              TextButton(
                child: const Text('Cancel'),
                onPressed: () => Navigator.pop(context),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.rocket_launch, size: 16),
                label: const Text('Start Export'),
                onPressed: _startExport,
              ),
            ],
      ),
    );
  }

  Widget _buildExportingView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.engineering, color: AppTheme.accent, size: 48),
        const SizedBox(height: 12),
        const Text(
          'Rendering via C++ Engine Pipeline...',
          style: TextStyle(color: AppTheme.textMain, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          // v1.0.0: Audio-only exports hide the misleading "0×0 • 0 FPS" line.
          _isAudioOnly
              ? 'Audio only • $_nativeCodecName'
              : '${resWidth}x$resHeight • $_fps FPS • $_nativeCodecName',
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: _exportProgress,
            backgroundColor: AppTheme.surface,
            color: AppTheme.accent,
            minHeight: 12,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${(_exportProgress * 100).toInt()}% completed',
              style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.bold),
            ),
            // v0.7.9: UX-01 — ETA alongside elapsed time.
            Text(
              'ETA: $_estimatedTimeRemaining',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              // v1.0.0: Audio-only exports show mm:ss progress instead of
              // "Frame X / N" (the FPS field is repurposed for kbps in MP3
              // mode, so the frame formula would be meaningless).
              _isAudioOnly
                  ? _formatTime(_exportProgress * widget.controller.durationMs)
                  : 'Frame ${(_exportProgress * widget.controller.durationMs / 1000 * _fps).toInt()} / ${(widget.controller.durationMs / 1000 * _fps).toInt()}',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
            ),
            if (_exportFileSizeBytes > 0)
              Text(
                'File size: ${(_exportFileSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB',
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
              ),
          ],
        ),
        // v0.7.9: UX-01 — pipeline stage indicator.
        const SizedBox(height: 8),
        Text(
          _exportPhase,
          style: const TextStyle(color: AppTheme.accent, fontSize: 10, fontStyle: FontStyle.italic),
        ),
      ],
    );
  }

  Widget _buildSettingsView() {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // v0.5.5: Preset chips row
          const Text('Export Presets', style: TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _presets.map((preset) {
                final isSelected = _selectedPreset == preset.name && !_customMode;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _PresetChip(
                    label: preset.label,
                    icon: preset.icon,
                    description: preset.description,
                    isSelected: isSelected,
                    onTap: () => _applyPreset(preset.name),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 12),

          // v0.7.0: Custom settings (shown when _customMode or any preset selected for detail)
          if (_customMode) ...[
            if (_selectedFormat != 'GIF' && _selectedFormat != 'MP3') ...[
              _buildDropdown('Resolution', _selectedRes,
                  ['720p (HD)', '1080p (Full HD)', '4K (Ultra HD)'], _onResolutionChanged, Icons.video_settings),
              const SizedBox(height: 10),
              _buildDropdown('Frame Rate', _selectedFps,
                  ['24 FPS', '30 FPS', '60 FPS'], _onFpsChanged, Icons.movie),
            ] else if (_selectedFormat == 'GIF') ...[
              _buildDropdown('GIF Size', _selectedRes,
                  ['240p', '360p', '480p', '720p'], _onResolutionChanged, Icons.aspect_ratio),
              const SizedBox(height: 10),
              _buildDropdown('GIF FPS', _selectedFps,
                  ['10 FPS', '15 FPS', '24 FPS'], _onFpsChanged, Icons.movie),
            ] else if (_selectedFormat == 'MP3') ...[
              _buildDropdown('Audio Bitrate', _selectedFps,
                  ['128 kbps', '192 kbps', '256 kbps', '320 kbps'], _onBitrateQualityChanged, Icons.audiotrack),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 10),

            if (_selectedFormat != 'GIF' && _selectedFormat != 'MP3') ...[
              // v1.1.0 (PLAN 3.12): GIF removed from the container list —
              // the engine cannot encode it (pal8 palette requirement).
              _buildDropdown('Container Format', _selectedFormat,
                  ['MP4', 'MOV', 'MP3'], _onFormatChanged, Icons.file_present),

              if (_selectedFormat != 'GIF' && _selectedFormat != 'MP3') ...[
                const SizedBox(height: 10),
                _buildDropdown('Video Codec', _selectedCodec,
                    _codecOptions, _onCodecChanged, Icons.code),
              ],

              if (_selectedFormat != 'GIF' && _selectedFormat != 'MP3') ...[
                const SizedBox(height: 10),
                _buildSlider('Bitrate: ${_bitrateMbps.toStringAsFixed(0)} Mbps',
                    _bitrateMbps, 1.0, 50.0, _onBitrateChanged),
              ],

              if (_selectedFormat != 'GIF' && _selectedFormat != 'MP3') ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.audiotrack, color: AppTheme.textMuted, size: 16),
                    const SizedBox(width: 6),
                    const Text('Include Audio', style: TextStyle(color: AppTheme.textMain, fontSize: 13)),
                    const Spacer(),
                    Switch(
                      value: _includeAudio,
                      onChanged: (v) => setState(() => _includeAudio = v),
                      activeThumbColor: AppTheme.primary,
                    ),
                  ],
                ),
              ],
            ],
          ],

          // Always show aspect ratio info
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Row(
              children: [
                const Icon(Icons.aspect_ratio, color: AppTheme.accent, size: 16),
                const SizedBox(width: 8),
                Text(
                  _selectedFormat == 'MP3'
                      ? 'Audio-only export (no video)'
                      : '$_aspectRatioLabel aspect ratio',
                  style: const TextStyle(color: AppTheme.textMain, fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  _selectedFormat == 'MP3'
                      ? '44.1 kHz • Stereo'
                      : '${resWidth}x$resHeight',
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, fontFamily: 'monospace'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Estimated file size
          Row(
            children: [
              const Icon(Icons.storage, color: AppTheme.textMuted, size: 16),
              const SizedBox(width: 6),
              Text(
                'Estimated size: $_estimatedFileSize',
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Output path selector
          Row(
            children: [
              const Icon(Icons.folder_open, color: AppTheme.textMuted, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _outputPath ?? 'Videos/GhitaEdit_Export.$_formatExtension',
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: _pickOutputPath,
                child: const Text('Browse...', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),

          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                _widgetReady ? Icons.check_circle_outline : Icons.error_outline,
                color: _widgetReady ? Colors.green : Colors.redAccent,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                _widgetReady
                    ? 'Engine ready • ${widget.controller.project.allClips.length} clips queued'
                    : 'Engine not ready — export disabled',
                style: TextStyle(
                  fontSize: 11,
                  color: _widgetReady ? AppTheme.textMuted : Colors.redAccent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _onResolutionChanged(String? val) { if (val != null) setState(() => _selectedRes = val); }
  void _onFpsChanged(String? val) {
    if (val != null) {
      setState(() {
        _selectedFps = val;
        if (val.contains('24')) {
          _selectedFps = '24 FPS';
        } else if (val.contains('30')) {
          _selectedFps = '30 FPS';
        } else if (val.contains('60')) {
          _selectedFps = '60 FPS';
        } else if (val.contains('15')) {
          _selectedFps = '15 FPS';
        } else if (val.contains('10')) {
          _selectedFps = '10 FPS';
        } else {
          _selectedFps = val;
        }
      });
    }
  }
  void _onBitrateQualityChanged(String? val) { if (val != null) setState(() => _selectedFps = val); }
  void _onFormatChanged(String? val) {
    if (val != null) {
      setState(() {
        _selectedFormat = val;
        if (val == 'GIF') {
          _selectedCodec = 'GIF';
          _selectedRes = '480p';
          _selectedFps = '15 FPS';
        } else if (val == 'MP3') {
          _selectedCodec = 'MP3';
          _selectedFps = '320 kbps';
        } else if (val == 'MOV') {
          _selectedCodec = 'H.264';
          _selectedRes = '1080p (Full HD)';
          _selectedFps = '60 FPS';
        } else {
          _selectedCodec = 'H.264';
          _selectedRes = '1080p (Full HD)';
          _selectedFps = '60 FPS';
        }
      });
    }
  }
  void _onCodecChanged(String? val) { if (val != null) setState(() => _selectedCodec = val); }
  void _onBitrateChanged(double val) { setState(() => _bitrateMbps = val); }

  Widget _buildDropdown(String label, String value, List<String> items,
                        ValueChanged<String?> onChanged, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: AppTheme.textMuted, size: 14),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.divider),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              dropdownColor: AppTheme.surface,
              style: const TextStyle(color: AppTheme.textMain, fontSize: 13),
              items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSlider(String label, double value, double min, double max,
                      ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppTheme.primary,
            inactiveTrackColor: AppTheme.divider,
            thumbColor: AppTheme.primary,
            valueIndicatorColor: AppTheme.primary,
            valueIndicatorTextStyle: const TextStyle(color: Colors.white, fontSize: 11),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: 49,
            label: '${value.toStringAsFixed(0)} Mbps',
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

// ========== Export Preset Model — v0.5.5 ==========

class ExportPreset {
  final String name;
  final String label;
  final IconData icon;
  final int width;
  final int height;
  final int fps;
  final String format;
  final String codec;
  final double bitrateMbps;
  final bool includeAudio;
  final String description;

  const ExportPreset({
    required this.name,
    required this.label,
    required this.icon,
    required this.width,
    required this.height,
    required this.fps,
    required this.format,
    required this.codec,
    required this.bitrateMbps,
    required this.includeAudio,
    required this.description,
  });
}

// ========== Preset Chip Widget — v0.5.5 ==========

class _PresetChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final String description;
  final bool isSelected;
  final VoidCallback onTap;

  const _PresetChip({
    required this.label,
    required this.icon,
    required this.description,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary.withValues(alpha: 0.25) : AppTheme.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppTheme.accent : AppTheme.divider,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: isSelected ? AppTheme.accent : AppTheme.textMuted),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? AppTheme.accent : AppTheme.textMain,
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
            if (description.isNotEmpty)
              Text(
                description,
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 9,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
