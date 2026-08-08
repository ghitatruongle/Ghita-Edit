import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../controllers/editor_controller.dart';
import '../../controllers/command_history.dart';
import '../../models/clip.dart';
import '../theme/app_theme.dart';

// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

// ============================================================
// MediaBin — v0.7.0 Enhanced with Stickers & Rich Presets
// ============================================================

class MediaBin extends StatefulWidget {
  final EditorController controller;
  // v1.0.0: Optional initial/requested tab index (0=Media 1=Audio 2=Stickers
  // 3=Effects 4=Text). The bottom toolbar tools set this to jump to the
  // relevant tab. When the parent changes it, the bin animates to that tab.
  final int initialTab;

  const MediaBin({super.key, required this.controller, this.initialTab = 0});

  @override
  State<MediaBin> createState() => _MediaBinState();
}

class _MediaBinState extends State<MediaBin> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _searchQuery = '';

  // v0.7.0: Imported media + stickers
  final List<Map<String, dynamic>> _importedMedia = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    // v1.0.0: respect the requested initial tab.
    if (widget.initialTab > 0 && widget.initialTab < 5) {
      _tabController.index = widget.initialTab;
    }
    _syncImportedMedia();
  }

  @override
  void didUpdateWidget(covariant MediaBin oldWidget) {
    super.didUpdateWidget(oldWidget);
    // v1.0.0: jump to the tab requested by the parent (toolbar tools).
    if (oldWidget.initialTab != widget.initialTab &&
        widget.initialTab >= 0 &&
        widget.initialTab < 5) {
      _tabController.animateTo(widget.initialTab);
    }
    _syncImportedMedia();
  }

  void _syncImportedMedia() {
    final clips = widget.controller.project.allClips;
    final existingIds = _importedMedia.map((m) => m['id'] as String).toSet();

    for (final clip in clips) {
      if (!existingIds.contains(clip.id)) {
        _importedMedia.add({
          'id': clip.id,
          'name': clip.displayName,
          'duration': _formatDuration(clip.durationMs),
          'type': _typeString(clip.type),
          'path': clip.sourceFilePath,
          'clip': clip,
        });
      }
    }

    // v1.0.2: O(1) lookup — the old `clips.any(...)` per entry made this
    // quadratic, and it runs on every parent rebuild (30 fps during playback).
    final liveIds = clips.map((c) => c.id).toSet();
    _importedMedia.removeWhere((m) => !liveIds.contains(m['id'] as String));
  }

  String _typeString(ClipType type) {
    switch (type) {
      case ClipType.video: return 'video';
      case ClipType.audio: return 'audio';
      case ClipType.image: return 'image';
      case ClipType.text: return 'text';
      case ClipType.overlay: return 'overlay';
      case ClipType.sticker: return 'sticker';
    }
  }

  String _formatDuration(int ms) {
    final totalSec = ms ~/ 1000;
    final min = totalSec ~/ 60;
    final sec = totalSec % 60;
    return '${min.toString().padLeft(2, "0")}:${sec.toString().padLeft(2, "0")}';
  }

  List<Map<String, dynamic>> get _filteredMedia {
    if (_searchQuery.isEmpty) return _importedMedia;
    return _importedMedia.where((item) {
      return item['name'].toString().toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _openFilePicker() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Import Media File',
        type: FileType.custom,
        allowedExtensions: ['mp4', 'mov', 'avi', 'mkv', 'mp3', 'wav', 'flac', 'png', 'jpg', 'jpeg', 'webm', 'gif'],
      );
      if (result != null && mounted) {
        widget.controller.importMedia(result.files.single.path!);
        _syncImportedMedia();
        setState(() {});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Imported: ${result.files.single.name}'), duration: const Duration(seconds: 2)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick file: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.surface,
      child: Column(
        children: [
          // v0.7.0: Navigation Tabs (5 tabs)
          Container(
            color: AppTheme.card,
            child: TabBar(
              controller: _tabController,
              indicatorColor: AppTheme.primaryLight,
              labelColor: AppTheme.primaryLight,
              unselectedLabelColor: AppTheme.textMuted,
              labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.2),
              tabs: const [
                Tab(icon: Icon(Icons.folder_rounded, size: 16), text: 'Media'),
                Tab(icon: Icon(Icons.music_note_rounded, size: 16), text: 'Audio'),
                Tab(icon: Icon(Icons.emoji_emotions_rounded, size: 16), text: 'Stickers'),
                Tab(icon: Icon(Icons.auto_fix_high_rounded, size: 16), text: 'Effects'),
                Tab(icon: Icon(Icons.title_rounded, size: 16), text: 'Text'),
              ],
            ),
          ),

          // Search & Import
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search...',
                    hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                    prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textMuted, size: 16),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSm), borderSide: BorderSide.none),
                    fillColor: AppTheme.background,
                    filled: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  ),
                  style: const TextStyle(color: AppTheme.textMain, fontSize: 12),
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
                const SizedBox(height: 6),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSm + 2)),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Import', style: TextStyle(fontSize: 11)),
                  onPressed: _openFilePicker,
                ),
              ],
            ),
          ),

          // Tab Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildMediaGrid(),
                _buildAudioPresets(),
                _buildStickersGrid(),
                _buildEffectsList(),
                _buildTextPresetsEnhanced(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // Media Grid Tab
  // ============================================================

  Widget _buildMediaGrid() {
    final mediaItems = _filteredMedia.where((m) => ['video', 'image', 'overlay'].contains(m['type'])).toList();

    if (mediaItems.isEmpty) {
      // v0.7.9: UX-02 — friendlier empty state with a direct import action.
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.folder_open_rounded, size: 48, color: AppTheme.textMuted),
            const SizedBox(height: 12),
            const Text(
              'No media imported yet',
              style: TextStyle(color: AppTheme.textMain, fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            const Text(
              'Click "Import" or drag media in from your files',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Import Media', style: TextStyle(fontSize: 11)),
              onPressed: _openFilePicker,
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(6),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: 1.1,
      ),
      itemCount: mediaItems.length,
      itemBuilder: (context, index) {
        final item = mediaItems[index];
        final path = item['path'] as String? ?? '';
        // v0.7.9: PERF-03 — serve cached thumbnails when the engine has
        // produced one; otherwise the tile falls back to its type icon.
        final thumb = path.isNotEmpty
            ? widget.controller.engineService.getCachedThumbnail(path)
            : null;
        return LongPressDraggable<Map<String, dynamic>>(
          data: item,
          feedback: Material(color: Colors.transparent, child: _MediaTile(name: item['name'] as String, duration: item['duration'] as String, type: item['type'] as String, isDragging: true, thumbnail: thumb)),
          child: _MediaTile(name: item['name'] as String, duration: item['duration'] as String, type: item['type'] as String, isDragging: false, thumbnail: thumb),
        );
      },
    );
  }

  // ============================================================
  // Audio Presets Tab
  // ============================================================

  Widget _buildAudioPresets() {
    final audioItems = _filteredMedia.where((m) => m['type'] == 'audio').toList();

    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        if (audioItems.isNotEmpty) ...[
          const Text('Imported Audio', style: TextStyle(color: AppTheme.textMuted, fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
          const SizedBox(height: 4),
          // v0.8.0: Tapping selects the existing clip (and seeks to it) —
          // it used to call importMedia again, duplicating the clip on the
          // timeline on every tap.
          // v1.0.2: If the media was never imported as a timeline clip (e.g.
          // a leftover bin entry), tap adds it to the timeline instead of
          // silently selecting nothing.
          ...audioItems.map((item) => _presetTile(item['name'] as String, 'Audio', Icons.music_note_rounded, () {
            final clip = item['clip'] as dynamic;
            if (clip != null) {
              final id = clip.id as String;
              final onTimeline = widget.controller.project.allClips.any((c) => c.id == id);
              if (onTimeline) {
                widget.controller.selectClip(id);
                widget.controller.seek(clip.timelineStartMs as int);
              } else {
                final path = item['path'] as String?;
                if (path != null && path.isNotEmpty) {
                  widget.controller.importMedia(path);
                }
              }
            }
          })),
          const SizedBox(height: 10),
        ],
        // v0.7.8: Removed the dead "Audio FX Presets" tiles — they had no
        // backing feature and did nothing when tapped.
      ],
    );
  }

  // ============================================================
  // Stickers Grid Tab (v0.7.0)
  // ============================================================

  Widget _buildStickersGrid() {
    final stickers = _stickerData;
    return GridView.builder(
      padding: const EdgeInsets.all(6),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.0,
      ),
      itemCount: stickers.length,
      itemBuilder: (context, index) {
        final sticker = stickers[index];
        return _StickerTile(
          emoji: sticker['emoji'] as String,
          label: sticker['label'] as String,
          onTap: () => _addStickerClip(sticker['emoji'] as String, sticker['label'] as String),
        );
      },
    );
  }

  void _addStickerClip(String emoji, String label) {
    final ctrl = widget.controller;
    final clip = Clip(
      id: Clip.nextId(),
      sourceFilePath: '',
      displayName: label,
      timelineStartMs: ctrl.positionMs,
      durationMs: 3000,
      type: ClipType.sticker,
      textContent: emoji,
      textFontSize: 64.0,
      stickerScale: 1.0,
    );
    // v0.7.8: Resolve the overlay track via the controller (falls back to the
    // first track) — hardcoding 'track_overlay_1' silently no-op'd the add
    // when a loaded project lacks that track.
    final trackId = ctrl.trackIdForClipType(ClipType.sticker);
    if (trackId == null) return;
    final cmd = AddClipCommand(
      trackId: trackId,
      clip: clip,
      positionMs: ctrl.positionMs,
    );
    ctrl.commandHistory.execute(cmd, ctrl.project);
    ctrl.notifyListeners();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added $label sticker'), duration: const Duration(seconds: 2)),
      );
    }
  }

  // ============================================================
  // Effects List Tab
  // ============================================================

  Widget _buildEffectsList() {
    final engineFilters = widget.controller.engineService.availableFilters;

    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        const Text('Filters', style: TextStyle(color: AppTheme.textMuted, fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
        const SizedBox(height: 4),
        if (engineFilters.isNotEmpty)
          ...engineFilters.map((f) {
            final id = f['id'] as int? ?? 0;
            final name = f['name'] as String? ?? 'Unknown';
            final isActive = widget.controller.activeFilterType == id;
            return _buildFilterTile(name, id, isActive, widget.controller);
          })
        else
          ..._defaultFilterTiles(),
      ],
    );
  }

  List<Widget> _defaultFilterTiles() {
    // v0.8.0: All 21 filters (0-20) are engine-supported and wired to
    // setFilter — the "Coming soon" state is gone.
    final supported = <int, String>{
      0: 'Original (No Filter)',
      1: 'Grayscale',
      2: 'Sepia Tone',
      3: 'Negative / Invert',
      4: 'Brightness Boost',
      5: 'Gaussian Blur',
      6: 'Edge Detect (Sobel)',
      7: 'Color Grading',
      8: 'BCSH Adjust',
      9: 'Pixelate',
      10: 'Mosaic',
      11: 'VHS Effect',
      12: 'Glitch',
      13: 'Chromatic Aberration',
      14: 'Vignette',
      15: 'Film Grain',
      16: 'Light Leak',
      17: 'Sharpen',
      18: 'Posterize',
      19: 'Duotone',
      20: 'Background Blur',
    };
    final ctrl = widget.controller;
    return [
      ...supported.entries.map((e) =>
          _buildFilterTile(e.value, e.key, ctrl.activeFilterType == e.key, ctrl)),
    ];
  }

  // ============================================================
  // Text Presets Enhanced Tab (v0.7.0)
  // ============================================================

  Widget _buildTextPresetsEnhanced() {
    final textPresets = [
      {'name': 'Title Banner', 'subtitle': 'Text Overlay', 'icon': Icons.title_rounded, 'preset': _TitleBannerPreset()},
      {'name': 'Subtitle', 'subtitle': 'Text Overlay', 'icon': Icons.subtitles_rounded, 'preset': _SubtitlePreset()},
      {'name': 'Lower Third', 'subtitle': 'Graphics', 'icon': Icons.featured_play_list_rounded, 'preset': _LowerThirdPreset()},
      {'name': 'Watermark', 'subtitle': 'Text Overlay', 'icon': Icons.water_damage_rounded, 'preset': _WatermarkPreset()},
      // v0.7.0: New text presets
      {'name': 'Callout', 'subtitle': 'Text Overlay', 'icon': Icons.chat_bubble_rounded, 'preset': _CalloutPreset()},
      {'name': 'Neon Glow', 'subtitle': 'Text Overlay', 'icon': Icons.auto_awesome_rounded, 'preset': _NeonGlowPreset()},
      {'name': 'Pop-up', 'subtitle': 'Text Overlay', 'icon': Icons.chat_bubble_rounded, 'preset': _PopupPreset()},
      {'name': 'Cinematic', 'subtitle': 'Text Overlay', 'icon': Icons.movie_rounded, 'preset': _CinematicPreset()},
      {'name': 'Handwriting', 'subtitle': 'Text Overlay', 'icon': Icons.edit_rounded, 'preset': _HandwritingPreset()},
    ];

    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        const Text('Text Presets', style: TextStyle(color: AppTheme.textMuted, fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
        const SizedBox(height: 4),
        ...textPresets.map((preset) {
          return _presetTile(preset['name'] as String, preset['subtitle'] as String, preset['icon'] as IconData, () {
            _addTextClipWithPreset(preset['name'] as String, preset['preset'] as _TextPreset);
          });
        }),
      ],
    );
  }

  void _addTextClipWithPreset(String presetName, _TextPreset preset) {
    final ctrl = widget.controller;
    final clip = Clip(
      id: Clip.nextId(),
      sourceFilePath: '',
      displayName: presetName,
      timelineStartMs: ctrl.positionMs,
      durationMs: preset.durationMs,
      type: ClipType.text,
      textContent: preset.text,
      textFont: preset.font,
      textFontSize: preset.fontSize,
      textColorValue: preset.color.toARGB32(),
      textBold: preset.bold,
      textItalic: preset.italic,
      textUnderline: preset.underline,
      textStrokeWidth: preset.strokeWidth,
      textStrokeColorValue: preset.strokeColor.toARGB32(),
      textShadow: preset.shadow,
      textBackgroundColorValue: preset.backgroundColor.toARGB32(),
      textAlignment: preset.alignment,
      textGradient: preset.gradient,
    );
    // v0.7.8: Same track resolution as stickers (see _addStickerClip).
    final trackId = ctrl.trackIdForClipType(ClipType.text);
    if (trackId == null) return;
    final cmd = AddClipCommand(
      trackId: trackId,
      clip: clip,
      positionMs: ctrl.positionMs,
    );
    ctrl.commandHistory.execute(cmd, ctrl.project);
    ctrl.notifyListeners();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added $presetName'), duration: const Duration(seconds: 2)),
      );
    }
  }

  // ============================================================
  // Shared Tile Builders
  // ============================================================

  Widget _presetTile(String title, String subtitle, IconData icon, VoidCallback onTap) {
    return Card(
      color: AppTheme.card,
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSm), side: const BorderSide(color: AppTheme.divider, width: 0.5)),
      child: ListTile(
        leading: Icon(icon, color: AppTheme.primaryLight, size: 18),
        title: Text(title, style: const TextStyle(color: AppTheme.textMain, fontSize: 12)),
        subtitle: Text(subtitle, style: const TextStyle(color: AppTheme.textMuted, fontSize: 10)),
        trailing: const Icon(Icons.add_circle_outline_rounded, color: AppTheme.accent, size: 20),
        onTap: onTap,
      ),
    );
  }

  Widget _buildFilterTile(String name, int type, bool isActive, EditorController ctrl) {
    return Card(
      color: isActive ? AppTheme.primary.withValues(alpha: 0.2) : AppTheme.card,
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        side: BorderSide(color: isActive ? AppTheme.primaryLight : AppTheme.divider, width: isActive ? 1.2 : 0.5),
      ),
      child: ListTile(
        leading: Icon(Icons.color_lens_rounded, color: isActive ? AppTheme.primaryLight : AppTheme.textMuted, size: 16),
        title: Text(name, style: const TextStyle(color: AppTheme.textMain, fontSize: 11)),
        trailing: isActive
            ? const Icon(Icons.check_circle_rounded, color: AppTheme.primaryLight, size: 18)
            : const Icon(Icons.play_arrow_rounded, color: AppTheme.textMuted, size: 16),
        onTap: () => ctrl.setFilter(type, 1.0),
      ),
    );
  }
}

