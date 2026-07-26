import 'dart:async';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:ffi/ffi.dart';
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
  String _selectedFormat = 'MP4 (H.264 / AAC)';
  String? _outputPath;
  bool _isExporting = false;
  double _exportProgress = 0.0;
  Timer? _progressTimer;

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
    if (_selectedFormat.contains('MOV')) return 'mov';
    if (_selectedFormat.contains('GIF')) return 'gif';
    if (_selectedFormat.contains('MP3')) return 'mp3';
    return 'mp4';
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

    // Default output path if not selected
    final outputPath = _outputPath ?? 'Videos/GhitaEdit_Export.$_formatExtension';

    setState(() {
      _isExporting = true;
      _exportProgress = 0.0;
    });

    // Start the native export pipeline via FFI
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

    // Call native startExport
    final result = engineService.bindings!.startExport(
      engineService.ctx,
      outputPath.toNativeUtf8(),
      resWidth,
      resHeight,
      _fps,
    );

    if (result != 0) {
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
    _progressTimer = Timer.periodic(const Duration(milliseconds: 150), (timer) {
      if (!mounted) {
        timer.cancel();
        engineService.bindings!.cancelExport(engineService.ctx);
        return;
      }

      final isExporting = engineService.bindings!.isExporting(engineService.ctx);
      final progress = engineService.bindings!.getExportProgress(engineService.ctx);

      setState(() {
        _exportProgress = progress.clamp(0.0, 1.0);
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
    setState(() {
      _isExporting = false;
      _exportProgress = 0.0;
    });
  }

  bool get _widgetReady => widget.controller.isEngineReady;

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
        width: 450,
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
          '$_selectedRes • $_selectedFps • $_selectedFormat',
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
              'Frame ${(_exportProgress * widget.controller.durationMs / 1000 * _fps).toInt()} / ${(widget.controller.durationMs / 1000 * _fps).toInt()}',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSettingsView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDropdown('Resolution', _selectedRes, ['720p (HD)', '1080p (Full HD)', '4K (Ultra HD)'], _onResolutionChanged, Icons.video_settings),
        const SizedBox(height: 12),
        _buildDropdown('Frame Rate', _selectedFps, ['30 FPS', '60 FPS'], _onFpsChanged, Icons.movie),
        const SizedBox(height: 12),
        _buildDropdown('Container Format', _selectedFormat, ['MP4 (H.264 / AAC)', 'MOV (ProRes)', 'GIF Animation', 'MP3 Audio Only'], _onFormatChanged, Icons.file_present),
        const SizedBox(height: 12),

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
              _widgetReady ? 'Engine ready • ${widget.controller.project.allClips.length} clips queued' : 'Engine not ready — export disabled',
              style: TextStyle(
                fontSize: 11,
                color: _widgetReady ? AppTheme.textMuted : Colors.redAccent,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _onResolutionChanged(String? val) { if (val != null) setState(() => _selectedRes = val); }
  void _onFpsChanged(String? val) { if (val != null) setState(() => _selectedFps = val); }
  void _onFormatChanged(String? val) { if (val != null) setState(() => _selectedFormat = val); }

  Widget _buildDropdown(String label, String value, List<String> items, ValueChanged<String?> onChanged, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
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
}
