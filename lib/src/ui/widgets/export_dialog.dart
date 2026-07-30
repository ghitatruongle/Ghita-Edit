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

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  int get resWidth {
    switch (_selectedRes) {
      case '720p (HD)': return 1280;
      case '4K (Ultra HD)': return 3840;
      default: return 1920;
    }
  }

  int get resHeight {
    switch (_selectedRes) {
      case '720p (HD)': return 720;
      case '4K (Ultra HD)': return 2160;
      default: return 1080;
    }
  }

  int get _fps {
    return _selectedFps.startsWith('30') ? 30 : 60;
  }

  String get _formatExtension {
    if (_selectedFormat == 'MOV') return 'mov';
    if (_selectedFormat == 'GIF') return 'gif';
    if (_selectedFormat == 'MP3') return 'mp3';
    return 'mp4';
  }

  String get _nativeCodecName {
    switch (_selectedCodec) {
      case 'H.265': return 'h265';
      case 'VP9': return 'vp9';
      default: return 'h264';
    }
  }

  String get _estimatedFileSize {
    // Rough estimate: bitrate * duration / 8
    final totalSeconds = widget.controller.durationMs ~/ 1000;
    if (totalSeconds <= 0) return 'Unknown';
    final bits = _bitrateMbps * 1000000 * totalSeconds;
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

    // v0.4.5: Use extended export with codec/bitrate/audio
    final result = engineService.startExportEx(
      outputPath,
      resWidth,
      resHeight,
      _fps,
      _nativeCodecName,
      (_bitrateMbps * 1000000).toInt(),
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

  // v0.4.5: Codec options by format
  List<String> get _codecOptions {
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
        width: 480,
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
          '$_selectedRes • $_selectedFps • $_selectedCodec',
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
          _buildDropdown('Resolution', _selectedRes,
              ['720p (HD)', '1080p (Full HD)', '4K (Ultra HD)'], _onResolutionChanged, Icons.video_settings),
          const SizedBox(height: 10),
          _buildDropdown('Frame Rate', _selectedFps,
              ['30 FPS', '60 FPS'], _onFpsChanged, Icons.movie),
          const SizedBox(height: 10),
          _buildDropdown('Container Format', _selectedFormat,
              ['MP4', 'MOV', 'GIF', 'MP3'], _onFormatChanged, Icons.file_present),

          // v0.4.5: Codec selector
          if (_selectedFormat != 'GIF' && _selectedFormat != 'MP3') ...[
            const SizedBox(height: 10),
            _buildDropdown('Video Codec', _selectedCodec,
                _codecOptions, _onCodecChanged, Icons.code),
          ],

          // v0.4.5: Bitrate slider
          if (_selectedFormat != 'GIF' && _selectedFormat != 'MP3') ...[
            const SizedBox(height: 10),
            _buildSlider('Bitrate: ${_bitrateMbps.toStringAsFixed(0)} Mbps',
                _bitrateMbps, 1.0, 50.0, _onBitrateChanged),
          ],

          // v0.4.5: Include audio toggle
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

          const SizedBox(height: 6),

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
        // Auto-select codec based on format
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
