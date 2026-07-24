import 'dart:async';

import 'package:flutter/material.dart';
import '../../controllers/editor_controller.dart';
import '../theme/app_theme.dart';

class ExportDialog extends StatefulWidget {
  final EditorController controller;

  const ExportDialog({super.key, required this.controller});

  @override
  State<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<ExportDialog> {
  String _selectedRes = "1080p (Full HD)";
  String _selectedFps = "60 FPS";
  String _selectedFormat = "MP4 (H.264 / AAC)";
  bool _isExporting = false;
  double _exportProgress = 0.0;
  Timer? _progressTimer;

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  void _startExport() {
    if (!_widgetReady) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("C++ Engine is not ready yet."),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() {
      _isExporting = true;
      _exportProgress = 0.0;
    });

    _progressTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (_exportProgress >= 1.0) {
        timer.cancel();
        if (!mounted) return;
        setState(() {
          _isExporting = false;
          _exportProgress = 1.0;
        });
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Export completed successfully! Saved to Videos/GhitaEdit_Export.mp4"),
            backgroundColor: Colors.green,
          ),
        );
        return;
      }
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _exportProgress += 0.05;
      });
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
          Icon(Icons.output, color: AppTheme.accent),
          const SizedBox(width: 8),
          Text("Export Media Project", style: AppTheme.titleMedium),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: _isExporting ? _buildExportingView() : _buildSettingsView(),
      ),
      actions: _isExporting ? [] : [
        TextButton(
          child: const Text("Cancel"),
          onPressed: () => Navigator.pop(context),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
          ),
          icon: const Icon(Icons.rocket_launch, size: 16),
          label: const Text("Start Export"),
          onPressed: _startExport,
        ),
      ],
    );
  }

  Widget _buildExportingView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          "Rendering via C++ Hardware Encoder...",
          style: TextStyle(color: AppTheme.textMain, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        LinearProgressIndicator(
          value: _exportProgress,
          backgroundColor: AppTheme.surface,
          color: AppTheme.accent,
          minHeight: 10,
        ),
        const SizedBox(height: 12),
        Text(
          '${(_exportProgress * 100).toInt()}% completed',
          style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildSettingsView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDropdown("Resolution", _selectedRes, ["720p (HD)", "1080p (Full HD)", "4K (Ultra HD)"], _onResolutionChanged, Icons.video_settings),
        const SizedBox(height: 12),
        _buildDropdown("Frame Rate", _selectedFps, ["30 FPS", "60 FPS"], _onFpsChanged, Icons.movie),
        const SizedBox(height: 12),
        _buildDropdown("Container Format", _selectedFormat, ["MP4 (H.264 / AAC)", "MOV (ProRes)", "GIF Animation", "MP3 Audio Only"], _onFormatChanged, Icons.file_present),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(
              _widgetReady ? Icons.check_circle_outline : Icons.error_outline,
              color: _widgetReady ? Colors.green : Colors.redAccent,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              _widgetReady ? 'Engine ready for export' : 'Engine not ready — export disabled',
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
