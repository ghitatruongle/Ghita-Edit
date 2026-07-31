import 'dart:async';

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

  // v0.5.5: Export presets
  static const _presets = <ExportPreset>[
    ExportPreset(
      name: 'YouTube 1080p',
      label: 'YouTube 1080p',
      icon: Icons.play_circle_filled,
      width: 1920, height: 1080, fps: 60,
      format: 'MP4', codec: 'H.264', bitrateMbps: 10, includeAudio: true,
      description: 'H.264 • 10 Mbps • 60fps',
    ),
    ExportPreset(
      name: 'YouTube 4K',
      label: 'YouTube 4K',
      icon: Icons.high_quality,
      width: 3840, height: 2160, fps: 60,
      format: 'MP4', codec: 'H.265', bitrateMbps: 35, includeAudio: true,
      description: 'H.265 • 35 Mbps • 60fps',
    ),
    ExportPreset(
      name: 'TikTok 9:16',
      label: 'TikTok / Reels',
      icon: Icons.smartphone,
      width: 1080, height: 1920, fps: 30,
      format: 'MP4', codec: 'H.264', bitrateMbps: 8, includeAudio: true,
      description: '9:16 • H.264 • 8 Mbps • 30fps',
    ),
    ExportPreset(
      name: 'Instagram 1:1',
      label: 'Instagram 1:1',
      icon: Icons.camera,
      width: 1080, height: 1080, fps: 30,
      format: 'MP4', codec: 'H.264', bitrateMbps: 6, includeAudio: true,
      description: '1:1 • H.264 • 6 Mbps • 30fps',
    ),
    ExportPreset(
      name: 'Twitter 720p',
      label: 'Twitter / X',
      icon: Icons.chat,
      width: 1280, height: 720, fps: 30,
      format: 'MP4', codec: 'H.264', bitrateMbps: 5, includeAudio: true,
      description: '720p • H.264 • 5 Mbps • 30fps',
    ),
    ExportPreset(
      name: 'Web VP9',
      label: 'Web (VP9)',
      icon: Icons.public,
      width: 1920, height: 1080, fps: 30,
      format: 'MP4', codec: 'VP9', bitrateMbps: 8, includeAudio: true,
      description: 'VP9 • 8 Mbps • 30fps',
    ),
    ExportPreset(
      name: 'Archive ProRes',
      label: 'Archive (ProRes)',
      icon: Icons.archive,
      width: 1920, height: 1080, fps: 60,
      format: 'MOV', codec: 'ProRes', bitrateMbps: 200, includeAudio: true,
      description: 'ProRes • 200 Mbps • 60fps • MOV',
    ),
    ExportPreset(
      name: 'Custom',
      label: 'Custom...',
      icon: Icons.tune,
      width: 1920, height: 1080, fps: 60,
      format: 'MP4', codec: 'H.264', bitrateMbps: 10, includeAudio: true,
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
      default: return 1920;
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
      default: return 1080;
    }
  }

  int get _fps {
    if (!_customMode && _selectedPreset != null) {
      final preset = _getPreset(_selectedPreset!);
      if (preset != null) return preset.fps;
    }
    return _selectedFps.startsWith('30') ? 30 : 60;
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
          default: return 'h264';
        }
      }
    }
    switch (_selectedCodec) {
      case 'H.265': return 'h265';
      case 'VP9': return 'vp9';
      case 'ProRes': return 'prores';
      default: return 'h264';
    }
  }

  String get _estimatedFileSize {
    final totalSeconds = widget.controller.durationMs ~/ 1000;
    if (totalSeconds <= 0) return 'Unknown';
    final preset = _customMode ? null : _getPreset(_selectedPreset ?? '');
    final bitrate = (preset?.bitrateMbps ?? _bitrateMbps.toInt()).toDouble() * 1000000;
    final bits = bitrate * totalSeconds;
    final bytes = bits ~/ 8;
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String get _elapsedTime {
    if (_exportStartTime == null) return '--:--';
    final elapsed = DateTime.now().difference(_exportStartTime!);
    if (elapsed.inHours > 0) {
      return '${elapsed.inHours}:${elapsed.inMinutes.remainder(60).toString().padLeft(2, '0')}:${elapsed.inSeconds.remainder(60).toString().padLeft(2, '0')}';
    }
    return '${elapsed.inMinutes}:${elapsed.inSeconds.remainder(60).toString().padLeft(2, '0')}';
  }

  String get _aspectRatioLabel {
    final w = resWidth;
    final h = resHeight;
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
      (_customMode ? _bitrateMbps : (_getPreset(_selectedPreset ?? '')?.bitrateMbps ?? 10)) * 1000000 ~/ 1,
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

      final isExporting = bindings!.isExporting(ctx);
      final progress = bindings.getExportProgress(ctx);
      final fileSize = engineService.getExportFileSize();

      setState(() {
        _exportProgress = progress.clamp(0.0, 1.0);
        _exportFileSizeBytes = fileSize;
      });

      if (!isExporting || _exportProgress >= 1.0) {
        timer.cancel();
        setState(() {
          _isExporting = false;
          _exportProgress = 1.0;
        });
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export completed! Saved to: $outputPath'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    });
  }

  void _cancelExport() {
    _progressTimer?.cancel();
    final engineService = widget.controller.engineService;
    engineService.bindings?.cancelExport(engineService.ctx);
    setState(() {
      _isExporting = false;
      _exportProgress = 0.0;
    });
  }

  bool get _widgetReady => widget.controller.isEngineReady;

  List<String> get _codecOptions {
    if (!_customMode) return [];
    switch (_selectedFormat) {
      case 'MOV': return ['H.264', 'ProRes'];
      case 'GIF': return ['GIF'];
      case 'MP3': return ['MP3'];
      default: return ['H.264', 'H.265', 'VP9'];
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
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
          '${resWidth}x$resHeight • $_fps FPS • $_nativeCodecName',
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
            Text(
              'Elapsed: $_elapsedTime',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Frame ${(_exportProgress * widget.controller.durationMs / 1000 * _fps).toInt()} / ${(widget.controller.durationMs / 1000 * _fps).toInt()}',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
            ),
            if (_exportFileSizeBytes > 0)
              Text(
                'File size: ${(_exportFileSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB',
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
              ),
          ],
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

          // Custom settings (shown when _customMode or any preset selected for detail)
          if (_customMode) ...[
            _buildDropdown('Resolution', _selectedRes,
                ['720p (HD)', '1080p (Full HD)', '4K (Ultra HD)'], _onResolutionChanged, Icons.video_settings),
            const SizedBox(height: 10),
            _buildDropdown('Frame Rate', _selectedFps,
                ['30 FPS', '60 FPS'], _onFpsChanged, Icons.movie),
            const SizedBox(height: 10),
            _buildDropdown('Container Format', _selectedFormat,
                ['MP4', 'MOV', 'GIF', 'MP3'], _onFormatChanged, Icons.file_present),

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
                  '$_aspectRatioLabel aspect ratio',
                  style: const TextStyle(color: AppTheme.textMain, fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  '${resWidth}x$resHeight',
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
  void _onFpsChanged(String? val) { if (val != null) setState(() => _selectedFps = val); }
  void _onFormatChanged(String? val) {
    if (val != null) {
      setState(() {
        _selectedFormat = val;
        if (val == 'GIF') {
          _selectedCodec = 'GIF';
        } else if (val == 'MP3') {
          _selectedCodec = 'MP3';
        } else if (val == 'MOV') {
          _selectedCodec = 'H.264';
        } else {
          _selectedCodec = 'H.264';
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
  final int bitrateMbps;
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
