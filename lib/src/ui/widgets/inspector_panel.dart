import 'package:flutter/material.dart';
import '../../controllers/editor_controller.dart';
import '../theme/app_theme.dart';

class InspectorPanel extends StatelessWidget {
  final EditorController controller;

  const InspectorPanel({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.all(12),
      child: ListView(
        children: [
          const Text(
            "PROPERTIES INSPECTOR",
            style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 12),

          // File Info Card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.video_file, color: AppTheme.accent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        controller.currentMediaName,
                        style: const TextStyle(
                          color: AppTheme.textMain,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(color: AppTheme.divider, height: 16),
                _buildMetaRow("Resolution", "1280 x 720 (720p)"),
                _buildMetaRow("FPS", "60 FPS (Hardware Accel)"),
                _buildMetaRow("Codec", "H.264 / AAC (FFmpeg)"),
                _buildMetaRow("Engine", controller.engineVersion),
              ],
            ),
          ),

          const SizedBox(height: 16),
          const Text(
            "ACTIVE FILTER & FX",
            style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        _getFilterName(controller.activeFilterType),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppTheme.textMain, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 18, color: AppTheme.textMuted),
                      onPressed: () => controller.setFilter(0, 1.0),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text("Filter Intensity", style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                Slider(
                  value: controller.filterIntensity,
                  min: 0.0,
                  max: 1.0,
                  activeColor: AppTheme.primaryLight,
                  onChanged: (val) => controller.setFilter(controller.activeFilterType, val),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          const Text(
            "AUDIO MIXER & GAIN",
            style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Master Volume", style: TextStyle(color: AppTheme.textMain, fontSize: 12)),
                    Text(
                      '${(controller.volume * 100).toInt()}%',
                      style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Slider(
                  value: controller.volume,
                  min: 0.0,
                  max: 1.5,
                  activeColor: AppTheme.accent,
                  onChanged: controller.setVolume,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getFilterName(int type) {
    switch (type) {
      case 1: return "Grayscale Shader";
      case 2: return "Warm Sepia Shader";
      case 3: return "Invert Color Shader";
      default: return "Original (Pass-through)";
    }
  }

  Widget _buildMetaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.textMain, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
