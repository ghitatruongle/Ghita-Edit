import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import '../ffi/native_bindings.dart';
import '../models/project.dart';

/// Manages project file save/load operations.
/// v1.5.0 T5-P1: Dual-backend — saves to both JSON (.ghita) and SQLite
/// (.ghita.db) when the sqlite feature is available in the engine DLL.
/// Loads prefer SQLite (faster, indexed), falls back to JSON for old projects.
/// Auto-migrates JSON→SQLite on first load of a legacy project.
class ProjectService {
  static const String projectExtension = '.ghita';
  static const String autoSaveDir = '.ghita_autosave';
  static const String dbExtension = '.ghita.db';

  String? _lastSavePath;
  String? get lastSavePath => _lastSavePath;

  /// Whether the engine DLL exports the SQLite project database symbols.
  bool get _sqliteAvailable {
    try {
      return GhitaNativeBindings.instance.projectDbSave != null;
    } catch (_) {
      return false;
    }
  }

  /// Derive the SQLite database path from a .ghita JSON path.
  String _dbPathFor(String jsonPath) => '$jsonPath$dbExtension';

  /// Save project to a specific file path.
  /// v1.5.0 T5-P1: Dual-write — always writes JSON for backward compat,
  /// plus SQLite when available for indexed/fast access.
  Future<bool> saveProject(Project project, String filePath) async {
    final ok = await _writeFile(project, filePath);
    if (ok) {
      project.filePath = filePath;
      _lastSavePath = filePath;
      debugPrint('[ProjectService] Saved project to: $filePath');
      // Dual-write to SQLite when available.
      _sqliteSave(filePath, project);
    }
    return ok;
  }

  /// Write project JSON to the SQLite database (best-effort, non-blocking).
  void _sqliteSave(String jsonPath, Project project) {
    if (!_sqliteAvailable) return;
    try {
      final b = GhitaNativeBindings.instance;
      final dbPath = _dbPathFor(jsonPath);
      final dbName = project.name.isNotEmpty ? project.name : 'untitled';
      final jsonStr = project.toJsonString();
      final dbPtr = dbPath.toNativeUtf8();
      final namePtr = dbName.toNativeUtf8();
      final jsonPtr = jsonStr.toNativeUtf8();
      try {
        final ret = b.projectDbSave!(dbPtr, namePtr, jsonPtr);
        if (ret == 0) {
          debugPrint('[ProjectService] SQLite save OK: $dbPath');
        } else {
          debugPrint('[ProjectService] SQLite save failed (code $ret)');
        }
      } finally {
        calloc.free(dbPtr);
        calloc.free(namePtr);
        calloc.free(jsonPtr);
      }
    } catch (e) {
      debugPrint('[ProjectService] SQLite save error: $e');
    }
  }

  /// v0.7.8: Low-level atomic write — no path bookkeeping, so autosave can
  /// never repoint project.filePath/_lastSavePath at an autosave file.
  /// Writes to a temp file first and renames, so a crash mid-write cannot
  /// corrupt the project file.
  /// v0.7.9: True atomic replace — try rename first (POSIX overwrites the
  /// destination), and only delete-then-rename on Windows where rename fails
  /// when the target exists. On failure the temp file is cleaned up so a
  /// failed save cannot leave junk behind.
  Future<bool> _writeFile(Project project, String filePath) async {
    final tmpFile = File('$filePath.tmp');
    try {
      final file = File(filePath);
      final dir = file.parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final jsonStr = project.toJsonString();
      await tmpFile.writeAsString(jsonStr, flush: true);

      try {
        await tmpFile.rename(filePath);
      } catch (_) {
        // Windows: rename fails when the destination exists — remove it
        // first, then retry. The data was already flushed to the temp file,
        // so this still cannot corrupt the destination on crash.
        if (await file.exists()) {
          await file.delete();
        }
        await tmpFile.rename(filePath);
      }
      return true;
    } catch (e) {
      debugPrint('[ProjectService] Write failed: $e');
      // v0.7.9: Never leave a stray .tmp file behind on failure.
      try {
        if (await tmpFile.exists()) {
          await tmpFile.delete();
        }
      } catch (_) {}
      return false;
    }
  }

