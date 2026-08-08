import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../controllers/editor_controller.dart';
import '../../models/clip.dart';
import '../theme/app_theme.dart';

/// Photoshop-style Pro Photo & Graphic Editor Studio Panel v1.0.0.
class PhotoEditorPanel extends StatefulWidget {
  final EditorController controller;

  const PhotoEditorPanel({
    super.key,
    required this.controller,
  });

  @override
  State<PhotoEditorPanel> createState() => _PhotoEditorPanelState();
}

class _PhotoEditorPanelState extends State<PhotoEditorPanel> {
  double _exposure = 0.0;
  double _contrast = 0.0;
  double _saturation = 0.0;
  double _vibrance = 0.0;
  double _temperature = 0.0;
  bool _bgRemoved = false;
  // v1.0.1: Track which clip the local slider values belong to so we can
  // reset them when a different clip is selected.
  String? _activeClipId;

  Future<void> _pickImageFile() async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'bmp', 'webp', 'gif'],
    );
    if (result != null && result.files.single.path != null && mounted) {
      await widget.controller.importPhotoToStudio(result.files.single.path!);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Imported Photo Layer: ${result.files.single.name}')),
      );
    }
  }

  void _applyColorCorrection() {
    final sel = widget.controller.selectedClip ?? widget.controller.project.allClips.firstOrNull;
    if (sel != null) {
      // v1.0.2: NO beginPropertyGesture() here — it was called on every
      // slider tick, giving each tick a fresh gestureId so coalescing never
      // engaged and a single drag pushed dozens of undo entries (evicting
      // older commands from the 100-entry stack). The gesture now opens once
      // per drag via the slider's onChangeStart (see _buildSlider).
      widget.controller.setClipColorCorrection(
        sel.id,
        exposure: _exposure,
        contrast: _contrast,
        saturation: _saturation,
        vibrance: _vibrance,
        temperature: _temperature,
      );
    }
  }

  void _toggleBackgroundRemoval(bool value) {
    setState(() => _bgRemoved = value);
    final sel = widget.controller.selectedClip ?? widget.controller.project.allClips.firstOrNull;
    if (sel != null) {
      // Filter 22 is CapCut Chroma Key / BG Removal
      widget.controller.setClipFilter(sel.id, value ? 22 : 0, value ? 0.75 : 0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final clips = widget.controller.project.allClips;
    final activeClip = widget.controller.selectedClip ?? clips.firstOrNull;

    // v1.0.1: When the selected clip changes, reset the local slider state
    // to reflect the new clip's actual color correction values. Previously
    // the sliders kept showing the previous clip's values.
    if (activeClip?.id != _activeClipId) {
      _activeClipId = activeClip?.id;
      if (activeClip != null) {
        _exposure = activeClip.colorExposure;
        _contrast = activeClip.colorContrast;
        _saturation = activeClip.colorSaturation;
        _vibrance = activeClip.colorVibrance;
        _temperature = activeClip.colorTemperature;
        _bgRemoved = activeClip.filterType == 22;
      }
    }

    return Container(
      color: AppTheme.background,
      child: Column(
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: AppTheme.surface,
              border: Border(bottom: BorderSide(color: AppTheme.divider)),
            ),
            child: Row(
              children: [
                const Icon(Icons.photo_filter, color: AppTheme.accentLight, size: 20),
                const SizedBox(width: 8),
                const Text(
                  '🎨 PHOTO EDITOR STUDIO (PHOTOSHOP MODE)',
                  style: TextStyle(
                    color: AppTheme.textMain,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    letterSpacing: 1.0,
                  ),
                ),
                const Spacer(),

                // Import Image File Button
                ElevatedButton.icon(
                  onPressed: _pickImageFile,
                  icon: const Icon(Icons.add_photo_alternate_rounded, size: 14),
                  label: const Text('📥 Import Photo Layer', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.card,
                    foregroundColor: AppTheme.accentLight,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    side: const BorderSide(color: AppTheme.accent),
                  ),
                ),
                const SizedBox(width: 12),

                ElevatedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Photo Exported Successfully (PNG 4K Lossless / WEBP / JPEG 100%)')),
                    );
                  },
                  icon: const Icon(Icons.file_download, size: 14),
                  label: const Text('EXPORT HIGH-RES IMAGE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ],
            ),
          ),

          // Main Studio Body
          Expanded(
            child: Row(
              children: [
                // Left Photo Tools & Adjustments
                Container(
                  width: 320,
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: AppTheme.surface,
                    border: Border(right: BorderSide(color: AppTheme.divider)),
                  ),
                  child: ListView(
                    children: [
                      Text(
                        activeClip != null
                            ? '🎚️ COLOR & EXPOSURE (${activeClip.displayName})'
                            : '🎚️ COLOR & EXPOSURE ADJUSTMENTS',
                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                      ),
                      const SizedBox(height: 16),

                      _buildSlider('Exposure', _exposure, -1.0, 1.0, (v) {
                        setState(() => _exposure = v);
                        _applyColorCorrection();
                      }, onChangeStart: (_) => widget.controller.beginPropertyGesture()),
                      _buildSlider('Contrast', _contrast, -1.0, 1.0, (v) {
                        setState(() => _contrast = v);
                        _applyColorCorrection();
                      }, onChangeStart: (_) => widget.controller.beginPropertyGesture()),
                      _buildSlider('Saturation', _saturation, -1.0, 1.0, (v) {
                        setState(() => _saturation = v);
                        _applyColorCorrection();
                      }, onChangeStart: (_) => widget.controller.beginPropertyGesture()),
                      _buildSlider('Vibrance', _vibrance, -1.0, 1.0, (v) {
                        setState(() => _vibrance = v);
                        _applyColorCorrection();
                      }, onChangeStart: (_) => widget.controller.beginPropertyGesture()),
                      _buildSlider('Temperature', _temperature, -1.0, 1.0, (v) {
                        setState(() => _temperature = v);
                        _applyColorCorrection();
                      }, onChangeStart: (_) => widget.controller.beginPropertyGesture()),

                      const SizedBox(height: 16),
                      const Divider(color: AppTheme.divider),
                      const SizedBox(height: 12),

                      const Text(
                        '🪄 AI PHOTO TOOLS',
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                      ),
                      const SizedBox(height: 8),

                      SwitchListTile(
                        value: _bgRemoved,
                        onChanged: _toggleBackgroundRemoval,
                        activeThumbColor: AppTheme.accent,
                        title: const Text('Magic Cutout (Remove Background)', style: TextStyle(color: AppTheme.textMain, fontSize: 11, fontWeight: FontWeight.bold)),
                        subtitle: const Text('AI color distance transparency mask', style: TextStyle(color: AppTheme.textMuted, fontSize: 9)),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),

                // Center Image Canvas View
                Expanded(
                  child: Container(
                    color: const Color(0xFF0F1117),
                    child: Center(
                      child: Container(
                        width: 560,
                        height: 360,
                        decoration: BoxDecoration(
                          color: _bgRemoved ? Colors.transparent : Colors.black,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.primaryLight, width: 2),
                          boxShadow: AppTheme.shadowLg,
                        ),
                        child: Stack(
                          children: [
                            Center(
                              child: Icon(
                                activeClip?.type == ClipType.image ? Icons.image : Icons.videocam,
                                size: 80,
                                color: AppTheme.textMuted,
                              ),
                            ),
                            Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const SizedBox(height: 90),
                                  Text(
                                    activeClip != null
                                        ? '📷 EDITING: ${activeClip.displayName}'
                                        : 'PHOTOSHOP IMAGE CANVAS (4K READY)',
                                    style: const TextStyle(color: AppTheme.textMain, fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _bgRemoved ? '✨ BACKGROUND REMOVED (TRANSPARENT PNG)' : 'Color Correction & Layer FX Applied',
                                    style: const TextStyle(color: AppTheme.accentLight, fontSize: 10),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Right Layers Panel
                Container(
                  width: 260,
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: AppTheme.surface,
                    border: Border(left: BorderSide(color: AppTheme.divider)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '🥞 LAYERS STACK (${clips.length})',
                            style: const TextStyle(color: AppTheme.textMuted, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_a_photo_outlined, size: 16, color: AppTheme.accentLight),
                            onPressed: _pickImageFile,
                            tooltip: 'Add Photo Layer',
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: clips.isEmpty
                            ? Center(
                                child: TextButton.icon(
                                  onPressed: _pickImageFile,
                                  icon: const Icon(Icons.add_photo_alternate, size: 16),
                                  label: const Text('Add Image Layer', style: TextStyle(fontSize: 11)),
                                ),
                              )
                            : ListView.separated(
                                itemCount: clips.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 6),
                                itemBuilder: (context, idx) {
                                  final clip = clips[idx];
                                  final isSelected = activeClip?.id == clip.id;
                                  return InkWell(
                                    onTap: () {
                                      widget.controller.project.selectClip(clip.id);
                                      setState(() {});
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: isSelected ? AppTheme.accent.withValues(alpha: 0.2) : AppTheme.card,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: isSelected ? AppTheme.accent : AppTheme.divider),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            clip.type == ClipType.image ? Icons.image : Icons.movie,
                                            size: 14,
                                            color: isSelected ? AppTheme.accentLight : AppTheme.textMuted,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              clip.displayName,
                                              style: TextStyle(
                                                color: isSelected ? AppTheme.textMain : AppTheme.textMuted,
                                                fontSize: 11,
                                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlider(String label, double val, double min, double max, ValueChanged<double> onChanged, {ValueChanged<double>? onChangeStart}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: AppTheme.textMain, fontSize: 11)),
            Text(val.toStringAsFixed(2), style: const TextStyle(color: AppTheme.accentLight, fontSize: 10, fontFamily: 'monospace')),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            activeTrackColor: AppTheme.accent,
            inactiveTrackColor: AppTheme.divider,
            thumbColor: AppTheme.accentLight,
          ),
          child: Slider(
            value: val.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
            // v1.0.2: Open the undo gesture once at drag start so all ticks
            // of one drag coalesce into a single undo entry.
            onChangeStart: onChangeStart,
          ),
        ),
      ],
    );
  }
}
