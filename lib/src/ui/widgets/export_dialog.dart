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

  void _startExport() {
    setState(() {
      _isExporting = true;
      _exportProgress = 0.0;
    });

    // Simulate fast rendering progress
    Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return false;
      setState(() {
        _exportProgress += 0.05;
      });
      if (_exportProgress >= 1.0) {
        setState(() {
          _isExporting = false;
        });
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Export completed successfully! Saved to Videos/GhitaEdit_Export.mp4"),
            backgroundColor: Colors.green,
          ),
        );
        return false;
      }
      return true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: const [
          Icon(Icons.output, color: AppTheme.accent),
          SizedBox(width: 8),
          Text("Export Media Project", style: TextStyle(color: AppTheme.textMain, fontSize: 16)),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: _isExporting
            ? Column(
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
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDropdown("Resolution", _selectedRes, ["720p (HD)", "1080p (Full HD)", "4K (Ultra HD)"], (val) => setState(() => _selectedRes = val!)),
                  const SizedBox(height: 12),
                  _buildDropdown("Frame Rate", _selectedFps, ["30 FPS", "60 FPS"], (val) => setState(() => _selectedFps = val!)),
                  const SizedBox(height: 12),
                  _buildDropdown("Container Format", _selectedFormat, ["MP4 (H.264 / AAC)", "MOV (ProRes)", "GIF Animation", "MP3 Audio Only"], (val) => setState(() => _selectedFormat = val!)),
                ],
              ),
      ),
      actions: _isExporting
          ? []
          : [
              TextButton(
                child: const Text("Cancel", style: TextStyle(color: AppTheme.textMuted)),
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

  Widget _buildDropdown(String label, String value, List<String> items, ValueChanged<String?> onChanged) {
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
