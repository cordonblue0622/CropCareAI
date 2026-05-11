import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_constants.dart';
import '../data/local/database_helper.dart';

class VideoCleanupReport {
  final int filesDeleted;
  final int rowsTombstoned;
  final List<String> errors;

  const VideoCleanupReport({
    required this.filesDeleted,
    required this.rowsTombstoned,
    required this.errors,
  });

  bool get hasWork => filesDeleted > 0 || rowsTombstoned > 0;
}

/// Manages on-disk video file lifecycle:
///   - Auto-expire after [retention] (run once per 23h on app start).
///   - Manual delete via [deleteVideo].
///
/// In both cases, the file is removed and any DB row whose `video_url`
/// matches the deleted path is rewritten to `expired:<basename>` so the UI
/// can render the "Video expired" badge.
class VideoCleanupService {
  VideoCleanupService({required this.db});

  final DatabaseHelper db;

  static const Duration retention = Duration(days: 30);
  static const Duration _gate = Duration(hours: 23);
  static const String _lastRunKey = 'video_cleanup_last_run_iso8601';

  Future<VideoCleanupReport> runIfDue() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastRunKey);
    final lastRun = raw == null ? null : DateTime.tryParse(raw);
    if (lastRun != null && DateTime.now().difference(lastRun) < _gate) {
      return const VideoCleanupReport(
          filesDeleted: 0, rowsTombstoned: 0, errors: []);
    }

    final report = await _sweep();
    await prefs.setString(_lastRunKey, DateTime.now().toIso8601String());
    return report;
  }

  Future<void> deleteVideo(String filePath) async {
    final file = File(filePath);
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('VideoCleanupService.deleteVideo: $e');
    }
    await _tombstoneRows(filePath);
  }

  Future<VideoCleanupReport> _sweep() async {
    final errors = <String>[];
    int filesDeleted = 0;
    int rowsTombstoned = 0;

    Directory? videosDir;
    try {
      final docs = await getApplicationDocumentsDirectory();
      videosDir = Directory(p.join(docs.path, 'videos'));
      if (!await videosDir.exists()) {
        return VideoCleanupReport(
            filesDeleted: 0, rowsTombstoned: 0, errors: errors);
      }
    } catch (e) {
      return VideoCleanupReport(
          filesDeleted: 0, rowsTombstoned: 0, errors: ['$e']);
    }

    final cutoff = DateTime.now().subtract(retention);

    await for (final entity in videosDir.list()) {
      if (entity is! File) continue;
      try {
        final stat = await entity.stat();
        if (stat.modified.isAfter(cutoff)) continue;
        final path = entity.path;
        await entity.delete();
        filesDeleted++;
        rowsTombstoned += await _tombstoneRows(path);
      } catch (e) {
        errors.add('${entity.path}: $e');
      }
    }

    return VideoCleanupReport(
      filesDeleted: filesDeleted,
      rowsTombstoned: rowsTombstoned,
      errors: errors,
    );
  }

  Future<int> _tombstoneRows(String filePath) async {
    final basename = p.basename(filePath);
    final tombstone = 'expired:$basename';
    final database = await db.database;
    int total = 0;

    total += await database.update(
      AppConstants.diagnosesTable,
      {'video_url': tombstone},
      where: 'video_url = ?',
      whereArgs: [filePath],
    );

    total += await database.update(
      AppConstants.progressUpdatesTable,
      {'video_url': tombstone},
      where: 'video_url = ?',
      whereArgs: [filePath],
    );

    final chatRows = await database.query(
      AppConstants.chatMessagesTable,
      columns: ['id', 'metadata'],
    );
    for (final row in chatRows) {
      final raw = row['metadata'] as String?;
      if (raw == null || raw.isEmpty) continue;
      Map<String, dynamic> meta;
      try {
        meta = (jsonDecode(raw) as Map).cast<String, dynamic>();
      } catch (_) {
        continue;
      }
      if (meta['video_url'] == filePath) {
        meta['video_url'] = tombstone;
        await database.update(
          AppConstants.chatMessagesTable,
          {'metadata': jsonEncode(meta)},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
        total++;
      }
    }

    return total;
  }
}