  /// Load project from a file path.
  /// v1.5.0 T5-P1: Try SQLite first (faster), fall back to JSON.
  /// On JSON load, auto-migrate to SQLite for next time.
  Future<Project?> loadProject(String filePath) async {
    // Try SQLite backend first.
    if (_sqliteAvailable) {
      final dbFile = File(_dbPathFor(filePath));
      if (await dbFile.exists()) {
        final project = _sqliteLoad(filePath);
        if (project != null) {
          project.filePath = filePath;
          _lastSavePath = filePath;
          debugPrint('[ProjectService] Loaded project from SQLite: ${project.name}');
          return project;
        }
      }
    }

    // Fall back to JSON.
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

      // Auto-migrate JSON → SQLite on first load.
      _sqliteSave(filePath, project);

      return project;
    } catch (e) {
      debugPrint('[ProjectService] Load failed: $e');
      return null;
    }
  }

  /// Load project from SQLite database (returns null on any failure).
  Project? _sqliteLoad(String jsonPath) {
    try {
      final b = GhitaNativeBindings.instance;
      final fn = b.projectDbLoad;
      if (fn == null) return null;
      final dbPath = _dbPathFor(jsonPath);
      final dbPtr = dbPath.toNativeUtf8();
      // Use the filename without extension as the project name key.
      final name = jsonPath.split(RegExp(r'[/\\]')).last.replaceAll('.ghita', '');
      final namePtr = name.toNativeUtf8();
      try {
        final resultPtr = fn(dbPtr, namePtr);
        if (resultPtr == nullptr) return null;
        final jsonStr = resultPtr.toDartString();
        if (jsonStr.isEmpty) return null;
        return Project.fromJsonString(jsonStr);
      } finally {
        calloc.free(dbPtr);
        calloc.free(namePtr);
      }
    } catch (e) {
      debugPrint('[ProjectService] SQLite load error: $e');
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

  // ========== v1.5.0 T5-P2: Auto-Recovery ==========

  static const String recoveryExtension = '.ghita_recovery';

  /// Write a recovery file alongside the project (atomic, same pattern as
  /// autosave). Called on every save so a crash mid-edit can be recovered.
  Future<bool> writeRecoveryFile(Project project, String filePath) async {
    try {
      final recoveryPath = '$filePath$recoveryExtension';
      final ok = await _writeFile(project, recoveryPath);
      if (ok) {
        debugPrint('[ProjectService] Recovery file written: $recoveryPath');
      }
      return ok;
    } catch (e) {
      debugPrint('[ProjectService] Recovery write failed: $e');
      return false;
    }
  }

  /// Check whether a recovery file exists and is newer than the main project.
  /// Returns the recovery path if recovery should be offered, null otherwise.
  Future<String?> checkRecovery(String filePath) async {
    try {
      final recoveryPath = '$filePath$recoveryExtension';
      final recoveryFile = File(recoveryPath);
      if (!await recoveryFile.exists()) return null;

      final mainFile = File(filePath);
      if (!await mainFile.exists()) {
        return recoveryPath;
      }

      final recoveryStat = await recoveryFile.stat();
      final mainStat = await mainFile.stat();
      if (recoveryStat.modified.isAfter(mainStat.modified)) {
        return recoveryPath;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Load a project from a recovery file.
  Future<Project?> loadRecovery(String recoveryPath) async {
    try {
      final file = File(recoveryPath);
      if (!await file.exists()) return null;
      final jsonStr = await file.readAsString();
      final project = Project.fromJsonString(jsonStr);
      debugPrint('[ProjectService] Loaded recovery from: $recoveryPath');
      return project;
    } catch (e) {
      debugPrint('[ProjectService] Recovery load failed: $e');
      return null;
    }
  }

  /// Delete the recovery file after a successful save or when the user
  /// declines recovery.
  Future<void> clearRecovery(String filePath) async {
    try {
      final recoveryPath = '$filePath$recoveryExtension';
      final file = File(recoveryPath);
      if (await file.exists()) {
        await file.delete();
        debugPrint('[ProjectService] Recovery file cleared: $recoveryPath');
      }
    } catch (_) {}
  }
}
