import 'package:flutter/material.dart';
import '../../controllers/editor_controller.dart';
import '../../controllers/command_history.dart';
import '../../models/clip.dart';
import '../../models/curve_speed.dart';
import '../../models/project.dart';
import '../theme/app_theme.dart';

// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

// ============================================================
// InspectorPanel — v0.7.0 Enhanced with Rich Text Editor
// ============================================================

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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      color: AppTheme.surface,
      child: ListView(
        padding: const EdgeInsets.all(10),
        children: [
          // Header
          Row(
            children: [
              const Text(
                'INSPECTOR',
                style: TextStyle(
                  color: AppTheme.accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              if (selectedClips.length > 1)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    '${selectedClips.length} SELECTED',
                    style: const TextStyle(color: AppTheme.primaryLight, fontSize: 8, fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Multi-select bulk info
          if (selectedClips.length > 1)
            _buildMultiSelectCard(selectedClips, project, context),

          // Single clip info
          if (selectedClip != null && selectedClips.length == 1) ...[
            _buildClipInfoCard(selectedClip, isDark),
            const SizedBox(height: 10),

            // v0.7.0: Rich Text Editor (for text clips)
            if (selectedClip.type == ClipType.text || selectedClip.type == ClipType.overlay)
              ..._buildRichTextEditor(selectedClip, controller),

            // v0.7.0: Sticker Properties (for sticker clips)
            if (selectedClip.type == ClipType.sticker)
              ..._buildStickerProperties(selectedClip, controller, context),

            // Clip Transform Card
            _buildClipTransformCard(selectedClip),
            const SizedBox(height: 10),
          ],

          // Project Info
          _buildProjectInfoCard(project),
          const SizedBox(height: 10),

          // v0.7.0: Color Correction Card (v0.5.5: per-clip, now enhanced)
          if (selectedClip != null && selectedClips.length == 1)
            _buildColorCorrectionCard(selectedClip, controller),

          // Filters & FX
          const SizedBox(height: 10),
          Row(
            children: [
              const Text('FILTERS & FX', style: TextStyle(color: AppTheme.accent, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
              const Spacer(),
              if (selectedClip != null && selectedClips.length == 1)
                TextButton.icon(
                  onPressed: () {
                    // v1.1.0 (PLAN 1.1/B12): Undoable reset — the old code
                    // mutated the clip directly (no undo entry) and never
                    // re-synced the engine, so the preview kept the filter.
                    controller.setClipFilter(selectedClip.id, 0, 1.0);
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 14, color: AppTheme.textMuted),
                  label: const Text('Reset', style: TextStyle(fontSize: 9)),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (selectedClip != null && selectedClips.length == 1)
            _buildPerClipFilterCard(selectedClip, filters, controller, context)
          else
            _buildGlobalFilterCard(filters, controller),

          // Transition
          if (selectedClip != null && selectedClips.length == 1) ...[
            const SizedBox(height: 10),
            _buildTransitionCard(selectedClip, controller),
          ],

          const SizedBox(height: 10),

          // Audio Mixer
          const Text('AUDIO MIXER', style: TextStyle(color: AppTheme.accent, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
          const SizedBox(height: 4),
          _buildAudioMixerCard(controller),

          const SizedBox(height: 10),

          // Engine info
          _buildEngineInfoCard(controller),
        ],
      ),
    );
  }

  // ============================================================
  // Rich Text Editor (v0.7.0)
  // ============================================================

  List<Widget> _buildRichTextEditor(Clip clip, EditorController controller) {
    final fonts = ['Segoe UI', 'Arial', 'Helvetica', 'Times New Roman', 'Georgia', 'Verdana', 'Courier New', 'Impact', 'Comic Sans MS', 'Trebuchet MS', 'Tahoma', 'Palatino'];
    final alignments = [
      {'icon': Icons.format_align_left_rounded, 'value': 0},
      {'icon': Icons.format_align_center_rounded, 'value': 1},
      {'icon': Icons.format_align_right_rounded, 'value': 2},
    ];

    // v1.0.0: Route all text-editor edits through setClipText so the
    // typing/styling session collapses into a single undo entry. Previously
    // each field mutated clip.text* directly (not undoable).
    void editText({
      String? content,
      String? font,
      double? fontSize,
      int? colorValue,
      bool? bold,
      bool? italic,
      bool? underline,
      double? strokeWidth,
      int? strokeColorValue,
      bool? shadow,
      int? bgColorValue,
      int? alignment,
    }) {
      controller.setClipText(
        clip.id,
        content: content,
        font: font,
        fontSize: fontSize,
        colorValue: colorValue,
        bold: bold,
        italic: italic,
        underline: underline,
        strokeWidth: strokeWidth,
        strokeColorValue: strokeColorValue,
        shadow: shadow,
        bgColorValue: bgColorValue,
        alignment: alignment,
      );
    }

    return [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.title_rounded, color: AppTheme.primaryLight, size: 14),
                const SizedBox(width: 6),
                const Text('TEXT EDITOR', style: TextStyle(color: AppTheme.textMain, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
              ],
            ),
            const SizedBox(height: 10),

            // Text content input
            // v1.0.0: wrapped in a StatefulWidget holding a TextEditingController
            // so undo/redo (which mutate clip.textContent outside the field) sync
            // the displayed text. The old uncontrolled TextField kept stale text
            // after Ctrl+Z.
            _TextContentField(
              clip: clip,
              onChanged: (val) => editText(content: val),
            ),
            const SizedBox(height: 10),

            // Font + Size row
            Row(
              children: [
                // Font dropdown
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: clip.textFont,
                        isDense: true,
                        dropdownColor: AppTheme.card,
                        style: TextStyle(color: AppTheme.textMain, fontSize: 11),
                        items: fonts.map((f) => DropdownMenuItem(value: f, child: Text(f, style: TextStyle(fontFamily: f, fontSize: 11)))).toList(),
                        onChanged: (val) {
                          if (val != null) editText(font: val);
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Font size slider
                SizedBox(
                  width: 80,
                  child: Column(
                    children: [
                      Text('${clip.textFontSize.toInt()}px', style: const TextStyle(color: AppTheme.textMuted, fontSize: 9)),
                      Slider(
                        value: clip.textFontSize.clamp(12.0, 200.0),
                        min: 12.0,
                        max: 200.0,
                        activeColor: AppTheme.primaryLight,
                        onChanged: (val) => editText(fontSize: val),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Style toggles: Bold, Italic, Underline, Shadow, Gradient
            Row(
              children: [
                _styleToggle(Icons.format_bold_rounded, clip.textBold, () => editText(bold: !clip.textBold)),
                _styleToggle(Icons.format_italic_rounded, clip.textItalic, () => editText(italic: !clip.textItalic)),
                _styleToggle(Icons.format_underlined_rounded, clip.textUnderline, () => editText(underline: !clip.textUnderline)),
                _styleToggle(Icons.blur_on, clip.textShadow, () => editText(shadow: !clip.textShadow)),
                // v1.0.1: Gradient toggle now routes through setClipText so it's
                // undoable (previously mutated the clip directly, bypassing
                // the command history — Ctrl+Z did not revert it).
                _styleToggle(Icons.gradient, clip.textGradient, () {
                  controller.setClipText(clip.id, gradient: !clip.textGradient);
                }),
                const Spacer(),

                // Alignment
                ...alignments.map((a) => _alignmentButton(
                  a['icon'] as IconData,
                  clip.textAlignment == a['value'],
                  () => editText(alignment: a['value'] as int),
                )),
              ],
            ),
            const SizedBox(height: 8),

            // Color + Stroke row
            Builder(
              builder: (ctx) => Row(
                children: [
                  // Text color
                  Expanded(
                    child: Row(
                      children: [
                        _colorDot(color: clip.textColor, onTap: () {
                          showDialog(
                            context: ctx,
                            builder: (_) => AlertDialog(
                              backgroundColor: AppTheme.card,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusLg)),
                              title: const Text('Pick Color', style: TextStyle(color: AppTheme.textMain)),
                              content: SizedBox(
                                width: 260,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _ColorGrid(
                                      colors: [
                                        Colors.white, Colors.black, Colors.red, Colors.orange, Colors.yellow,
                                        Colors.green, Colors.cyan, Colors.blue, Colors.purple, Colors.pink,
                                        AppTheme.primaryLight, AppTheme.accent, AppTheme.clipVideo, AppTheme.clipAudio,
                                        AppTheme.clipImage, AppTheme.clipText, AppTheme.clipOverlay, AppTheme.success,
                                      ],
                                      onColorTap: (c) { editText(colorValue: c.toARGB32()); Navigator.pop(ctx); },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      const SizedBox(width: 6),
                      Text('Color', style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Stroke width
                Row(
                  children: [
                    Text('Stroke', style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
                    const SizedBox(width: 4),
                    _colorDot(color: clip.textStrokeColor, onTap: () {
                        showDialog(
                          context: ctx,
                          builder: (_) => AlertDialog(
                            backgroundColor: AppTheme.card,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusLg)),
                            title: const Text('Pick Color', style: TextStyle(color: AppTheme.textMain)),
                            content: SizedBox(
                              width: 260,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _ColorGrid(
                                    colors: [
                                      Colors.white, Colors.black, Colors.red, Colors.orange, Colors.yellow,
                                      Colors.green, Colors.cyan, Colors.blue, Colors.purple, Colors.pink,
                                      AppTheme.primaryLight, AppTheme.accent, AppTheme.clipVideo, AppTheme.clipAudio,
                                      AppTheme.clipImage, AppTheme.clipText, AppTheme.clipOverlay, AppTheme.success,
                                    ],
                                    onColorTap: (c) { editText(strokeColorValue: c.toARGB32()); Navigator.pop(ctx); },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 50,
                      child: Slider(
                        value: clip.textStrokeWidth.clamp(0.0, 20.0),
                        min: 0.0,
                        max: 20.0,
                        activeColor: AppTheme.primaryLight,
                        onChanged: (val) => editText(strokeWidth: val),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    ];
  }

  Widget _styleToggle(IconData icon, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: active ? AppTheme.primary.withValues(alpha: 0.2) : AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? AppTheme.primaryLight : AppTheme.divider, width: 0.5),
        ),
        child: Icon(icon, size: 14, color: active ? AppTheme.primaryLight : AppTheme.textMuted),
      ),
    );
  }

  Widget _alignmentButton(IconData icon, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: active ? AppTheme.primary.withValues(alpha: 0.2) : AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? AppTheme.primaryLight : AppTheme.divider, width: 0.5),
        ),
        child: Icon(icon, size: 14, color: active ? AppTheme.primaryLight : AppTheme.textMuted),
      ),
    );
  }

  Widget _colorDot({required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppTheme.divider, width: 1),
        ),
      ),
    );
  }

  // ============================================================

  List<Widget> _buildStickerProperties(Clip clip, EditorController controller, BuildContext context) {
    return [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(color: AppTheme.clipSticker.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.emoji_emotions_rounded, color: AppTheme.clipSticker, size: 14),
                const SizedBox(width: 6),
                const Text('STICKER', style: TextStyle(color: AppTheme.textMain, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
              ],
            ),
            const SizedBox(height: 10),
Row(
                children: [
                  const Text('Scale', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                  const Spacer(),
                  Text('${(clip.stickerScale * 100).toInt()}%', style: const TextStyle(color: AppTheme.accent, fontSize: 11, fontWeight: FontWeight.w600)),
                ],
              ),
              Slider(
                value: clip.stickerScale.clamp(0.1, 5.0),
                min: 0.1,
                max: 5.0,
                activeColor: AppTheme.clipSticker,
                // v1.1.0 (PLAN 3.12/B13): DISABLED — the engine renders
                // stickers via GDI text (fixed size); scale had NO effect on
                // preview/export while the UI pretended it did. Honest label
                // until the engine supports sticker transform.
                onChanged: null,
              ),
              Row(
                children: [
                  const Text('Rotation', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                  const Spacer(),
                  Text('${clip.stickerRotation.toInt()}°', style: const TextStyle(color: AppTheme.accent, fontSize: 11, fontWeight: FontWeight.w600)),
                ],
              ),
              Slider(
                value: clip.stickerRotation.clamp(-180.0, 180.0),
                min: -180.0,
                max: 180.0,
                divisions: 36,
                activeColor: AppTheme.clipSticker,
                onChanged: null, // v1.1.0: disabled — no engine transform support
              ),
              const Text('Sticker transform chưa được engine hỗ trợ (disbled trung thực)',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 9, fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    ];
  }

  // ============================================================
  // Color Correction Card (v0.7.0 enhanced)
  // ============================================================

  Widget _buildColorCorrectionCard(Clip clip, EditorController controller) {
    // v0.7.8: These sliders drive the real per-clip color-correction fields
    // (model-backed + JSON-persisted). Previously "Exposure" overwrote the
    // filter intensity and "Brightness" actually changed playback speed.
    // v0.8.0: Mirrored to the native engine so preview/export show the grade.
    // v1.0.0: All 8 engine-supported fields exposed (previously only 4).
    void setColor({
      double? exposure,
      double? contrast,
      double? saturation,
      double? temperature,
      double? tint,
      double? vibrance,
      double? highlights,
      double? shadows,
    }) {
      controller.setClipColorCorrection(
        clip.id,
        exposure: exposure,
        contrast: contrast,
        saturation: saturation,
        temperature: temperature,
        tint: tint,
        vibrance: vibrance,
        highlights: highlights,
        shadows: shadows,
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.palette_rounded, color: AppTheme.accentWarm, size: 14),
              const SizedBox(width: 6),
              const Text('COLOR', style: TextStyle(color: AppTheme.textMain, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
            ],
          ),
          const SizedBox(height: 10),
          _colorSlider('Exposure', clip.colorExposure, -1.0, 1.0, AppTheme.textSecondary, (val) => setColor(exposure: val)),
          _colorSlider('Contrast', clip.colorContrast, -1.0, 1.0, AppTheme.accent, (val) => setColor(contrast: val)),
          _colorSlider('Saturation', clip.colorSaturation, -1.0, 1.0, AppTheme.success, (val) => setColor(saturation: val)),
          _colorSlider('Temperature', clip.colorTemperature, -1.0, 1.0, AppTheme.accentWarm, (val) => setColor(temperature: val)),
          // v1.0.0: New sliders — Tint/Vibrance/Highlights/Shadows were in
          // the engine + project model but had no UI control.
          _colorSlider('Tint', clip.colorTint, -1.0, 1.0, AppTheme.warning, (val) => setColor(tint: val)),
          _colorSlider('Vibrance', clip.colorVibrance, -1.0, 1.0, AppTheme.accent, (val) => setColor(vibrance: val)),
          _colorSlider('Highlights', clip.colorHighlights, -1.0, 1.0, AppTheme.success, (val) => setColor(highlights: val)),
          _colorSlider('Shadows', clip.colorShadows, -1.0, 1.0, AppTheme.textSecondary, (val) => setColor(shadows: val)),
        ],
      ),
    );
  }

  Widget _colorSlider(String label, double value, double min, double max, Color accentColor, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 60, child: Text(label, style: TextStyle(color: AppTheme.textMuted, fontSize: 10))),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              activeColor: accentColor,
              // v1.0.0: Without a fresh gesture id per drag, every color
              // slider drag on a clip shares one id and coalesces into a
              // single undo entry — undo couldn't revert one slider alone.
              onChangeStart: (_) => controller.beginPropertyGesture(),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // Multi-select Card
  // ============================================================

  Widget _buildMultiSelectCard(List<Clip> clips, Project project, BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.select_all_rounded, color: AppTheme.primaryLight, size: 14),
              const SizedBox(width: 6),
              Text('${clips.length} Clips Selected', style: const TextStyle(color: AppTheme.textMain, fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 6),
          ...clips.map((clip) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 1.5),
            child: Row(
              children: [
                Icon(_iconForClipType(clip.type), size: 11, color: AppTheme.primaryLight),
                const SizedBox(width: 6),
                Expanded(child: Text(clip.displayName, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.textMain, fontSize: 10))),
                Text(_formatDuration(clip.durationMs), style: const TextStyle(color: AppTheme.textMuted, fontSize: 9)),
              ],
            ),
          )),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: () {
                    // v1.1.0 (PLAN 1.1/B12): Batch filter through the
                    // command history — one undo entry for the whole batch,
                    // and the command listener re-syncs the engine timeline
                    // (previously: direct mutation, no undo, no engine sync).
                    controller.commandHistory.execute(
                      ChangeMultiClipFilterCommand(
                        clipIds: clips.map((c) => c.id).toList(),
                        newFilterType: controller.activeFilterType,
                        newIntensity: controller.filterIntensity,
                      ),
                      controller.project,
                    );
                    controller.notifyListeners();
                  },
                  icon: const Icon(Icons.auto_fix_high, size: 14, color: AppTheme.primaryLight),
                  label: const Text('Apply Filter', style: TextStyle(fontSize: 10)),
                  style: TextButton.styleFrom(
                    backgroundColor: AppTheme.primary.withValues(alpha: 0.08),
                    foregroundColor: AppTheme.primaryLight,
                    padding: const EdgeInsets.symmetric(vertical: 5),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextButton.icon(
                  onPressed: () => controller.deleteSelectedClip(),
                  icon: const Icon(Icons.delete_outline_rounded, size: 14, color: AppTheme.error),
                  label: const Text('Delete All', style: TextStyle(fontSize: 10)),
                  style: TextButton.styleFrom(
                    backgroundColor: AppTheme.error.withValues(alpha: 0.08),
                    foregroundColor: AppTheme.error,
                    padding: const EdgeInsets.symmetric(vertical: 5),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // Clip Info Card
  // ============================================================

  Widget _buildClipInfoCard(Clip clip, bool isDark) {
    final color = AppTheme.clipColorForType(clip.type.name, isDark: isDark);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(clip.displayName, style: const TextStyle(color: AppTheme.textMain, fontWeight: FontWeight.w600, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _metaRow('Type', clip.type.name.toUpperCase()),
          _metaRow('Start', _formatTimecode(clip.timelineStartMs)),
          _metaRow('Duration', _formatTimecode(clip.durationMs)),
          _metaRow('Source In', _formatTimecode(clip.sourceInMs)),
          _metaRow('Source Out', _formatTimecode(clip.sourceOutMs)),
          _metaRow('Track', 'Track ${clip.trackIndex + 1}'),
          if (clip.groupId != null) _metaRow('Group', clip.groupId!),
          if (clip.isLocked) _metaRow('Status', 'Locked', valueColor: AppTheme.warning),
        ],
      ),
    );
  }

  // ============================================================
  // Clip Transform Card
  // ============================================================

  Widget _buildClipTransformCard(Clip clip) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.transform_rounded, color: AppTheme.primaryLight, size: 14),
              const SizedBox(width: 6),
              const Text('PROPERTIES', style: TextStyle(color: AppTheme.textMain, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
            ],
          ),
          const SizedBox(height: 10),

          // Speed (v0.7.8: undoable via ChangeClipPropertyCommand)
          _sliderRow('Speed', '${clip.speed.toStringAsFixed(2)}x', clip.speed, 0.25, 4.0, AppTheme.accent, (val) {
            controller.setClipSpeed(clip.id, val);
          }, onChangedStart: (_) => controller.beginPropertyGesture()),
          // Opacity (v0.7.8: undoable)
          _sliderRow('Opacity', '${(clip.opacity * 100).toInt()}%', clip.opacity, 0.0, 1.0, AppTheme.primaryLight, (val) {
            controller.setClipOpacity(clip.id, val);
          }, onChangedStart: (_) => controller.beginPropertyGesture()),
          // Volume (v0.7.8: undoable)
          _sliderRow('Volume', '${(clip.volume * 100).toInt()}%', clip.volume, 0.0, 2.0, AppTheme.clipAudio, (val) {
            controller.setClipVolume(clip.id, val);
          }, onChangedStart: (_) => controller.beginPropertyGesture()),

          // v1.1.0 (PLAN 3.11): Speed Ramp — CapCut-style curve presets wired
          // to the engine. curve_speed.dart was dead code in v1.0.0 (its
          // evaluateSpeedAt was never called); picking a preset now builds a
          // real point curve the engine integrates when rendering.
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.speed_rounded, size: 14, color: AppTheme.accent),
              const SizedBox(width: 6),
              const Text('Speed Ramp', style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
              const Spacer(),
              if (clip.speedCurve.isNotEmpty)
                Text('${clip.speedCurve.length} pts', style: const TextStyle(color: AppTheme.accent, fontSize: 10, fontFamily: 'monospace')),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<SpeedCurvePreset>(
                    isDense: true,
                    isExpanded: true,
                    dropdownColor: AppTheme.surface,
                    style: const TextStyle(color: AppTheme.textMain, fontSize: 11),
                    hint: const Text('Select preset…', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                    items: SpeedCurvePreset.values
                        .where((p) => p != SpeedCurvePreset.custom)
                        .map((p) => DropdownMenuItem(value: p, child: Text(p.displayName)))
                        .toList(),
                    onChanged: (preset) {
                      if (preset == null) return;
                      final points = <SpeedRampPoint>[
                        for (var i = 0; i <= 8; i++)
                          SpeedRampPoint(i / 8, preset.evaluateSpeedAt(i / 8)),
                      ];
                      controller.setClipSpeedCurve(clip.id, points);
                    },
                  ),
                ),
              ),
              TextButton(
                onPressed: clip.speedCurve.isEmpty
                    ? null
                    : () => controller.setClipSpeedCurve(clip.id, const []),
                child: const Text('Clear', style: TextStyle(fontSize: 10)),
              ),
            ],
          ),

          // v1.1.0 (PLAN 3.4): Picture-in-picture geometry — real engine
          // rendering (the v1.0.0 render_pip C API was a stub returning
          // hasClip).
          const SizedBox(height: 8),
          const Divider(height: 1, color: AppTheme.divider),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.picture_in_picture_alt_rounded, size: 14, color: AppTheme.clipOverlay),
              const SizedBox(width: 6),
              // v1.1.0: Flexible — long labels must not overflow narrow panels.
              const Flexible(
                child: Text('PICTURE-IN-PICTURE', overflow: TextOverflow.ellipsis, style: TextStyle(color: AppTheme.textMuted, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
              ),
              const Spacer(),
              TextButton(
                onPressed: clip.pipW >= 1.0 && clip.pipH >= 1.0 && clip.pipX == 0 && clip.pipY == 0
                    ? null
                    : () => controller.setClipPip(clip.id),
                child: const Text('Reset', style: TextStyle(fontSize: 10)),
              ),
            ],
          ),
          _sliderRow('X', '${(clip.pipX * 100).toInt()}%', clip.pipX, 0.0, 1.0, AppTheme.clipOverlay, (v) {
            controller.setClipPip(clip.id, x: v, y: clip.pipY, w: clip.pipW, h: clip.pipH, rotation: clip.pipRotation);
          }, onChangedStart: (_) => controller.beginPropertyGesture()),
          _sliderRow('Y', '${(clip.pipY * 100).toInt()}%', clip.pipY, 0.0, 1.0, AppTheme.clipOverlay, (v) {
            controller.setClipPip(clip.id, x: clip.pipX, y: v, w: clip.pipW, h: clip.pipH, rotation: clip.pipRotation);
          }, onChangedStart: (_) => controller.beginPropertyGesture()),
          _sliderRow('Width', '${(clip.pipW * 100).toInt()}%', clip.pipW, 0.1, 1.0, AppTheme.clipOverlay, (v) {
            controller.setClipPip(clip.id, x: clip.pipX, y: clip.pipY, w: v, h: clip.pipH, rotation: clip.pipRotation);
          }, onChangedStart: (_) => controller.beginPropertyGesture()),
          _sliderRow('Height', '${(clip.pipH * 100).toInt()}%', clip.pipH, 0.1, 1.0, AppTheme.clipOverlay, (v) {
            controller.setClipPip(clip.id, x: clip.pipX, y: clip.pipY, w: clip.pipW, h: v, rotation: clip.pipRotation);
          }, onChangedStart: (_) => controller.beginPropertyGesture()),
        ],
      ),
    );
  }

  Widget _sliderRow(String label, String value, double val, double min, double max, Color color, ValueChanged<double> onChanged,
      {ValueChanged<double>? onChangedStart}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 50, child: Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 10))),
          Expanded(
            child: Slider(
              value: val.clamp(min, max),
              min: min,
              max: max,
              activeColor: color,
              label: value,
              onChangeStart: onChangedStart,
              onChanged: onChanged,
            ),
          ),
          SizedBox(width: 40, child: Text(value, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600, fontFamily: 'monospace'))),
        ],
      ),
    );
  }

  // ============================================================
  // Project Info Card
  // ============================================================

  Widget _buildProjectInfoCard(Project project) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.folder_special_rounded, color: AppTheme.primaryLight, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(project.name, style: const TextStyle(color: AppTheme.textMain, fontWeight: FontWeight.w600, fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _metaRow('Version', project.version),
          _metaRow('Clips', '${project.allClips.length}'),
          _metaRow('Tracks', '${project.tracks.length}'),
          _metaRow('Duration', _formatDuration(project.totalDurationMs)),
          _metaRow('Output', '${project.outputWidth}x${project.outputHeight} @ ${project.outputFps}fps'),
        ],
      ),
    );
  }

  // ============================================================
  // Per-Clip Filter Card
  // ============================================================

  Widget _buildPerClipFilterCard(Clip clip, List<Map<String, dynamic>> filters, EditorController controller, BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
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
                  style: const TextStyle(color: AppTheme.textMain, fontWeight: FontWeight.w600, fontSize: 11),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 16, color: AppTheme.textMuted),
                onPressed: () {
                  // v0.7.8: Undoable reset
                  controller.setClipFilter(clip.id, 0, 1.0);
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text('Intensity', style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
          Slider(
            value: clip.filterIntensity.clamp(0.0, 1.0),
            min: 0.0,
            max: 1.0,
            activeColor: AppTheme.primaryLight,
            // v0.7.8: Undoable via ChangeFilterCommand
            onChanged: (val) => controller.setClipFilter(clip.id, clip.filterType, val),
          ),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: filters.isNotEmpty
                ? filters.map((f) {
                    final id = f['id'] as int? ?? 0;
                    final name = f['name'] as String? ?? 'Unknown';
                    return _filterChip(name, id, clip.filterType == id, () {
                      // v0.7.8: Undoable per-clip filter selection
                      controller.setClipFilter(clip.id, id, clip.filterIntensity);
                    });
                  }).toList()
                : _defaultFilterChips(clip),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // Global Filter Card
  // ============================================================

  Widget _buildGlobalFilterCard(List<Map<String, dynamic>> filters, EditorController controller) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
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
                  style: const TextStyle(color: AppTheme.textMain, fontWeight: FontWeight.w600, fontSize: 11),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 16, color: AppTheme.textMuted),
                onPressed: () => controller.setFilter(0, 1.0),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text('Intensity', style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
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

  // ============================================================
  // Transition Card
  // ============================================================

  Widget _buildTransitionCard(Clip clip, EditorController controller) {
    // v1.1.0 (PLAN 3.12): Only the transitions the ENGINE actually renders —
    // the v1.0.0 changelog claimed Slide/Wipe/Zoom/Dissolve/Radial were real,
    // but the compositor only implements FadeIn/FadeOut/Crossfade (the others
    // were metadata-only no-ops). Honest dropdown until the effects exist.
    final transitions = ['None', 'Fade In', 'Fade Out', 'Crossfade'];
    final safeType = clip.transitionType.clamp(0, transitions.length - 1);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.animation_rounded, color: AppTheme.primaryLight, size: 14),
              const SizedBox(width: 6),
              const Text('TRANSITION', style: TextStyle(color: AppTheme.textMain, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
            ],
          ),
          const SizedBox(height: 8),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              // v0.7.8: Reflect the clip's actual transition instead of 'None'
              value: transitions[safeType],
              isExpanded: true,
              dropdownColor: AppTheme.surface,
              style: const TextStyle(color: AppTheme.textMain, fontSize: 12),
              items: transitions.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
              onChanged: (val) {
                if (val != null) {
                  final idx = transitions.indexOf(val);
                  controller.setClipTransition(clip.id, idx, 500);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // Audio Mixer Card
  // ============================================================

  Widget _buildAudioMixerCard(EditorController controller) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Master', style: TextStyle(color: AppTheme.textMain, fontSize: 11)),
              Text('${(controller.volume * 100).toInt()}%', style: TextStyle(color: AppTheme.accent, fontSize: 10, fontWeight: FontWeight.w600, fontFamily: 'monospace')),
            ],
          ),
          Slider(
            value: controller.volume.clamp(0.0, 2.0),
            min: 0.0,
            max: 2.0,
            activeColor: AppTheme.accent,
            onChanged: controller.setVolume,
          ),
          if (controller.selectedClip != null && controller.selectedClips.length == 1) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Clip', style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
                Text('${(controller.selectedClip!.volume * 100).toInt()}%', style: TextStyle(color: AppTheme.accent, fontSize: 10, fontWeight: FontWeight.w600, fontFamily: 'monospace')),
              ],
            ),
            Slider(
              value: controller.selectedClip!.volume.clamp(0.0, 2.0),
              min: 0.0,
              max: 2.0,
              activeColor: AppTheme.primaryLight,
              // v0.7.8: Route through the undoable setClipVolume like the
              // Transform card (was a direct mutation without undo).
              onChangeStart: (_) => controller.beginPropertyGesture(),
              onChanged: (val) => controller.setClipVolume(controller.selectedClip!.id, val),
            ),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // Engine Info Card
  // ============================================================

  Widget _buildEngineInfoCard(EditorController controller) {
    final hasFFmpeg = controller.engineService.ffmpegAvailable;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(hasFFmpeg ? Icons.memory_rounded : Icons.developer_mode_rounded, color: hasFFmpeg ? AppTheme.success : AppTheme.textMuted, size: 14),
              const SizedBox(width: 6),
              // v0.7.8: Clamp long status text in narrow panels
              Flexible(
                child: Text(
                  hasFFmpeg ? 'FFmpeg Accelerated' : 'Demo Mode (Synthetic)',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: hasFFmpeg ? AppTheme.success : AppTheme.textMuted, fontSize: 10, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            controller.engineVersion.isNotEmpty ? controller.engineVersion : 'Engine not loaded',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 9),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // Filter Chip Widget
  // ============================================================

  // v0.7.9: UX-03 — chips carry a tooltip describing the effect, and an
  // optional disabled state (opacity + lock) for unsupported filter ids.
  Widget _filterChip(String label, int type, bool isActive, VoidCallback onTap,
      {String tooltip = '', bool isSupported = true}) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: isSupported ? onTap : null,
        child: Opacity(
          opacity: isSupported ? 1.0 : 0.45,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isActive ? AppTheme.primary.withValues(alpha: 0.2) : AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(AppTheme.radiusFull),
              border: Border.all(color: isActive ? AppTheme.primaryLight : AppTheme.divider, width: isActive ? 1.2 : 0.5),
            ),
            // v0.8.0: Cap the chip width + ellipsis — the engine-driven chip
            // list uses full filter names ("Chromatic Aberration") that
            // overflowed the 201px Wrap lane by a few pixels.
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 190),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: TextStyle(
                        color: isActive ? AppTheme.primaryLight : AppTheme.textMuted,
                        fontSize: 10,
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (!isSupported) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.lock_rounded, size: 10, color: AppTheme.textMuted),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _defaultFilterChips(Clip? clip) {
    // v0.7.8: Chips are functional — per-clip chips update the clip model,
    // global chips go through controller.setFilter (previously dead onTap).
    // v0.7.9: Each chip now carries a descriptive tooltip (UX-03).
    // v1.1.0 (PLAN 1.1/B15): Fallback list extended 0-22 — it only renders
    // when the engine JSON is unavailable (demo mode), but it must not claim
    // the supported filters are missing.
    const names = {
      0: 'None', 1: 'Gray', 2: 'Sepia', 3: 'Invert', 4: 'Bright',
      5: 'Blur', 6: 'Edge', 7: 'Grade', 8: 'Adjust', 9: 'Pixel', 10: 'Mosaic',
      11: 'VHS', 12: 'Glitch', 13: 'Chromatic', 14: 'Vignette', 15: 'Grain',
      16: 'Light Leak', 17: 'Sharpen', 18: 'Posterize', 19: 'Duotone',
      20: 'BG Blur', 21: 'Skin Retouch', 22: 'Chroma Key',
    };
    const descriptions = {
      0: 'No filter applied',
      1: 'Black & white conversion',
      2: 'Warm brown sepia tone',
      3: 'Invert all colors',
      4: 'Brightness boost',
      5: 'Gaussian blur',
      6: 'Sobel edge detection',
      7: '3×3 color grading matrix',
      8: 'Brightness / contrast / saturation / hue',
      9: 'Pixelate effect',
      10: 'Mosaic effect',
      11: 'VHS scanlines & noise',
      12: 'Horizontal band displacement',
      13: 'RGB channel split',
      14: 'Darkened corners',
      15: 'Static film grain',
      16: 'Warm diagonal light leak',
      17: 'Edge sharpening',
      18: 'Reduced color levels',
      19: 'Blue shadows / orange highlights',
      20: 'Blur outside a center ellipse',
      21: 'Skin smoothing & brightening',
      22: 'Green-screen removal (alpha)',
    };
    final activeType = clip?.filterType ?? controller.activeFilterType;

    final chips = <Widget>[];
    names.forEach((id, label) {
      chips.add(_filterChip(
        label,
        id,
        activeType == id,
        () {
          if (clip != null) {
            clip.filterType = id;
            controller.notifyListeners();
          } else {
            controller.setFilter(id, 1.0);
          }
        },
        tooltip: descriptions[id] ?? '',
      ));
    });

    // v0.8.0: Filters 0-20 are all engine-supported; only truly unknown ids
    // (corrupt/old projects) get a disabled chip.
    if (activeType > 22) {
      chips.add(_filterChip(
        'Filter #$activeType',
        activeType,
        true,
        () {},
        tooltip: 'Unsupported filter id from an older project',
        isSupported: false,
      ));
    }
    return chips;
  }

  // ============================================================
  // Meta Row Helper
  // ============================================================

  Widget _metaRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 10)),
          // v0.7.8: Long values (group ids, paths) used to overflow the row
          // in narrow panels — clamp with ellipsis instead.
          Flexible(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: valueColor ?? AppTheme.textMain, fontSize: 10, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // Formatting Helpers
  // ============================================================

  String _formatDuration(int ms) {
    final totalSec = ms ~/ 1000;
    final min = totalSec ~/ 60;
    final sec = totalSec % 60;
    return '${min.toString().padLeft(2, "0")}:${sec.toString().padLeft(2, "0")}';
  }

  String _formatTimecode(int ms) {
    final totalSeconds = ms / 1000.0;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, "0")}:${seconds.toStringAsFixed(2).padLeft(5, "0")}';
  }

  String _getFilterName(int type) {
    // v1.1.0 (PLAN 1.1/B15): Full 0-22 mapping — the old switch only covered
    // 0-10 and labeled the engine-supported filters 11-22 as "unsupported"
    // (misleading). Names mirror getAvailableFiltersJson in the engine.
    switch (type) {
      case 0: return 'Original (Pass-through)';
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
      case 11: return 'VHS Effect';
      case 12: return 'Glitch';
      case 13: return 'Chromatic Aberration';
      case 14: return 'Vignette';
      case 15: return 'Film Grain';
      case 16: return 'Light Leak';
      case 17: return 'Sharpen';
      case 18: return 'Posterize';
      case 19: return 'Duotone';
      case 20: return 'Background Blur';
      case 21: return 'Skin Retouch';
      case 22: return 'Chroma Key';
      // v0.7.8: Truly unknown ids (corrupt/very old projects) show honestly
      // instead of being mislabeled as "Original".
      default: return 'Filter #$type (unsupported)';
    }
  }

  IconData _iconForClipType(ClipType type) {
    switch (type) {
      case ClipType.video: return Icons.movie;
      case ClipType.audio: return Icons.music_note;
      case ClipType.image: return Icons.image;
      case ClipType.text: return Icons.title;
      case ClipType.overlay: return Icons.layers;
      case ClipType.sticker: return Icons.emoji_emotions;
    }
  }
}

// ============================================================
// Color Picker Grid Widget
// ============================================================

class _ColorGrid extends StatelessWidget {
  final List<Color> colors;
  final ValueChanged<Color> onColorTap;

  const _ColorGrid({required this.colors, required this.onColorTap});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: 1.0,
      ),
      itemCount: colors.length,
      itemBuilder: (context, index) {
        final color = colors[index];
        return GestureDetector(
          onTap: () => onColorTap(color),
          child: Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.divider, width: 0.5),
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 4, spreadRadius: -2),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ====================================================================
// v1.0.0: Text content field with undo/redo sync. A vanilla TextField
// keeps its own internal editing state and ignores external changes to
// the bound clip, so undo/redo of text edits left the field stale. This
// widget owns a TextEditingController and re-syncs when the clip's
// textContent diverges from what the user has typed locally.
// ====================================================================
class _TextContentField extends StatefulWidget {
  final Clip clip;
  final ValueChanged<String> onChanged;
  const _TextContentField({required this.clip, required this.onChanged});

  @override
  State<_TextContentField> createState() => _TextContentFieldState();
}

class _TextContentFieldState extends State<_TextContentField> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.clip.textContent);
  }

  @override
  void didUpdateWidget(covariant _TextContentField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Clip switched → reset to the new clip's text.
    if (oldWidget.clip.id != widget.clip.id) {
      _controller.text = widget.clip.textContent;
      return;
    }
    // Same clip, but the text was changed outside the field (undo, redo,
    // paste from Media Bin, programmatic setClipText). The clip object is
    // mutated in place, so oldWidget.clip == widget.clip — comparing against
    // the controller's current text is the only reliable signal.
    if (_controller.text != widget.clip.textContent) {
      _controller.text = widget.clip.textContent;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      maxLines: 3,
      decoration: InputDecoration(
        hintText: 'Enter text...',
        hintStyle: TextStyle(color: AppTheme.textMuted, fontSize: 12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      style: TextStyle(color: AppTheme.textMain, fontSize: 13),
      onChanged: widget.onChanged,
    );
  }
}
