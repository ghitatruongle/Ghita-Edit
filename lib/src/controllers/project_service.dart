import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/project.dart';

/// Manages project file save/load operations.
class ProjectService {
  static const String projectExtension = '.ghita';
  static const String autoSaveDir = '.ghita_autosave';

  String? _lastSavePath;
  String? get lastSavePath => _lastSavePath;

  /// Save project to a specific file path.
  Future<bool> saveProject(Project project, String filePath) async {
    final ok = await _writeFile(project, filePath);
    if (ok) {
      project.filePath = filePath;
      _lastSavePath = filePath;
      debugPrint('[ProjectService] Saved project to: $filePath');
    }
    return ok;
  }

  /// v0.7.8: Low-level atomic write — no path bookkeeping, so autosave can
  /// never repoint project.filePath/_lastSavePath at an autosave file.
  /// Writes to a temp file first and renames, so a crash mid-write cannot
  /// corrupt the project file.
  Future<bool> _writeFile(Project project, String filePath) async {
    try {
      final file = File(filePath);
      final dir = file.parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final jsonStr = project.toJsonString();
      final tmpFile = File('$filePath.tmp');
      await tmpFile.writeAsString(jsonStr, flush: true);
      if (await file.exists()) {
        await file.delete();
      }
      await tmpFile.rename(filePath);
      return true;
    } catch (e) {
      debugPrint('[ProjectService] Write failed: $e');
      return false;
    }
  }

  /// Load project from a file path.
  Future<Project?> loadProject(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('[ProjectService] File not found: $filePath');
        return null;
      }

      final jsonStr = await file.readAsString();
      final project = Project.fromJsonString(jsonStr);
      project.filePath = filePath;
      _lastSavePath = filePath;

      debugPrint('[ProjectService] Loaded project: ${project.name} from $filePath');
      return project;
    } catch (e) {
      debugPrint('[ProjectService] Load failed: $e');
      return null;
    }
  }

  /// Quick-save to the last known path (or return false if no path set).
  Future<bool> quickSave(Project project) async {
    final path = _lastSavePath ?? project.filePath;
    if (path.isEmpty) return false;
    return saveProject(project, path);
  }

  /// Auto-save project to a temporary location.
  Future<bool> autoSave(Project project, String workingDir) async {
    try {
      final dir = Directory('$workingDir/$autoSaveDir');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${dir.path}/autosave_$timestamp$projectExtension';

      // Keep only the last 5 autosaves
      await _cleanOldAutoSaves(dir);

      // v0.7.8: Write through _writeFile, NOT saveProject — saveProject would
      // repoint project.filePath/_lastSavePath at this autosave, making the
      // next Ctrl+S overwrite an autosave instead of the user's project.
      final ok = await _writeFile(project, filePath);
      debugPrint('[ProjectService] Auto-saved to: $filePath');
      return ok;
    } catch (e) {
      debugPrint('[ProjectService] Auto-save failed: $e');
      return false;
    }
  }

  /// Get the most recent auto-save file.
  Future<String?> getLatestAutoSave(String workingDir) async {
    try {
      final dir = Directory('$workingDir/$autoSaveDir');
      if (!await dir.exists()) return null;

      final files = await dir
          .list()
          .where((f) => f is File && f.path.endsWith(projectExtension))
          .cast<File>()
          .toList();

      if (files.isEmpty) return null;

      files.sort((a, b) => b.path.compareTo(a.path));
      return files.first.path;
    } catch (_) {
      return null;
    }
  }

  /// List recent project files from a directory.
  Future<List<String>> listRecentProjects(String projectsDir) async {
    try {
      final dir = Directory(projectsDir);
      if (!await dir.exists()) return [];

      final files = await dir
          .list(recursive: true)
          .where((f) => f is File && f.path.endsWith(projectExtension))
          .cast<File>()
          .toList();

      // Sort by modification date (newest first)
      final withStats = <MapEntry<String, DateTime>>[];
      for (final file in files) {
        final stat = await file.stat();
        withStats.add(MapEntry(file.path, stat.modified));
      }
      withStats.sort((a, b) => b.value.compareTo(a.value));

      return withStats.take(10).map((e) => e.key).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _cleanOldAutoSaves(Directory dir) async {
    try {
      final files = await dir
          .list()
          .where((f) => f is File && f.path.endsWith(projectExtension))
          .cast<File>()
          .toList();

      if (files.length <= 5) return;

      files.sort((a, b) => a.path.compareTo(b.path));
      final toDelete = files.sublist(0, files.length - 5);
      for (final file in toDelete) {
        await file.delete();
      }
    } catch (_) {}
  }

  /// Export project metadata as a summary string.
  String getProjectSummary(Project project) {
    final clipCount = project.allClips.length;
    final trackCount = project.tracks.length;
    final duration = _formatDuration(project.totalDurationMs);
    return '$trackCount tracks, $clipCount clips, $duration total';
  }

  String _formatDuration(int ms) {
    final seconds = ms ~/ 1000;
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes}m ${secs}s';
  }
}
