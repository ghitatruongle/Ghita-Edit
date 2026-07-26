import 'package:flutter/material.dart';
import '../../controllers/editor_controller.dart';
import '../../models/clip.dart';
import '../theme/app_theme.dart';

class InspectorPanel extends StatelessWidget {
  final EditorController controller;

  const InspectorPanel({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final selectedClip = controller.selectedClip;

    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.all(12),
      child: ListView(
        children: [
          const Text(
            'PROPERTIES INSPECTOR',
            style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 12),

          // Selected Clip Info
          _buildClipInfoCard(selectedClip),

          const SizedBox(height: 16),

          // Project Info
          _buildProjectInfoCard(),

          const SizedBox(height: 16),
          const Text(
            'ACTIVE FILTER & FX',
            style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 8),

          _buildFilterCard(),

          const SizedBox(height: 16),
          const Text(
            'AUDIO MIXER & GAIN',
            style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 8),

          _buildAudioMixerCard(),
        ],
      ),
    );
  }

  Widget _buildClipInfoCard(Clip? clip) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: clip != null ? AppTheme.accent : AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                clip != null ? Icons.video_file : Icons.info_outline,
                color: clip != null ? AppTheme.accent : AppTheme.textMuted,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  clip?.displayName ?? 'No clip selected',
                  style: TextStyle(
                    color: clip != null ? AppTheme.textMain : AppTheme.textMuted,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          if (clip != null) ...[
            const Divider(color: AppTheme.divider, height: 16),
            _buildMetaRow('Type', clip.type.name.toUpperCase()),
            _buildMetaRow('Timeline Start', _formatMs(clip.timelineStartMs)),
            _buildMetaRow('Duration', _formatMs(clip.durationMs)),
            _buildMetaRow('Source In', _formatMs(clip.sourceInMs)),
            _buildMetaRow('Source Out', _formatMs(clip.sourceOutMs)),
            _buildMetaRow('Track', 'Track ${clip.trackIndex + 1}'),
            _buildMetaRow('Filter', _getFilterName(clip.filterType)),
          ] else ...[
            const Divider(color: AppTheme.divider, height: 16),
            _buildMetaRow('Hint', 'Click a clip on the timeline'),
            _buildMetaRow('Engine', controller.engineVersion),
          ],
        ],
      ),
    );
  }

  Widget _buildProjectInfoCard() {
    final project = controller.project;
    return Container(
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
              const Icon(Icons.folder_special, color: AppTheme.primaryLight, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  project.name,
                  style: const TextStyle(color: AppTheme.textMain, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildMetaRow('Version', project.version),
          _buildMetaRow('Clips', '${project.allClips.length}'),
          _buildMetaRow('Tracks', '${project.tracks.length}'),
          _buildMetaRow('Duration', _formatMs(project.totalDurationMs)),
          _buildMetaRow('Output', '${project.outputWidth}x${project.outputHeight} @ ${project.outputFps}fps'),
        ],
      ),
    );
  }

  Widget _buildFilterCard() {
    return Container(
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
          const Text('Filter Intensity', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
          Slider(
            value: controller.filterIntensity,
            min: 0.0,
            max: 1.0,
            activeColor: AppTheme.primaryLight,
            onChanged: (val) => controller.setFilter(controller.activeFilterType, val),
          ),
          // Quick filter buttons
          Wrap(
            spacing: 4,
            children: [
              _filterChip('None', 0),
              _filterChip('Gray', 1),
              _filterChip('Sepia', 2),
              _filterChip('Invert', 3),
              _filterChip('Bright', 4),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, int type) {
    final isActive = controller.activeFilterType == type;
    return GestureDetector(
      onTap: () => controller.setFilter(type, controller.filterIntensity),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.primary.withValues(alpha: 0.3) : AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isActive ? AppTheme.accent : AppTheme.divider),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? AppTheme.accent : AppTheme.textMuted,
            fontSize: 10,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildAudioMixerCard() {
    return Container(
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
              const Text('Master Volume', style: TextStyle(color: AppTheme.textMain, fontSize: 12)),
              Text(
                '${(controller.volume * 100).toInt()}%',
                style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          Slider(
            value: controller.volume.clamp(0.0, 2.0),
            min: 0.0,
            max: 2.0,
            activeColor: AppTheme.accent,
            onChanged: controller.setVolume,
          ),
        ],
      ),
    );
  }

  String _getFilterName(int type) {
    switch (type) {
      case 1: return 'Grayscale Shader';
      case 2: return 'Warm Sepia Shader';
      case 3: return 'Invert Color Shader';
      case 4: return 'Brightness Boost';
      default: return 'Original (Pass-through)';
    }
  }

  String _formatMs(int ms) {
    final seconds = ms ~/ 1000;
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    final millis = ms % 1000;
    if (minutes > 0) {
      return '${minutes}m ${secs}s';
    }
    return '$secs.${(millis ~/ 100)}s';
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
