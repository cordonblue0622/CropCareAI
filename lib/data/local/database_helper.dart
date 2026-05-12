import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../../core/constants/app_constants.dart';

/// Singleton wrapper around the SQLite database.
/// Handles local caching of user profiles and the offline sync queue.
class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  Database? _database;

  bool get _isDisabledOnPlatform => kIsWeb;

  Future<Database> get database async {
    if (_isDisabledOnPlatform) {
      throw UnsupportedError('SQLite is disabled on web.');
    }
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, AppConstants.dbName);
    return openDatabase(
      path,
      version: AppConstants.dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createAllTables(db);
  }

  Future<void> _createAllTables(Database db) async {
    // Users – local cache of Supabase 'profiles' table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${AppConstants.usersTable} (
        id                 TEXT PRIMARY KEY,
        full_name          TEXT,
        display_name       TEXT,
        email              TEXT UNIQUE NOT NULL,
        phone              TEXT,
        avatar_url         TEXT,
        barangay           TEXT,
        municipality       TEXT,
        province           TEXT,
        country            TEXT,
        preferred_language TEXT DEFAULT 'en',
        provider           TEXT DEFAULT 'email',
        created_at         TEXT,
        updated_at         TEXT
      )
    ''');

    // Sync queue
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${AppConstants.syncQueueTable} (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name   TEXT    NOT NULL,
        record_id    TEXT    NOT NULL,
        operation    TEXT    NOT NULL,
        payload      TEXT    NOT NULL,
        created_at   TEXT    NOT NULL,
        attempts     INTEGER DEFAULT 0,
        last_error   TEXT
      )
    ''');

    // Crops
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${AppConstants.cropsTable} (
        id                      TEXT PRIMARY KEY,
        user_id                 TEXT NOT NULL,
        crop_type               TEXT NOT NULL,
        crop_name               TEXT NOT NULL,
        plot_code               TEXT,
        location_label          TEXT,
        notes                   TEXT,
        status                  TEXT NOT NULL DEFAULT 'monitoring',
        planted_at              TEXT,
        last_checked_at         TEXT,
        latest_progress_status  TEXT,
        latest_health_score     REAL,
        sync_version            INTEGER NOT NULL DEFAULT 1,
        is_deleted              INTEGER NOT NULL DEFAULT 0,
        created_at              TEXT NOT NULL,
        updated_at              TEXT NOT NULL
      )
    ''');

    // Diagnoses
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${AppConstants.diagnosesTable} (
        id                    TEXT PRIMARY KEY,
        crop_id               TEXT NOT NULL,
        user_id               TEXT NOT NULL,
        diagnosis_mode        TEXT NOT NULL,
        label_key             TEXT,
        disease_name          TEXT NOT NULL,
        confidence_score      REAL,
        severity              TEXT NOT NULL DEFAULT 'mild',
        result_label          TEXT,
        summary               TEXT,
        image_url             TEXT,
        video_url             TEXT,
        detected_regions_json TEXT,
        model_name            TEXT,
        model_version         TEXT,
        diagnosed_at          TEXT NOT NULL,
        sync_version          INTEGER NOT NULL DEFAULT 1,
        is_deleted            INTEGER NOT NULL DEFAULT 0,
        created_at            TEXT NOT NULL,
        updated_at            TEXT NOT NULL
      )
    ''');

    // Treatments
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${AppConstants.treatmentsTable} (
        id                      TEXT PRIMARY KEY,
        crop_id                 TEXT NOT NULL,
        diagnosis_id            TEXT,
        user_id                 TEXT NOT NULL,
        disease_name            TEXT NOT NULL,
        treatment_title         TEXT NOT NULL,
        treatment_steps         TEXT NOT NULL,
        expected_duration_days  INTEGER,
        status                  TEXT NOT NULL DEFAULT 'planned',
        started_at              TEXT,
        ended_at                TEXT,
        reassessment_required   INTEGER NOT NULL DEFAULT 0,
        notes                   TEXT,
        source                  TEXT DEFAULT 'knowledge_base',
        sync_version            INTEGER NOT NULL DEFAULT 1,
        is_deleted              INTEGER NOT NULL DEFAULT 0,
        created_at              TEXT NOT NULL,
        updated_at              TEXT NOT NULL
      )
    ''');

    // Treatment Tasks
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${AppConstants.treatmentTasksTable} (
        id            TEXT PRIMARY KEY,
        treatment_id  TEXT NOT NULL,
        crop_id       TEXT NOT NULL,
        user_id       TEXT NOT NULL,
        title         TEXT NOT NULL,
        description   TEXT,
        due_at        TEXT NOT NULL,
        completed_at  TEXT,
        status        TEXT NOT NULL DEFAULT 'pending',
        task_order    INTEGER,
        sync_version  INTEGER NOT NULL DEFAULT 1,
        is_deleted    INTEGER NOT NULL DEFAULT 0,
        created_at    TEXT NOT NULL,
        updated_at    TEXT NOT NULL
      )
    ''');

    // Progress Updates
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${AppConstants.progressUpdatesTable} (
        id                    TEXT PRIMARY KEY,
        crop_id               TEXT NOT NULL,
        treatment_id          TEXT,
        diagnosis_id          TEXT,
        user_id               TEXT NOT NULL,
        update_source         TEXT NOT NULL DEFAULT 'manual',
        note                  TEXT,
        image_url             TEXT,
        video_url             TEXT,
        observed_symptoms     TEXT,
        detected_disease_name TEXT,
        detected_severity     TEXT,
        progress_status       TEXT NOT NULL DEFAULT 'insufficient_data',
        health_score          REAL,
        completed_task_count  INTEGER DEFAULT 0,
        missed_task_count     INTEGER DEFAULT 0,
        update_date           TEXT NOT NULL,
        sync_version          INTEGER NOT NULL DEFAULT 1,
        is_deleted            INTEGER NOT NULL DEFAULT 0,
        created_at            TEXT NOT NULL,
        updated_at            TEXT NOT NULL
      )
    ''');

    // Chat Sessions
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${AppConstants.chatSessionsTable} (
        id                  TEXT PRIMARY KEY,
        user_id             TEXT NOT NULL,
        crop_id             TEXT,
        title               TEXT,
        is_offline_session  INTEGER NOT NULL DEFAULT 0,
        last_message_at     TEXT,
        sync_version        INTEGER NOT NULL DEFAULT 1,
        is_deleted          INTEGER NOT NULL DEFAULT 0,
        created_at          TEXT NOT NULL,
        updated_at          TEXT NOT NULL
      )
    ''');

    // Chat Messages
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${AppConstants.chatMessagesTable} (
        id          TEXT PRIMARY KEY,
        session_id  TEXT NOT NULL,
        user_id     TEXT NOT NULL,
        role        TEXT NOT NULL,
        content     TEXT NOT NULL,
        metadata    TEXT,
        created_at  TEXT NOT NULL
      )
    ''');

    // Notifications
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${AppConstants.notificationsTable} (
        id             TEXT PRIMARY KEY,
        user_id        TEXT NOT NULL,
        crop_id        TEXT,
        treatment_id   TEXT,
        type           TEXT NOT NULL,
        title          TEXT NOT NULL,
        body           TEXT NOT NULL,
        scheduled_for  TEXT,
        is_read        INTEGER NOT NULL DEFAULT 0,
        is_sent        INTEGER NOT NULL DEFAULT 0,
        created_at     TEXT NOT NULL
      )
    ''');

    // Disease Knowledge Base (local cache)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${AppConstants.diseaseKnowledgeTable} (
        id                      TEXT PRIMARY KEY,
        crop_type               TEXT NOT NULL,
        label_key               TEXT,
        disease_name            TEXT NOT NULL,
        scientific_name         TEXT,
        description             TEXT,
        symptoms                TEXT,
        causes                  TEXT,
        treatment_steps         TEXT,
        prevention_steps        TEXT,
        estimated_recovery_days INTEGER,
        severity_notes          TEXT,
        caution_notes           TEXT,
        is_active               INTEGER NOT NULL DEFAULT 1,
        source_name             TEXT,
        source_url              TEXT,
        created_at              TEXT NOT NULL,
        updated_at              TEXT NOT NULL
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add new profile columns to existing users table
      await db.execute(
          'ALTER TABLE ${AppConstants.usersTable} ADD COLUMN display_name TEXT');
      await db.execute(
          'ALTER TABLE ${AppConstants.usersTable} ADD COLUMN phone TEXT');
      await db.execute(
          'ALTER TABLE ${AppConstants.usersTable} ADD COLUMN barangay TEXT');
      await db.execute(
          'ALTER TABLE ${AppConstants.usersTable} ADD COLUMN municipality TEXT');
      await db.execute(
          'ALTER TABLE ${AppConstants.usersTable} ADD COLUMN province TEXT');
      await db.execute(
          'ALTER TABLE ${AppConstants.usersTable} ADD COLUMN country TEXT');
      await db.execute(
          "ALTER TABLE ${AppConstants.usersTable} ADD COLUMN preferred_language TEXT DEFAULT 'en'");
      // Create all new tables
      await _createAllTables(db);
    }

    if (oldVersion < 3) {
      await _ensureColumn(
        db,
        AppConstants.diagnosesTable,
        'label_key',
        'TEXT',
      );
      await _ensureColumn(
        db,
        AppConstants.diseaseKnowledgeTable,
        'label_key',
        'TEXT',
      );
    }
  }

  Future<void> _ensureColumn(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    final exists = rows.any((row) => row['name'] == column);
    if (!exists) {
      await db.execute(
        'ALTER TABLE $table ADD COLUMN $column $definition',
      );
    }
  }

  // ─── Users ────────────────────────────────────────────────────────────────

  Future<void> upsertUser(Map<String, dynamic> userData) async {
    if (_isDisabledOnPlatform) return;
    final db = await database;
    await db.insert(
      AppConstants.usersTable,
      userData,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getUserById(String id) async {
    if (_isDisabledOnPlatform) return null;
    final db = await database;
    final rows = await db.query(
      AppConstants.usersTable,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<Map<String, dynamic>?> getUserByEmail(String email) async {
    if (_isDisabledOnPlatform) return null;
    final db = await database;
    final rows = await db.query(
      AppConstants.usersTable,
      where: 'email = ?',
      whereArgs: [email],
      limit: 1,
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<void> deleteUser(String id) async {
    if (_isDisabledOnPlatform) return;
    final db = await database;
    await db.delete(
      AppConstants.usersTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ─── Sync Queue ───────────────────────────────────────────────────────────

  Future<int> addToSyncQueue({
    required String tableName,
    required String recordId,
    required String operation, // 'UPSERT' | 'DELETE'
    required String payload, // JSON string
  }) async {
    if (_isDisabledOnPlatform) return 0;
    final db = await database;
    return db.insert(AppConstants.syncQueueTable, {
      'table_name': tableName,
      'record_id': recordId,
      'operation': operation,
      'payload': payload,
      'created_at': DateTime.now().toIso8601String(),
      'attempts': 0,
    });
  }

  Future<List<Map<String, dynamic>>> getPendingSyncItems() async {
    if (_isDisabledOnPlatform) return [];
    final db = await database;
    return db.query(
      AppConstants.syncQueueTable,
      orderBy: 'created_at ASC',
    );
  }

  Future<void> markSyncItemDone(int id) async {
    if (_isDisabledOnPlatform) return;
    final db = await database;
    await db.delete(
      AppConstants.syncQueueTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> incrementSyncAttempts(int id, {String? error}) async {
    if (_isDisabledOnPlatform) return;
    final db = await database;
    await db.rawUpdate(
      'UPDATE ${AppConstants.syncQueueTable} '
      'SET attempts = attempts + 1, last_error = ? WHERE id = ?',
      [error, id],
    );
  }

  Future<String?> getLatestCropImageUrl(String cropId) async {
    if (_isDisabledOnPlatform) return null;
    final db = await database;

    Future<String?> firstImageFromTable({
      required String table,
      required String where,
      required List<Object?> whereArgs,
    }) async {
      final rows = await db.query(
        table,
        columns: const ['image_url'],
        where: where,
        whereArgs: whereArgs,
        orderBy: 'created_at DESC',
      );
      for (final row in rows) {
        final imageUrl = _normalizeOptionalString(row['image_url']);
        if (imageUrl != null) {
          return imageUrl;
        }
      }
      return null;
    }

    final progressImage = await firstImageFromTable(
      table: AppConstants.progressUpdatesTable,
      where: 'crop_id = ? AND is_deleted = 0',
      whereArgs: [cropId],
    );
    if (progressImage != null) {
      return progressImage;
    }

    final diagnosisImage = await firstImageFromTable(
      table: AppConstants.diagnosesTable,
      where: 'crop_id = ? AND is_deleted = 0',
      whereArgs: [cropId],
    );
    if (diagnosisImage != null) {
      return diagnosisImage;
    }

    final sessionRows = await db.query(
      AppConstants.chatSessionsTable,
      columns: const ['id'],
      where: 'crop_id = ? AND is_deleted = 0',
      whereArgs: [cropId],
      orderBy: 'last_message_at DESC',
    );

    for (final session in sessionRows) {
      final sessionId = session['id'] as String?;
      if (sessionId == null || sessionId.isEmpty) {
        continue;
      }

      final messageRows = await db.query(
        AppConstants.chatMessagesTable,
        columns: const ['metadata'],
        where: 'session_id = ?',
        whereArgs: [sessionId],
        orderBy: 'created_at DESC',
      );

      for (final message in messageRows) {
        final metadata = _parseMetadata(message['metadata']);
        final imageUrl = _normalizeOptionalString(metadata?['image_url']);
        if (imageUrl != null) {
          return imageUrl;
        }
      }
    }

    return null;
  }

  Future<void> closeDatabase() async {
    if (_isDisabledOnPlatform) return;
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }

  // ─── Generic upsert / query helpers ──────────────────────────────────────

  Future<void> upsertRow(String table, Map<String, dynamic> data) async {
    if (_isDisabledOnPlatform) return;
    final db = await database;
    await db.insert(table, data, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Map<String, dynamic>? _parseMetadata(dynamic raw) {
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        return null;
      }
    }
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return null;
  }

  String? _normalizeOptionalString(dynamic raw) {
    if (raw is! String) {
      return null;
    }
    final value = raw.trim();
    return value.isEmpty ? null : value;
  }

  Future<void> upsertRows(
    String table,
    Iterable<Map<String, dynamic>> rows,
  ) async {
    if (_isDisabledOnPlatform) return;
    final items = rows.toList(growable: false);
    if (items.isEmpty) return;

    final db = await database;
    final batch = db.batch();
    for (final row in items) {
      batch.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> queryByUserId(
    String table,
    String userId, {
    bool includeDeleted = false,
  }) async {
    if (_isDisabledOnPlatform) return [];
    final db = await database;
    final where =
        includeDeleted ? 'user_id = ?' : 'user_id = ? AND is_deleted = 0';
    return db.query(table, where: where, whereArgs: [userId]);
  }

  Future<Map<String, dynamic>?> queryById(String table, String id) async {
    if (_isDisabledOnPlatform) return null;
    final db = await database;
    final rows =
        await db.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<void> softDelete(String table, String id) async {
    if (_isDisabledOnPlatform) return;
    final db = await database;
    await db.update(
      table,
      {'is_deleted': 1, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> hardDelete(String table, String id) async {
    if (_isDisabledOnPlatform) return;
    final db = await database;
    await db.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> queryChatMessages(String sessionId) async {
    if (_isDisabledOnPlatform) return [];
    final db = await database;
    return db.query(
      AppConstants.chatMessagesTable,
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'created_at ASC',
    );
  }

  Future<List<Map<String, dynamic>>> queryTasksForTreatment(
      String treatmentId) async {
    if (_isDisabledOnPlatform) return [];
    final db = await database;
    return db.query(
      AppConstants.treatmentTasksTable,
      where: 'treatment_id = ? AND is_deleted = 0',
      whereArgs: [treatmentId],
      orderBy: 'task_order ASC, due_at ASC',
    );
  }

  Future<List<Map<String, dynamic>>> queryTasksForCrop(String cropId) async {
    if (_isDisabledOnPlatform) return [];
    final db = await database;
    return db.query(
      AppConstants.treatmentTasksTable,
      where: 'crop_id = ? AND is_deleted = 0',
      whereArgs: [cropId],
      orderBy: 'task_order ASC, due_at ASC',
    );
  }

  Future<List<Map<String, dynamic>>> queryDiagnosesForCrop(
      String cropId) async {
    if (_isDisabledOnPlatform) return [];
    final db = await database;
    return db.query(
      AppConstants.diagnosesTable,
      where: 'crop_id = ? AND is_deleted = 0',
      whereArgs: [cropId],
      orderBy: 'diagnosed_at ASC',
    );
  }

  Future<List<Map<String, dynamic>>> queryDiseaseKnowledge(
      String cropType) async {
    if (_isDisabledOnPlatform) return [];
    final db = await database;
    if (cropType.isEmpty) {
      return db.query(
        AppConstants.diseaseKnowledgeTable,
        where: 'is_active = 1',
        orderBy: 'disease_name ASC',
      );
    }
    return db.query(
      AppConstants.diseaseKnowledgeTable,
      where: 'crop_type = ? AND is_active = 1',
      whereArgs: [cropType],
      orderBy: 'disease_name ASC',
    );
  }
}
