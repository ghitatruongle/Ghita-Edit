import 'package:flutter/material.dart';
import '../../controllers/editor_controller.dart';
import '../theme/app_theme.dart';

class MediaBin extends StatefulWidget {
  final EditorController controller;

  const MediaBin({super.key, required this.controller});

  @override
  State<MediaBin> createState() => _MediaBinState();
}

class _MediaBinState extends State<MediaBin> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final List<Map<String, String>> _sampleMedia = [
    {"name": "Intro_Vlog_4K.mp4", "duration": "00:45", "type": "video"},
    {"name": "Background_Music.mp3", "duration": "02:30", "type": "audio"},
    {"name": "Cinematic_LUT_01.png", "duration": "Photo", "type": "image"},
    {"name": "Sound_Effect_Whoosh.wav", "duration": "00:03", "type": "audio"},
    {"name": "Overlay_Text_Title.png", "duration": "Text", "type": "text"},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
              labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              tabs: const [
                Tab(icon: Icon(Icons.folder, size: 18), text: "Media"),
                Tab(icon: Icon(Icons.audiotrack, size: 18), text: "Audio"),
                Tab(icon: Icon(Icons.auto_fix_high, size: 18), text: "Effects"),
                Tab(icon: Icon(Icons.title, size: 18), text: "Text"),
              ],
            ),
          ),

          // Search & Import Bar
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text("Import File", style: TextStyle(fontSize: 12)),
                    onPressed: () {
                      widget.controller.loadMedia("C:/Media/New_Imported_Clip.mp4");
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Media loaded into C++ Core Engine!"),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // Media Items Grid
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Media Grid
                GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 1.2,
                  ),
                  itemCount: _sampleMedia.length,
                  itemBuilder: (context, index) {
                    final item = _sampleMedia[index];
                    return GestureDetector(
                      onTap: () => widget.controller.loadMedia(item["name"]!),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppTheme.card,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.divider),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              item["type"] == "video"
                                  ? Icons.movie
                                  : item["type"] == "audio"
                                      ? Icons.music_note
                                      : Icons.image,
                              color: AppTheme.accent,
                              size: 32,
                            ),
                            const SizedBox(height: 6),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4.0),
                              child: Text(
                                item["name"]!,
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
                              item["duration"]!,
                              style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),

                // Audio presets
                ListView(
                  padding: const EdgeInsets.all(8),
                  children: [
                    _buildPresetTile("Cinematic Bass Drop", "Audio FX", Icons.multitrack_audio),
                    _buildPresetTile("Pop Background Beat", "Music", Icons.music_note),
                    _buildPresetTile("Vlog Acoustic Guitar", "Music", Icons.audiotrack),
                  ],
                ),

                // Video FX
                ListView(
                  padding: const EdgeInsets.all(8),
                  children: [
                    _buildFilterTile("Original (No Filter)", 0, widget.controller),
                    _buildFilterTile("Grayscale Filter", 1, widget.controller),
                    _buildFilterTile("Warm Sepia Tone", 2, widget.controller),
                    _buildFilterTile("Negative / Invert", 3, widget.controller),
                  ],
                ),

                // Text Presets
                ListView(
                  padding: const EdgeInsets.all(8),
                  children: [
                    _buildPresetTile("Subtitle Overlay", "Text", Icons.subtitles),
                    _buildPresetTile("Title Banner 3D", "Title", Icons.title),
                    _buildPresetTile("Lower Third Banner", "Graphics", Icons.featured_play_list),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetTile(String title, String subtitle, IconData icon) {
    return Card(
      color: AppTheme.card,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: AppTheme.primaryLight),
        title: Text(title, style: const TextStyle(color: AppTheme.textMain, fontSize: 12)),
        subtitle: Text(subtitle, style: const TextStyle(color: AppTheme.textMuted, fontSize: 10)),
        trailing: const Icon(Icons.add_circle_outline, color: AppTheme.accent, size: 20),
        onTap: () {},
      ),
    );
  }

  Widget _buildFilterTile(String name, int type, EditorController ctrl) {
    bool selected = ctrl.activeFilterType == type;
    return Card(
      color: selected ? AppTheme.primary.withOpacity(0.3) : AppTheme.card,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: selected ? AppTheme.accent : AppTheme.divider),
      ),
      child: ListTile(
        leading: Icon(Icons.color_lens, color: selected ? AppTheme.accent : AppTheme.textMuted),
        title: Text(name, style: const TextStyle(color: AppTheme.textMain, fontSize: 12)),
        trailing: selected
            ? const Icon(Icons.check_circle, color: AppTheme.accent, size: 20)
            : const Icon(Icons.play_arrow, color: AppTheme.textMuted, size: 18),
        onTap: () => ctrl.setFilter(type, 1.0),
      ),
    );
  }
}
