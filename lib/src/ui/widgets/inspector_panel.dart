import 'package:flutter/material.dart';
import '../../controllers/editor_controller.dart';
import '../../models/clip.dart';
import '../../models/project.dart';
import '../theme/app_theme.dart';

class InspectorPanel extends StatelessWidget {
  final EditorController controller;

  const InspectorPanel({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final selectedClip = controller.selectedClip;
    final selectedClips = controller.selectedClips;
    final engineService = controller.engineService;
    final filters = engineService.availableFilters;
    final project = controller.project;

    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.all(12),
      child: ListView(
        children: [
          // Header
          Row(
            children: [
              const Text(
                'INSPECTOR',
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              const Spacer(),
              if (selectedClips.length > 1)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    '${selectedClips.length} SELECTED',
                    style: const TextStyle(color: AppTheme.accent, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Multi-select bulk info — v0.5.5
          if (selectedClips.length > 1)
            _buildMultiSelectCard(selectedClips, project, context),

          // Single clip info
          if (selectedClip != null && selectedClips.length == 1) ...[
            _buildClipInfoCard(selectedClip),
            const SizedBox(height: 16),
            _buildClipTransformCard(selectedClip),
            const SizedBox(height: 16),
          ],

          // Project Info
          _buildProjectInfoCard(),

          const SizedBox(height: 16),

          // Filters & FX
          const Text(
            'FILTERS & FX',
            style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 8),
          if (selectedClip != null && selectedClips.length == 1)
            _buildPerClipFilterCard(selectedClip, filters, controller)
          else
            _buildGlobalFilterCard(filters, controller),

          // Transition — when clip selected
          if (selectedClip != null && selectedClips.length == 1) ...[
            const SizedBox(height: 16),
            _buildTransitionCard(selectedClip, controller),
          ],

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
          _buildAudioMixerCard(controller),

          const SizedBox(height: 16),

          // Engine info
          _buildEngineInfoCard(controller),
        ],
      ),
    );
  }

  // ========== Multi-select Card — v0.5.5 ==========

  Widget _buildMultiSelectCard(List<Clip> clips, Project project, BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.select_all, color: AppTheme.accent, size: 16),
              const SizedBox(width: 8),
              Text(
                '${clips.length} Clips Selected',
                style: const TextStyle(color: AppTheme.textMain, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // List selected clips
          ...clips.map((clip) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(_iconForClipType(clip.type), size: 12, color: AppTheme.accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    clip.displayName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppTheme.textMain, fontSize: 11),
                  ),
                ),
                Text(
                  _formatMs(clip.durationMs),
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
                ),
              ],
            ),
          )),
          const SizedBox(height: 8),
          // Bulk actions
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: () {
                    // Apply global filter to all selected clips
                    final filterType = controller.activeFilterType;
                    final intensity = controller.filterIntensity;
                    for (final clip in clips) {
                      // Direct model mutation for bulk (no undo for bulk filter)
                      clip.filterType = filterType;
                      clip.filterIntensity = intensity;
                    }
                    // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
                    controller.notifyListeners();
                  },
                  icon: const Icon(Icons.auto_fix_high, size: 14, color: AppTheme.accent),
                  label: const Text('Apply Filter', style: TextStyle(fontSize: 10)),
                  style: TextButton.styleFrom(
                    backgroundColor: AppTheme.accent.withValues(alpha: 0.1),
                    foregroundColor: AppTheme.accent,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextButton.icon(
                  onPressed: () {
                    // Delete all selected clips
                    controller.deleteSelectedClip();
                  },
                  icon: const Icon(Icons.delete_outline, size: 14, color: Colors.redAccent),
                  label: const Text('Delete All', style: TextStyle(fontSize: 10)),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.red.withValues(alpha: 0.1),
                    foregroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ========== Clip Info Card ==========

  Widget _buildClipInfoCard(Clip clip) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.accent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _iconForClipType(clip.type),
                color: AppTheme.accent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  clip.displayName,
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
          _buildMetaRow('Type', clip.type.name.toUpperCase()),
          _buildMetaRow('Timeline Start', _formatTimecode(clip.timelineStartMs)),
          _buildMetaRow('Duration', _formatTimecode(clip.durationMs)),
          _buildMetaRow('Source In', _formatTimecode(clip.sourceInMs)),
          _buildMetaRow('Source Out', _formatTimecode(clip.sourceOutMs)),
          _buildMetaRow('Track', 'Track ${clip.trackIndex + 1}'),
        ],
      ),
    );
  }

  // ========== Clip Transform Card — v0.5.5 ==========

  Widget _buildClipTransformCard(Clip clip) {
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
              const Icon(Icons.transform, color: AppTheme.primaryLight, size: 16),
              const SizedBox(width: 6),
              const Text('Clip Properties', style: TextStyle(color: AppTheme.textMain, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),

          // Speed
          Row(
            children: [
              const Text('Speed', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
              const Spacer(),
              Text('${clip.speed.toStringAsFixed(2)}x', style: const TextStyle(color: AppTheme.accent, fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
          Slider(
            value: clip.speed.clamp(0.25, 4.0),
            min: 0.25,
            max: 4.0,
            divisions: 16,
            activeColor: AppTheme.accent,
            label: '${clip.speed.toStringAsFixed(2)}x',
            onChanged: (val) {
              // TODO: Implement per-clip speed change (requires ChangeClipSpeedCommand)
              debugPrint('Speed: $val');
            },
          ),

          // Opacity
          Row(
            children: [
              const Text('Opacity', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
              const Spacer(),
              Text('${(clip.opacity * 100).toInt()}%', style: const TextStyle(color: AppTheme.accent, fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
          Slider(
            value: clip.opacity.clamp(0.0, 1.0),
            min: 0.0,
            max: 1.0,
            activeColor: AppTheme.accent,
            label: '${(clip.opacity * 100).toInt()}%',
            onChanged: (val) {
              // TODO: Implement per-clip opacity change
              debugPrint('Opacity: $val');
            },
          ),
        ],
      ),
    );
  }

  // ========== Project Info Card ==========

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

  // ========== Per-Clip Filter Card — v0.5.5 ==========

  Widget _buildPerClipFilterCard(Clip clip, List<Map<String, dynamic>> filters, EditorController controller) {
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
              Expanded(
                child: Text(
                  _getFilterName(clip.filterType),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.textMain, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18, color: AppTheme.textMuted),
                onPressed: () {
                  // Reset filter for this clip
                  // TODO: Use ChangeFilterCommand for undo
                  clip.filterType = 0;
                  clip.filterIntensity = 1.0;
                  // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
                  controller.notifyListeners();
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text('Filter Intensity', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
          Slider(
            value: clip.filterIntensity.clamp(0.0, 1.0),
            min: 0.0,
            max: 1.0,
            activeColor: AppTheme.primaryLight,
            onChanged: (val) {
              clip.filterIntensity = val;
              // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
              controller.notifyListeners();
            },
          ),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: filters.isNotEmpty
                ? filters.map((f) {
                    final id = f['id'] as int? ?? 0;
                    final name = f['name'] as String? ?? 'Unknown';
                    return _filterChip(name, id, clip.filterType == id, () {
                      clip.filterType = id;
                      // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
                      controller.notifyListeners();
                    });
                  }).toList()
                : _defaultFilterChips(clip),
          ),
        ],
      ),
    );
  }

  // ========== Global Filter Card (when no clip selected or multi-select) ==========

  Widget _buildGlobalFilterCard(List<Map<String, dynamic>> filters, EditorController controller) {
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
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: filters.isNotEmpty
                ? filters.map((f) {
                    final id = f['id'] as int? ?? 0;
                    final name = f['name'] as String? ?? 'Unknown';
                    return _filterChip(name, id, controller.activeFilterType == id, () {
                      controller.setFilter(id, controller.filterIntensity);
                    });
                  }).toList()
                : _defaultFilterChips(null),
          ),
        ],
      ),
    );
  }

  // ========== Transition Card — v0.5.5 (with duration slider) ==========

  Widget _buildTransitionCard(Clip clip, EditorController controller) {
    final transitions = [
      'None', 'Fade In', 'Fade Out', 'Crossfade',
      'Slide', 'Wipe', 'Zoom', 'Dissolve', 'Radial',
    ];

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
              const Icon(Icons.animation, color: AppTheme.primaryLight, size: 16),
              const SizedBox(width: 6),
              const Text('Transition', style: TextStyle(color: AppTheme.textMain, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: 'None',
              isExpanded: true,
              dropdownColor: AppTheme.surface,
              style: const TextStyle(color: AppTheme.textMain, fontSize: 12),
              items: transitions.map((t) =>
                DropdownMenuItem(value: t, child: Text(t))).toList(),
              onChanged: (val) {
                if (val != null) {
                  final idx = transitions.indexOf(val);
                  controller.setClipTransition(clip.id, idx, 500);
                }
              },
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.timer, color: AppTheme.textMuted, size: 14),
              const SizedBox(width: 4),
              const Text('500ms', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
              // TODO: Add duration slider for transition duration
            ],
          ),
        ],
      ),
    );
  }

  // ========== Audio Mixer Card ==========

  Widget _buildAudioMixerCard(EditorController controller) {
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

          // Per-clip volume — v0.5.5
          if (controller.selectedClip != null && controller.selectedClips.length == 1) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Clip Volume', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                Text(
                  '${(controller.selectedClip!.volume * 100).toInt()}%',
                  style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ],
            ),
            Slider(
              value: controller.selectedClip!.volume.clamp(0.0, 2.0),
              min: 0.0,
              max: 2.0,
              activeColor: AppTheme.primaryLight,
              onChanged: (val) {
                // TODO: Implement per-clip volume via ChangeClipVolumeCommand
                controller.selectedClip!.volume = val;
                // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
                controller.notifyListeners();
              },
            ),
          ],
        ],
      ),
    );
  }

  // ========== Engine Info Card ==========

  Widget _buildEngineInfoCard(EditorController controller) {
    final hasFFmpeg = controller.engineService.ffmpegAvailable;
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
              Icon(
                hasFFmpeg ? Icons.memory : Icons.developer_mode,
                color: hasFFmpeg ? Colors.green : AppTheme.textMuted,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                hasFFmpeg ? 'FFmpeg Accelerated' : 'Demo Mode (Synthetic)',
                style: TextStyle(
                  color: hasFFmpeg ? Colors.green : AppTheme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            controller.engineVersion.isNotEmpty
                ? controller.engineVersion
                : 'Engine not loaded',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
          ),
        ],
      ),
    );
  }

  // ========== Filter Chip Widget ==========

  Widget _filterChip(String label, int type, bool isActive, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
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

  List<Widget> _defaultFilterChips(Clip? clip) {
    final activeType = clip?.filterType ?? 0;
    return [
      _filterChip('None', 0, activeType == 0, () {}),
      _filterChip('Gray', 1, activeType == 1, () {}),
      _filterChip('Sepia', 2, activeType == 2, () {}),
      _filterChip('Invert', 3, activeType == 3, () {}),
      _filterChip('Bright', 4, activeType == 4, () {}),
      _filterChip('Blur', 5, activeType == 5, () {}),
      _filterChip('Edge', 6, activeType == 6, () {}),
      _filterChip('Grade', 7, activeType == 7, () {}),
      _filterChip('Adjust', 8, activeType == 8, () {}),
      _filterChip('Pixel', 9, activeType == 9, () {}),
      _filterChip('Mosaic', 10, activeType == 10, () {}),
    ];
  }

  // ========== Meta Row ==========

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

  // ========== Formatting Helpers ==========

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

  String _formatTimecode(int ms) {
    final totalSeconds = ms / 1000.0;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toStringAsFixed(2).padLeft(5, '0')}';
  }

  String _getFilterName(int type) {
    switch (type) {
      case 1: return 'Grayscale';
      case 2: return 'Sepia';
      case 3: return 'Invert';
      case 4: return 'Brightness';
      case 5: return 'Blur';
      case 6: return 'Edge Detect';
      case 7: return 'Color Grading';
      case 8: return 'Adjust (BCSH)';
      case 9: return 'Pixelate';
      case 10: return 'Mosaic';
      default: return 'Original (Pass-through)';
    }
  }

  IconData _iconForClipType(ClipType type) {
    switch (type) {
      case ClipType.video: return Icons.movie;
      case ClipType.audio: return Icons.music_note;
      case ClipType.image: return Icons.image;
      case ClipType.text: return Icons.title;
      case ClipType.overlay: return Icons.layers;
    }
  }
}