// ============================================================
// Media Tile Widget
// ============================================================

class _MediaTile extends StatelessWidget {
  final String name;
  final String duration;
  final String type;
  final bool isDragging;
  // v0.7.9: PERF-03 — optional cached thumbnail (path-keyed from EngineService).
  final Uint8List? thumbnail;

  const _MediaTile({required this.name, required this.duration, required this.type, this.isDragging = false, this.thumbnail});

  @override
  Widget build(BuildContext context) {
    final thumb = thumbnail;
    return Container(
      decoration: BoxDecoration(
        color: isDragging ? AppTheme.primary.withValues(alpha: 0.2) : AppTheme.card,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: isDragging ? AppTheme.primaryLight : AppTheme.divider, width: isDragging ? 1.2 : 0.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (thumb != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(thumb, width: 48, height: 48, fit: BoxFit.cover, gaplessPlayback: true),
            )
          else
            Icon(
              type == 'video' ? Icons.movie_rounded : type == 'audio' ? Icons.music_note_rounded : type == 'text' ? Icons.title_rounded : Icons.image_rounded,
              color: AppTheme.accent,
              size: 28,
            ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.textMain, fontSize: 10, fontWeight: FontWeight.w500)),
          ),
          Text(duration, style: const TextStyle(color: AppTheme.textMuted, fontSize: 9)),
        ],
      ),
    );
  }
}

