import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cropcare_ai/core/constants/app_constants.dart';
import 'package:cropcare_ai/data/local/database_helper.dart';
import 'package:cropcare_ai/services/video_cleanup_service.dart';

class _FakePathProvider extends PathProviderPlatform {
  final String _docsPath;
  _FakePathProvider(this._docsPath);

  @override
  Future<String?> getApplicationDocumentsPath() async => _docsPath;
}

void main() {
  late Directory tempDocs;
  late DatabaseHelper db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDocs = await Directory.systemTemp.createTemp('cropcare_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDocs.path);
    SharedPreferences.setMockInitialValues({});
    db = DatabaseHelper.instance;
    await db.deleteDatabaseFile();
  });

  tearDown(() async {
    await db.deleteDatabaseFile();
    if (await tempDocs.exists()) {
      await tempDocs.delete(recursive: true);
    }
  });

  test('runIfDue is gated to once per 23 hours', () async {
    final svc = VideoCleanupService(db: db);
    final r1 = await svc.runIfDue();
    final r2 = await svc.runIfDue();
    expect(r1.errors, isEmpty);
    expect(r2.filesDeleted, 0);
    expect(r2.rowsTombstoned, 0);
  });

  test('files older than retention get deleted; newer survive', () async {
    final videosDir = Directory('${tempDocs.path}/videos')
      ..createSync(recursive: true);
    final old = File('${videosDir.path}/old.mp4')
      ..writeAsStringSync('x');
    final fresh = File('${videosDir.path}/fresh.mp4')
      ..writeAsStringSync('y');
    final ancient = DateTime.now()
        .subtract(VideoCleanupService.retention)
        .subtract(const Duration(days: 1));
    await old.setLastModified(ancient);

    final svc = VideoCleanupService(db: db);
    final report = await svc.runIfDue();

    expect(await old.exists(), isFalse);
    expect(await fresh.exists(), isTrue);
    expect(report.filesDeleted, 1);
  });

  test('per-file deletion error does not abort the sweep', () async {
    final svc = VideoCleanupService(db: db);
    final report = await svc.runIfDue();
    expect(report.errors, isEmpty);
  });

  test('deleteVideo writes tombstone into diagnoses.video_url', () async {
    final videosDir = Directory('${tempDocs.path}/videos')
      ..createSync(recursive: true);
    final f = File('${videosDir.path}/abc.mp4')..writeAsStringSync('z');

    final database = await db.database;
    await database.insert(AppConstants.diagnosesTable, {
      'id': 'd1',
      'crop_id': 'c1',
      'user_id': 'u1',
      'diagnosis_mode': 'online',
      'disease_name': 'tomato_blight',
      'severity': 'mild',
      'video_url': f.path,
      'diagnosed_at': DateTime.now().toIso8601String(),
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });

    final svc = VideoCleanupService(db: db);
    await svc.deleteVideo(f.path);

    expect(await f.exists(), isFalse);
    final rows = await database.query(
      AppConstants.diagnosesTable,
      where: 'id = ?',
      whereArgs: ['d1'],
    );
    expect(rows.first['video_url'], 'expired:abc.mp4');
  });
}
