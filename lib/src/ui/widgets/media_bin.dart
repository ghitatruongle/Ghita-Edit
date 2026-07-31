import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../controllers/editor_controller.dart';
import '../../controllers/command_history.dart';
import '../../models/clip.dart';
import '../theme/app_theme.dart';

class MediaBin extends StatefulWidget {
  final EditorController controller;

  const MediaBin({super.key, required this.controller});

  @override
  State<MediaBin> createState() => _MediaBinState();
}

class _MediaBinState extends State<MediaBin> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _searchQuery = '';

  // v0.5.5: Track imported media for display in the bin
  final List<Map<String, dynamic>> _importedMedia = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _syncImportedMedia();
  }

  @override
  void didUpdateWidget(covariant MediaBin oldWidget) {
    super.didUpdateWidget(oldWidget);
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

    // Remove entries for clips that no longer exist
    _importedMedia.removeWhere((m) {
      final id = m['id'] as String;
      return !clips.any((c) => c.id == id);
    });
  }

  String _typeString(ClipType type) {
    switch (type) {
      case ClipType.video: return 'video';
      case ClipType.audio: return 'audio';
      case ClipType.image: return 'image';
      case ClipType.text: return 'text';
      case ClipType.overlay: return 'overlay';
    }
  }

  String _formatDuration(int ms) {
    final totalSec = ms ~/ 1000;
    final min = totalSec ~/ 60;
    final sec = totalSec % 60;
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
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
            SnackBar(
              content: Text('Imported: ${result.files.single.name}'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pick file: $e'),
            backgroundColor: Colors.red,
          ),
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
          // Navigation Tabs
          Container(
            color: AppTheme.card,
            child: TabBar(
              controller: _tabController,
              indicatorColor: AppTheme.primaryLight,
              labelColor: AppTheme.primaryLight,
              unselectedLabelColor: AppTheme.textMuted,
              labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              tabs: const [
                Tab(icon: Icon(Icons.folder, size: 18), text: 'Media'),
                Tab(icon: Icon(Icons.audiotrack, size: 18), text: 'Audio'),
                Tab(icon: Icon(Icons.auto_fix_high, size: 18), text: 'Effects'),
                Tab(icon: Icon(Icons.title, size: 18), text: 'Text'),
              ],
            ),
          ),

          // Search & Import Bar
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search media...',
                    hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                    prefixIcon: const Icon(Icons.search, color: AppTheme.textMuted, size: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    fillColor: AppTheme.background,
                    filled: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  style: const TextStyle(color: AppTheme.textMain, fontSize: 12),
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Import File', style: TextStyle(fontSize: 12)),
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
                // Media Grid — v0.5.5: real imported clips with drag support
                _buildMediaGrid(),

                // Audio presets
                _buildAudioPresets(),

                // Effects / Filters
                _buildEffectsList(),

                // Text Presets — v0.5.5
                _buildTextPresets(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ========== Media Grid ==========

  Widget _buildMediaGrid() {
    final mediaItems = _filteredMedia.where((m) => ['video', 'image', 'overlay'].contains(m['type'])).toList();

    if (mediaItems.isEmpty) {
      return const Center(
        child: Text('No media imported yet.\nClick "Import File" to add media.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.2,
      ),
      itemCount: mediaItems.length,
          itemBuilder: (context, index) {
            final item = mediaItems[index];
            // v0.5.5: clip metadata available for future thumbnail display
            // final clip = item['clip'] as Clip?;
        return LongPressDraggable<Map<String, dynamic>>(
          data: item,
          feedback: Material(
            color: Colors.transparent,
            child: _MediaTile(
              name: item['name'] as String,
              duration: item['duration'] as String,
              type: item['type'] as String,
              isDragging: true,
            ),
          ),
          child: _MediaTile(
            name: item['name'] as String,
            duration: item['duration'] as String,
            type: item['type'] as String,
            isDragging: false,
          ),
        );
      },
    );
  }

  // ========== Audio Presets ==========

  Widget _buildAudioPresets() {
    final audioItems = _filteredMedia.where((m) => m['type'] == 'audio').toList();

    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        if (audioItems.isNotEmpty) ...[
          const Text('Imported Audio', style: TextStyle(color: AppTheme.textMuted, fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          ...audioItems.map((item) => _buildPresetTile(item['name'] as String, 'Audio', Icons.music_note, () {
            widget.controller.importMedia(item['path'] as String);
          })),
          const SizedBox(height: 12),
        ],
        const Text('Audio FX Presets', style: TextStyle(color: AppTheme.textMuted, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        _buildPresetTile('Cinematic Bass Drop', 'Audio FX', Icons.multitrack_audio, () {}),
        _buildPresetTile('Pop Background Beat', 'Music', Icons.music_note, () {}),
        _buildPresetTile('Vlog Acoustic Guitar', 'Music', Icons.audiotrack, () {}),
      ],
    );
  }

  // ========== Effects List ==========

  Widget _buildEffectsList() {
    final engineFilters = widget.controller.engineService.availableFilters;

    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        const Text('Filters', style: TextStyle(color: AppTheme.textMuted, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        if (engineFilters.isNotEmpty)
          ...engineFilters.map((f) {
            final id = f['id'] as int? ?? 0;
            final name = f['name'] as String? ?? 'Unknown';
            final isActive = widget.controller.activeFilterType == id;
            return _buildFilterTile(name, id, isActive, widget.controller);
          })
        else
          ListView(
            padding: const EdgeInsets.all(8),
            children: [
              _buildFilterTileStatic('Original (No Filter)', 0, false),
              _buildFilterTileStatic('Grayscale Filter', 1, false),
              _buildFilterTileStatic('Warm Sepia Tone', 2, false),
              _buildFilterTileStatic('Negative / Invert', 3, false),
              _buildFilterTileStatic('Brightness Boost', 4, false),
              _buildFilterTileStatic('Gaussian Blur', 5, false),
              _buildFilterTileStatic('Edge Detect (Sobel)', 6, false),
              _buildFilterTileStatic('Color Grading', 7, false),
              _buildFilterTileStatic('Adjust (BCSH)', 8, false),
              _buildFilterTileStatic('Pixelate', 9, false),
              _buildFilterTileStatic('Mosaic', 10, false),
            ],
          ),
      ],
    );
  }

  // ========== Text Presets — v0.5.5 ==========

  Widget _buildTextPresets() {
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        const Text('Text Overlay Presets', style: TextStyle(color: AppTheme.textMuted, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        _buildPresetTile('Title Banner', 'Text Overlay', Icons.title, () {
          _addTextClip('Title Banner');
        }),
        _buildPresetTile('Subtitle', 'Text Overlay', Icons.subtitles, () {
          _addTextClip('Subtitle');
        }),
        _buildPresetTile('Lower Third', 'Graphics', Icons.featured_play_list, () {
          _addTextClip('Lower Third');
        }),
        _buildPresetTile('Watermark', 'Text Overlay', Icons.water_damage, () {
          _addTextClip('Watermark');
        }),
      ],
    );
  }

  void _addTextClip(String presetName) {
    final ctrl = widget.controller;
    final clip = Clip(
      id: 'clip_${DateTime.now().millisecondsSinceEpoch}',
      sourceFilePath: '',
      displayName: presetName,
      timelineStartMs: ctrl.positionMs,
      durationMs: 3000,
      type: ClipType.text,
    );
    final cmd = AddClipCommand(
      trackId: 'track_overlay_1',
      clip: clip,
      positionMs: ctrl.positionMs,
    );
    ctrl.commandHistory.execute(cmd, ctrl.project);
    // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
    ctrl.notifyListeners();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added $presetName to overlay track'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // ========== Shared Tile Builders ==========

  Widget _buildPresetTile(String title, String subtitle, IconData icon, VoidCallback onTap) {
    return Card(
      color: AppTheme.card,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: AppTheme.primaryLight),
        title: Text(title, style: const TextStyle(color: AppTheme.textMain, fontSize: 12)),
        subtitle: Text(subtitle, style: const TextStyle(color: AppTheme.textMuted, fontSize: 10)),
        trailing: const Icon(Icons.add_circle_outline, color: AppTheme.accent, size: 20),
        onTap: onTap,
      ),
    );
  }

  Widget _buildFilterTile(String name, int type, bool isActive, EditorController ctrl) {
    return Card(
      color: isActive ? AppTheme.primary.withValues(alpha: 0.3) : AppTheme.card,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: isActive ? AppTheme.accent : AppTheme.divider),
      ),
      child: ListTile(
        leading: Icon(Icons.color_lens, color: isActive ? AppTheme.accent : AppTheme.textMuted),
        title: Text(name, style: const TextStyle(color: AppTheme.textMain, fontSize: 12)),
        trailing: isActive
            ? const Icon(Icons.check_circle, color: AppTheme.accent, size: 20)
            : const Icon(Icons.play_arrow, color: AppTheme.textMuted, size: 18),
        onTap: () => ctrl.setFilter(type, 1.0),
      ),
    );
  }

  Widget _buildFilterTileStatic(String name, int type, bool isActive) {
    return Card(
      color: AppTheme.card,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(Icons.color_lens, color: AppTheme.textMuted),
        title: Text(name, style: const TextStyle(color: AppTheme.textMain, fontSize: 12)),
        trailing: const Icon(Icons.play_arrow, color: AppTheme.textMuted, size: 18),
        onTap: () {
          debugPrint('Filter $type selected (needs clip selected)');
        },
      ),
    );
  }
}

// ========== Media Tile Widget — v0.5.5 ==========

class _MediaTile extends StatelessWidget {
  final String name;
  final String duration;
  final String type;
  final bool isDragging;

  const _MediaTile({
    required this.name,
    required this.duration,
    required this.type,
    this.isDragging = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDragging ? AppTheme.primary.withValues(alpha: 0.3) : AppTheme.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDragging ? AppTheme.accent : AppTheme.divider),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            type == 'video'
                ? Icons.movie
                : type == 'audio'
                    ? Icons.music_note
                    : type == 'text'
                        ? Icons.title
                        : Icons.image,
            color: AppTheme.accent,
            size: 32,
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textMain,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            duration,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
          ),
        ],
      ),
    );
  }
}
