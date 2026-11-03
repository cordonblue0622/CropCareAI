import 'package:cropcare_ai/core/constants/app_constants.dart';
import 'package:cropcare_ai/data/local/database_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DatabaseHelper helper;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    helper = DatabaseHelper.instance;
    await helper.deleteDatabaseFile();
  });

  tearDown(() => helper.deleteDatabaseFile());

  test('v3 records and relationships survive the v7 additive upgrade',
      () async {
    final path = join(await getDatabasesPath(), AppConstants.dbName);
    final oldDatabase = await openDatabase(
      path,
      version: 3,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE diagnoses (
            id TEXT PRIMARY KEY,
            crop_id TEXT NOT NULL,
            disease_name TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE users (
            id TEXT PRIMARY KEY,
            email TEXT UNIQUE NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE progress_updates (
            id TEXT PRIMARY KEY,
            crop_id TEXT NOT NULL,
            progress_status TEXT NOT NULL,
            image_url TEXT
          )
        ''');
        await db.insert('diagnoses', {
          'id': 'diagnosis-v3',
          'crop_id': 'crop-v3',
          'disease_name': 'Tomato Early Blight',
          'created_at': '2026-11-01T08:00:00.000Z',
        });
        await db.insert('users', {
          'id': 'user-v3',
          'email': 'offline@example.invalid',
        });
        await db.insert('progress_updates', {
          'id': 'progress-v3',
          'crop_id': 'crop-v3',
          'progress_status': 'insufficient_data',
          'image_url': 'data:image/jpeg;base64,AQID',
        });
      },
    );
    await oldDatabase.close();

    final upgraded = await helper.database;

    expect(await upgraded.getVersion(), AppConstants.dbVersion);
    final diagnosisColumns =
        await upgraded.rawQuery('PRAGMA table_info(diagnoses)');
    expect(
      diagnosisColumns.map((row) => row['name']),
      contains('chat_session_id'),
    );
    final progressColumns =
        await upgraded.rawQuery('PRAGMA table_info(progress_updates)');
    expect(
      progressColumns.map((row) => row['name']),
      containsAll([
        'ai_analysis_status',
        'ai_analysis_error',
        'ai_analysis_started_at',
      ]),
    );
    final diagnosis = await upgraded.query('diagnoses');
    expect(diagnosis.single['id'], 'diagnosis-v3');
    expect(diagnosis.single['crop_id'], 'crop-v3');
    expect(diagnosis.single['disease_name'], 'Tomato Early Blight');
    final progress = await upgraded.query('progress_updates');
    expect(progress.single['ai_analysis_status'], 'pending');
    expect(progress.single['image_url'], 'data:image/jpeg;base64,AQID');
    expect((await upgraded.query('users')).single['role'], 'farmer');
  });
}