// ============================================================
// Sticker Tile Widget (v0.7.0)
// ============================================================

class _StickerTile extends StatelessWidget {
  final String emoji;
  final String label;
  final VoidCallback onTap;

  const _StickerTile({required this.emoji, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(color: AppTheme.divider, width: 0.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 8), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Text Preset Definitions (v0.7.0)
// ============================================================

abstract class _TextPreset {
  String get text;
  String get font;
  double get fontSize;
  Color get color;
  bool get bold;
  bool get italic;
  bool get underline;
  double get strokeWidth;
  Color get strokeColor;
  bool get shadow;
  Color get backgroundColor;
  int get alignment;
  bool get gradient;
  int get durationMs;
}

class _TitleBannerPreset extends _TextPreset {
  @override String get text => 'YOUR TITLE';
  @override String get font => 'Impact';
  @override double get fontSize => 72.0;
  @override Color get color => Colors.white;
  @override bool get bold => true;
  @override bool get italic => false;
  @override bool get underline => false;
  @override double get strokeWidth => 4.0;
  @override Color get strokeColor => Colors.black;
  @override bool get shadow => true;
  @override Color get backgroundColor => Color(0x00000000);
  @override int get alignment => 1;
  @override bool get gradient => false;
  @override int get durationMs => 5000;
}

class _SubtitlePreset extends _TextPreset {
  @override String get text => 'Subtitle text here';
  @override String get font => 'Segoe UI';
  @override double get fontSize => 36.0;
  @override Color get color => Colors.white;
  @override bool get bold => false;
  @override bool get italic => false;
  @override bool get underline => false;
  @override double get strokeWidth => 2.0;
  @override Color get strokeColor => Colors.black;
  @override bool get shadow => true;
  @override Color get backgroundColor => Color(0x80000000);
  @override int get alignment => 1;
  @override bool get gradient => false;
  @override int get durationMs => 4000;
}

class _LowerThirdPreset extends _TextPreset {
  @override String get text => 'YOUR NAME';
  @override String get font => 'Arial';
  @override double get fontSize => 40.0;
  @override Color get color => Colors.white;
  @override bool get bold => true;
  @override bool get italic => false;
  @override bool get underline => false;
  @override double get strokeWidth => 1.0;
  @override Color get strokeColor => Color(0xFF7C4DFF);
  @override bool get shadow => false;
  @override Color get backgroundColor => Color(0xFF7C4DFF);
  @override int get alignment => 0;
  @override bool get gradient => true;
  @override int get durationMs => 5000;
}

class _WatermarkPreset extends _TextPreset {
  @override String get text => 'GHITA EDIT';
  @override String get font => 'Verdana';
  @override double get fontSize => 24.0;
  @override Color get color => Colors.white;
  @override bool get bold => false;
  @override bool get italic => false;
  @override bool get underline => false;
  @override double get strokeWidth => 0.0;
  @override Color get strokeColor => Colors.black;
  @override bool get shadow => true;
  @override Color get backgroundColor => Color(0x00000000);
  @override int get alignment => 2;
  @override bool get gradient => false;
  @override int get durationMs => 10000;
}

// v0.7.0: New text presets
class _CalloutPreset extends _TextPreset {
  @override String get text => 'Tap here!';
  @override String get font => 'Segoe UI';
  @override double get fontSize => 42.0;
  @override Color get color => Colors.white;
  @override bool get bold => true;
  @override bool get italic => false;
  @override bool get underline => false;
  @override double get strokeWidth => 3.0;
  @override Color get strokeColor => Colors.red;
  @override bool get shadow => true;
  @override Color get backgroundColor => Color(0xFFE53935);
  @override int get alignment => 1;
  @override bool get gradient => false;
  @override int get durationMs => 3000;
}

class _NeonGlowPreset extends _TextPreset {
  @override String get text => 'NEON';
  @override String get font => 'Impact';
  @override double get fontSize => 80.0;
  @override Color get color => Color(0xFFFF00FF);
  @override bool get bold => true;
  @override bool get italic => false;
  @override bool get underline => false;
  @override double get strokeWidth => 0.0;
  @override Color get strokeColor => Colors.black;
  @override bool get shadow => true;
  @override Color get backgroundColor => Color(0x00000000);
  @override int get alignment => 1;
  @override bool get gradient => true;
  @override int get durationMs => 4000;
}

class _PopupPreset extends _TextPreset {
  @override String get text => 'Pop-up!';
  @override String get font => 'Comic Sans MS';
  @override double get fontSize => 48.0;
  @override Color get color => Colors.yellow;
  @override bool get bold => true;
  @override bool get italic => false;
  @override bool get underline => false;
  @override double get strokeWidth => 2.0;
  @override Color get strokeColor => Colors.black;
  @override bool get shadow => true;
  @override Color get backgroundColor => Color(0x00000000);
  @override int get alignment => 1;
  @override bool get gradient => false;
  @override int get durationMs => 2000;
}

class _CinematicPreset extends _TextPreset {
  @override String get text => 'CINEMATIC';
  @override String get font => 'Georgia';
  @override double get fontSize => 60.0;
  @override Color get color => Color(0xFFE0E0E0);
  @override bool get bold => false;
  @override bool get italic => true;
  @override bool get underline => false;
  @override double get strokeWidth => 1.0;
  @override Color get strokeColor => Color(0xFF424242);
  @override bool get shadow => true;
  @override Color get backgroundColor => Color(0x00000000);
  @override int get alignment => 1;
  @override bool get gradient => false;
  @override int get durationMs => 5000;
}

class _HandwritingPreset extends _TextPreset {
  @override String get text => 'My Note';
  @override String get font => 'Trebuchet MS';
  @override double get fontSize => 44.0;
  @override Color get color => Color(0xFF2E7D32);
  @override bool get bold => false;
  @override bool get italic => true;
  @override bool get underline => true;
  @override double get strokeWidth => 0.0;
  @override Color get strokeColor => Colors.black;
  @override bool get shadow => false;
  @override Color get backgroundColor => Color(0x00000000);
  @override int get alignment => 0;
  @override bool get gradient => false;
  @override int get durationMs => 4000;
}

// ============================================================
// Sticker Data (v0.7.0 — 24 curated emoji/stickers)
// ============================================================

const _stickerData = [
  {'emoji': '👍', 'label': 'Like'},
  {'emoji': '❤️', 'label': 'Heart'},
  {'emoji': '🔥', 'label': 'Fire'},
  {'emoji': '⭐', 'label': 'Star'},
  {'emoji': '🎉', 'label': 'Party'},
  {'emoji': '😂', 'label': 'LOL'},
  {'emoji': '😮', 'label': 'Wow'},
  {'emoji': '👏', 'label': 'Clap'},
  {'emoji': '💯', 'label': '100'},
  {'emoji': '✨', 'label': 'Sparkle'},
  {'emoji': '👆', 'label': 'Up'},
  {'emoji': '👇', 'label': 'Down'},
  {'emoji': '✅', 'label': 'Check'},
  {'emoji': '❌', 'label': 'Cross'},
  {'emoji': '💬', 'label': 'Comment'},
  {'emoji': '📌', 'label': 'Pin'},
  {'emoji': '🎯', 'label': 'Target'},
  {'emoji': '🏆', 'label': 'Trophy'},
  {'emoji': '🚀', 'label': 'Rocket'},
  {'emoji': '💡', 'label': 'Idea'},
  {'emoji': '🎵', 'label': 'Music'},
  {'emoji': '📸', 'label': 'Camera'},
  {'emoji': '💬', 'label': 'Chat'},
  {'emoji': '🔔', 'label': 'Bell'},
];
