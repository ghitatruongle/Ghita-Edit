import 'dart:convert';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import '../../controllers/editor_controller.dart';
import '../../ffi/native_bindings.dart';
import '../theme/app_theme.dart';

/// v1.5.0 T5-P3: DAM Light Table panel — grid view of media library entries
/// with search, rating, and tag management via SQLite backend.
class LightTablePanel extends StatefulWidget {
  final EditorController controller;
  const LightTablePanel({super.key, required this.controller});

  @override
  State<LightTablePanel> createState() => _LightTablePanelState();
}

class _LightTablePanelState extends State<LightTablePanel> {
  String _searchQuery = '';
  List<_MediaItem> _items = [];
  bool _loading = false;
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _tagCtrl = TextEditingController();
  int? _selectedId;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _tagCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _doSearch('');
  }

  void _doSearch(String query) {
    setState(() => _loading = true);
    Future.microtask(() {
      final results = _searchLibrary(query);
      if (mounted) {
        setState(() {
          _items = results;
          _loading = false;
          _searchQuery = query;
        });
      }
    });
  }

  List<_MediaItem> _searchLibrary(String query) {
    try {
      final fn = GhitaNativeBindings.instance.projectDbLibrarySearch;
      if (fn == null) return [];
      // Use project filePath to derive db path.
      final projPath = widget.controller.project.filePath;
      if (projPath.isEmpty) return [];
      final dbPath = '$projPath.ghita.db';
      final dbPtr = dbPath.toNativeUtf8();
      final qPtr = query.toNativeUtf8();
      try {
        final resultPtr = fn(dbPtr, qPtr);
        if (resultPtr == nullptr) return [];
        final jsonStr = resultPtr.toDartString();
        if (jsonStr.isEmpty) return [];
        final decoded = jsonDecode(jsonStr);
        if (decoded is! List) return [];
        return decoded.map((e) {
          final m = e as Map<String, dynamic>;
          return _MediaItem(
            id: (m['id'] as num?)?.toInt() ?? 0,
            path: m['path'] as String? ?? '',
            tags: m['tags'] as String? ?? '',
            rating: (m['rating'] as num?)?.toInt() ?? 0,
          );
        }).toList();
      } finally {
        calloc.free(dbPtr);
        calloc.free(qPtr);
      }
    } catch (_) {
      return [];
    }
  }

  void _updateRating(int id, int rating) {
    try {
      final fn = GhitaNativeBindings.instance.projectDbLibraryUpdateRating;
      if (fn == null) return;
      final projPath = widget.controller.project.filePath;
      if (projPath.isEmpty) return;
      final dbPath = '$projPath.ghita.db';
      final dbPtr = dbPath.toNativeUtf8();
      try {
        fn(dbPtr, id, rating);
        _doSearch(_searchQuery);
      } finally {
        calloc.free(dbPtr);
      }
    } catch (_) {}
  }

  void _addTag(int id, String tag) {
    if (tag.trim().isEmpty) return;
    try {
      final fn = GhitaNativeBindings.instance.projectDbLibraryUpdateTags;
      if (fn == null) return;
      final projPath = widget.controller.project.filePath;
      if (projPath.isEmpty) return;
      final dbPath = '$projPath.ghita.db';
      final item = _items.where((i) => i.id == id).firstOrNull;
      final existingTags = item?.tags ?? '';
      final newTags = existingTags.isEmpty ? tag : '$existingTags,$tag';
      final dbPtr = dbPath.toNativeUtf8();
      final tagsPtr = newTags.toNativeUtf8();
      try {
        fn(dbPtr, id, tagsPtr);
        _tagCtrl.clear();
        _doSearch(_searchQuery);
      } finally {
        calloc.free(dbPtr);
        calloc.free(tagsPtr);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.background,
      child: Column(
        children: [
          // Header + Search
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: AppTheme.surface,
              border: Border(bottom: BorderSide(color: AppTheme.divider)),
            ),
            child: Row(
              children: [
                const Icon(Icons.grid_view, color: AppTheme.primaryLight, size: 20),
                const SizedBox(width: 8),
                const Text('LIGHT TABLE',
                    style: TextStyle(color: AppTheme.textMain, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.0)),
                const Spacer(),
                SizedBox(
                  width: 300,
                  height: 32,
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(color: AppTheme.textMain, fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Search media...',
                      hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                      prefixIcon: const Icon(Icons.search, size: 16, color: AppTheme.textMuted),
                      filled: true,
                      fillColor: AppTheme.card,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      isDense: true,
                    ),
                    onSubmitted: (v) => _doSearch(v),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => _doSearch(_searchCtrl.text),
                  icon: const Icon(Icons.search, size: 18, color: AppTheme.primaryLight),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
          ),

          // Grid
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.photo_library_outlined, color: AppTheme.textMuted, size: 48),
                            const SizedBox(height: 12),
                            Text(_searchQuery.isEmpty ? 'No media in library' : 'No results for "$_searchQuery"',
                                style: const TextStyle(color: AppTheme.textMain, fontSize: 13)),
                          ],
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 0.85,
                        ),
                        itemCount: _items.length,
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          final isSelected = _selectedId == item.id;
                          return GestureDetector(
                            onTap: () => setState(() => _selectedId = item.id),
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppTheme.card,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: isSelected ? AppTheme.primary : AppTheme.divider),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Thumbnail placeholder
                                  Expanded(
                                    child: Container(
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF1A1D2E),
                                        borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
                                      ),
                                      child: const Center(
                                        child: Icon(Icons.image, color: AppTheme.textMuted, size: 36),
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(6),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.path.split(RegExp(r'[/\\]')).last,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: AppTheme.textMain, fontSize: 10, fontWeight: FontWeight.w600),
                                        ),
                                        const SizedBox(height: 2),
                                        // Rating stars
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: List.generate(5, (i) {
                                            return GestureDetector(
                                              onTap: () => _updateRating(item.id, i + 1),
                                              child: Icon(
                                                i < item.rating ? Icons.star : Icons.star_border,
                                                size: 14,
                                                color: i < item.rating ? Colors.amber : AppTheme.textMuted,
                                              ),
                                            );
                                          }),
                                        ),
                                        const SizedBox(height: 2),
                                        // Tags
                                        if (item.tags.isNotEmpty)
                                          Wrap(
                                            spacing: 2,
                                            runSpacing: 1,
                                            children: item.tags.split(',').take(3).map((t) {
                                              return Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.primary.withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(3),
                                                ),
                                                child: Text(t.trim(),
                                                    style: const TextStyle(color: AppTheme.primaryLight, fontSize: 8)),
                                              );
                                            }).toList(),
                                          ),
                                        // Add tag (only for selected)
                                        if (isSelected)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: SizedBox(
                                                    height: 22,
                                                    child: TextField(
                                                      controller: _tagCtrl,
                                                      style: const TextStyle(color: AppTheme.textMain, fontSize: 9),
                                                      decoration: InputDecoration(
                                                        hintText: '+ tag',
                                                        hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 9),
                                                        filled: true,
                                                        fillColor: AppTheme.surface,
                                                        border: OutlineInputBorder(
                                                            borderRadius: BorderRadius.circular(3), borderSide: BorderSide.none),
                                                        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                                        isDense: true,
                                                      ),
                                                      onSubmitted: (v) => _addTag(item.id, v),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 2),
                                                GestureDetector(
                                                  onTap: () => _addTag(item.id, _tagCtrl.text),
                                                  child: const Icon(Icons.add_circle, size: 16, color: AppTheme.primary),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
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
    );
  }
}

class _MediaItem {
  final int id;
  final String path;
  final String tags;
  final int rating;
  _MediaItem({required this.id, required this.path, required this.tags, required this.rating});
}

