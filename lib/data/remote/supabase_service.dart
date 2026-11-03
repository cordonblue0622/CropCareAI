import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Thin wrapper around the Supabase client.
/// All remote data operations go through this class.
class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;

  SupabaseClient get client => _client;

  // ─── Auth ─────────────────────────────────────────────────────────────────

  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    required String fullName,
    required String emailRedirectTo,
    String? barangay,
    String? municipality,
    String? province,
    String? country,
    required DateTime legalAcceptedAt,
    required String termsVersion,
    required String privacyPolicyVersion,
  }) {
    return _client.auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: emailRedirectTo,
      data: {
        'full_name': fullName,
        if (barangay != null && barangay.trim().isNotEmpty)
          'barangay': barangay.trim(),
        if (municipality != null && municipality.trim().isNotEmpty)
          'municipality': municipality.trim(),
        if (province != null && province.trim().isNotEmpty)
          'province': province.trim(),
        if (country != null && country.trim().isNotEmpty)
          'country': country.trim(),
        'legal_accepted_at': legalAcceptedAt.toUtc().toIso8601String(),
        'terms_version': termsVersion,
        'privacy_policy_version': privacyPolicyVersion,
      },
    );
  }

  Future<void> recordLegalConsent({
    required DateTime acceptedAt,
    required String termsVersion,
    required String privacyPolicyVersion,
  }) async {
    await _client.auth.updateUser(
      UserAttributes(
        data: {
          'legal_accepted_at': acceptedAt.toUtc().toIso8601String(),
          'terms_version': termsVersion,
          'privacy_policy_version': privacyPolicyVersion,
        },
      ),
    );
  }

  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() => _client.auth.signOut();

  Future<void> sendPasswordResetEmail(
    String email, {
    required String redirectTo,
  }) =>
      _client.auth.resetPasswordForEmail(email, redirectTo: redirectTo);

  Future<void> updatePassword(String password) async {
    await _client.auth.updateUser(UserAttributes(password: password));
  }

  Future<void> requestEmailChange(
    String email, {
    required String emailRedirectTo,
  }) async {
    await _client.auth.updateUser(
      UserAttributes(email: email),
      emailRedirectTo: emailRedirectTo,
    );
  }

  User? get currentUser => _client.auth.currentUser;
  String? get authenticatedUserId => currentUser?.id;
  Session? get currentSession => _client.auth.currentSession;
  bool get isSignedIn => currentUser != null;

  // ─── Admin Auth (Superadmin only) ─────────────────────────────────────────
  // These methods use the Supabase Admin API and require the service role key
  // to be configured on the Supabase client.

  /// Creates a new user account with admin privileges via the Admin API.
  /// The email is auto-confirmed so the admin can log in immediately.
  Future<UserResponse> createAdminUser({
    required String email,
    required String password,
    required String fullName,
    String? barangay,
    String? municipality,
    String? province,
    String? country,
  }) async {
    return _client.auth.admin.createUser(
      AdminUserAttributes(
        email: email,
        password: password,
        emailConfirm: true,
        userMetadata: {
          'full_name': fullName,
          'role': 'admin',
          if (barangay != null && barangay.trim().isNotEmpty)
            'barangay': barangay.trim(),
          if (municipality != null && municipality.trim().isNotEmpty)
            'municipality': municipality.trim(),
          if (province != null && province.trim().isNotEmpty)
            'province': province.trim(),
          if (country != null && country.trim().isNotEmpty)
            'country': country.trim(),
        },
      ),
    );
  }

  /// Resets an admin's password via the Admin API (superadmin action).
  /// If [newPassword] is provided, it is set directly. Otherwise, a
  /// password reset email is generated and sent to the user's email.
  Future<void> resetAdminPassword({
    required String userId,
    String? newPassword,
    required String redirectTo,
  }) async {
    if (newPassword != null && newPassword.isNotEmpty) {
      await _client.auth.admin.updateUserById(
        userId,
        attributes: AdminUserAttributes(password: newPassword),
      );
      return;
    }

    // Look up the user's email to send the reset link
    final profile = await getProfile(userId);
    final email = profile?['email'] as String?;
    if (email == null || email.isEmpty) {
      throw StateError('No email found for user $userId.');
    }

    await _client.auth.admin.generateLink(
      type: GenerateLinkType.recovery,
      email: email,
      redirectTo: redirectTo,
    );
  }

  /// Sends a password reset email to an admin (superadmin action).
  Future<void> sendAdminPasswordResetEmail({
    required String email,
    required String redirectTo,
  }) async {
    await _client.auth.admin.generateLink(
      type: GenerateLinkType.recovery,
      email: email,
      redirectTo: redirectTo,
    );
  }

  /// Deletes a user account via the Admin API (superadmin action).
  Future<void> deleteAdminUser(String userId) async {
    await _client.auth.admin.deleteUser(userId);
  }

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  // ─── Profiles ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> getProfile(String userId) async {
    return _client.from('profiles').select().eq('id', userId).maybeSingle();
  }

  Future<Map<String, dynamic>?> getProfileByEmail(String email) async {
    return _client.from('profiles').select().eq('email', email).maybeSingle();
  }

  Future<void> upsertProfile(Map<String, dynamic> profile) async {
    await _client.from('profiles').upsert(profile);
  }

  Future<void> updateUserMetadata(Map<String, dynamic> data) async {
    await _client.auth.updateUser(UserAttributes(data: data));
  }

  Future<String> uploadProfileImage({
    required String userId,
    required List<int> bytes,
    required String extension,
    required String contentType,
  }) async {
    const bucket = 'chat-images';
    final safeExtension = extension.toLowerCase().replaceAll('.', '');
    final path =
        '$userId/profile/avatar-${DateTime.now().millisecondsSinceEpoch}.${safeExtension.isEmpty ? 'jpg' : safeExtension}';
    await _client.storage.from(bucket).uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions: FileOptions(contentType: contentType, upsert: false),
        );
    return _client.storage.from(bucket).getPublicUrl(path);
  }

  // ─── Generic CRUD (used by SyncService) ───────────────────────────────────

  Future<void> upsertRecord({
    required String table,
    required Map<String, dynamic> data,
  }) async {
    final sanitizedData = _sanitizeRemoteData(table, data);
    if (table == 'crops' ||
        table == 'treatments' ||
        table == 'treatment_tasks') {
      final savedRow =
          await _client.from(table).upsert(sanitizedData).select('id').single();
      if (savedRow['id'] != sanitizedData['id']) {
        throw StateError(
          'Supabase did not confirm the $table upsert '
          'for record ${sanitizedData['id']}.',
        );
      }
      return;
    }
    await _client.from(table).upsert(sanitizedData);
  }

  Future<void> deleteRecord({
    required String table,
    required String id,
  }) async {
    if (table == 'notifications') {
      final userId = currentUser?.id;
      if (userId == null) {
        throw StateError('Sign in before deleting a notification.');
      }
      await _client
          .from(table)
          .delete()
          .eq('user_id', userId)
          .eq('id', id)
          .select('id');
      return;
    }
    await _client.from(table).delete().eq('id', id);
  }

  Future<List<Map<String, dynamic>>> fetchRecordsUpdatedSince({
    required String table,
    required String userId,
    required DateTime since,
  }) async {
    return _client
        .from(table)
        .select()
        .eq('user_id', userId)
        .gte('updated_at', since.toIso8601String());
  }

  // ─── Crops ────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getCrops(String userId) async {
    return _getCrops(userId, includeDeleted: false);
  }

  Future<List<Map<String, dynamic>>> getCropsIncludingDeleted(
    String userId,
  ) async {
    return _getCrops(userId, includeDeleted: true);
  }

  Future<List<Map<String, dynamic>>> _getCrops(
    String userId, {
    required bool includeDeleted,
  }) async {
    var query = _client.from('crops').select().eq('user_id', userId);
    if (!includeDeleted) query = query.eq('is_deleted', false);
    return query.order('updated_at', ascending: false);
  }

  Future<Map<String, dynamic>?> getCropById({
    required String userId,
    required String cropId,
  }) async {
    return _client
        .from('crops')
        .select()
        .eq('user_id', userId)
        .eq('id', cropId)
        .maybeSingle();
  }

  Future<void> upsertCrop(Map<String, dynamic> crop) async {
    await upsertRecord(table: 'crops', data: crop);
  }

  Future<void> softDeleteCrop(String cropId) async {
    await softDeleteRecord(table: 'crops', id: cropId);
  }

  Future<void> softDeleteRecord({
    required String table,
    required String id,
  }) async {
    await _client.from(table).update({
      'is_deleted': true,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  // ─── Diagnoses ────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getDiagnoses(String userId) async {
    return _getDiagnoses(userId, includeDeleted: false);
  }

  Future<List<Map<String, dynamic>>> getDiagnosesIncludingDeleted(
    String userId,
  ) async {
    return _getDiagnoses(userId, includeDeleted: true);
  }

  Future<List<Map<String, dynamic>>> _getDiagnoses(
    String userId, {
    required bool includeDeleted,
  }) async {
    var query = _client.from('diagnoses').select().eq('user_id', userId);
    if (!includeDeleted) query = query.eq('is_deleted', false);
    return query.order('diagnosed_at', ascending: false);
  }

  Future<List<Map<String, dynamic>>> getDiagnosesByCrop(String cropId) async {
    return _client
        .from('diagnoses')
        .select()
        .eq('crop_id', cropId)
        .eq('is_deleted', false)
        .order('diagnosed_at', ascending: false);
  }

  Future<void> upsertDiagnosis(Map<String, dynamic> diagnosis) async {
    await _client
        .from('diagnoses')
        .upsert(_sanitizeRemoteData('diagnoses', diagnosis));
  }

  // ─── Treatments ───────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getTreatments(String userId) async {
    return _getTreatments(userId, includeDeleted: false);
  }

  Future<List<Map<String, dynamic>>> getTreatmentsIncludingDeleted(
    String userId,
  ) async {
    return _getTreatments(userId, includeDeleted: true);
  }

  Future<List<Map<String, dynamic>>> _getTreatments(
    String userId, {
    required bool includeDeleted,
  }) async {
    var query = _client.from('treatments').select().eq('user_id', userId);
    if (!includeDeleted) query = query.eq('is_deleted', false);
    return query.order('created_at', ascending: false);
  }

  Future<List<Map<String, dynamic>>> getTreatmentsByCrop(String cropId) async {
    return _client
        .from('treatments')
        .select()
        .eq('crop_id', cropId)
        .eq('is_deleted', false)
        .order('created_at', ascending: false);
  }

  Future<void> upsertTreatment(Map<String, dynamic> treatment) async {
    await _client.from('treatments').upsert(treatment);
  }

  // ─── Treatment Tasks ──────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getTreatmentTasks(
      String treatmentId) async {
    return _client
        .from('treatment_tasks')
        .select()
        .eq('treatment_id', treatmentId)
        .eq('is_deleted', false)
        .order('task_order', ascending: true);
  }

  Future<List<Map<String, dynamic>>> getTreatmentTasksByCrop(
    String cropId,
  ) async {
    return _client
        .from('treatment_tasks')
        .select()
        .eq('crop_id', cropId)
        .eq('is_deleted', false)
        .order('due_at', ascending: true);
  }

  Future<List<Map<String, dynamic>>> getTreatmentTasksByUser(
      String userId) async {
    return _getTreatmentTasksByUser(userId, includeDeleted: false);
  }

  Future<List<Map<String, dynamic>>> getAllTreatmentTasksByUser(
    String userId,
  ) async {
    return _getTreatmentTasksByUser(userId, includeDeleted: true);
  }

  Future<List<Map<String, dynamic>>> _getTreatmentTasksByUser(
    String userId, {
    required bool includeDeleted,
  }) async {
    var query = _client.from('treatment_tasks').select().eq('user_id', userId);
    if (!includeDeleted) query = query.eq('is_deleted', false);
    return query.order('due_at', ascending: true);
  }

  Future<void> upsertTreatmentTask(Map<String, dynamic> task) async {
    await _client.from('treatment_tasks').upsert(task);
  }

  Future<void> markTreatmentTaskCompleted(
    String taskId, {
    required DateTime completedAt,
  }) async {
    await _client.from('treatment_tasks').update({
      'status': 'completed',
      'completed_at': completedAt.toIso8601String(),
      'updated_at': completedAt.toIso8601String(),
    }).eq('id', taskId);
  }

  // ─── Progress Updates ─────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getProgressUpdates(String cropId) async {
    return _client
        .from('progress_updates')
        .select()
        .eq('crop_id', cropId)
        .eq('is_deleted', false)
        .order('update_date', ascending: false);
  }

  Future<void> insertProgressUpdate(Map<String, dynamic> update) async {
    await _client.from('progress_updates').insert(update);
  }

  Future<String?> getLatestCropImageUrl(String cropId) async {
    String? normalizeImageUrl(dynamic raw) {
      if (raw is! String) return null;
      final trimmed = raw.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    Map<String, dynamic>? parseMetadata(dynamic raw) {
      try {
        if (raw is Map) {
          return Map<String, dynamic>.from(raw);
        }
        if (raw is String && raw.trim().isNotEmpty) {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            return Map<String, dynamic>.from(decoded);
          }
        }
      } catch (_) {
        return null;
      }
      return null;
    }

    final progressRows = await _client
        .from('progress_updates')
        .select('image_url')
        .eq('crop_id', cropId)
        .eq('is_deleted', false)
        .order('update_date', ascending: false)
        .limit(10);
    for (final row in progressRows) {
      final imageUrl = normalizeImageUrl(row['image_url']);
      if (imageUrl != null) {
        return imageUrl;
      }
    }

    final diagnosisRows = await _client
        .from('diagnoses')
        .select('image_url')
        .eq('crop_id', cropId)
        .eq('is_deleted', false)
        .order('diagnosed_at', ascending: false)
        .limit(10);
    for (final row in diagnosisRows) {
      final imageUrl = normalizeImageUrl(row['image_url']);
      if (imageUrl != null) {
        return imageUrl;
      }
    }

    final sessionRows = await _client
        .from('chat_sessions')
        .select('id')
        .eq('crop_id', cropId)
        .eq('is_deleted', false)
        .order('last_message_at', ascending: false)
        .limit(5);
    for (final session in sessionRows) {
      final sessionId = session['id'] as String?;
      if (sessionId == null || sessionId.isEmpty) continue;

      final messageRows = await _client
          .from('chat_messages')
          .select('metadata')
          .eq('session_id', sessionId)
          .order('created_at', ascending: false)
          .limit(20);
      for (final row in messageRows) {
        final metadata = parseMetadata(row['metadata']);
        final imageUrl = normalizeImageUrl(metadata?['image_url']);
        if (imageUrl != null) {
          return imageUrl;
        }
      }
    }

    return null;
  }

  // ─── Chat Image Storage ───────────────────────────────────────────────────
  // Requires a public 'chat-images' bucket in your Supabase Storage.
  // Create it in: Supabase Dashboard → Storage → New bucket → chat-images (public).

  Future<String?> uploadChatImage({
    required String userId,
    required String messageId,
    required List<int> bytes,
  }) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty || normalizedUserId == 'unknown') {
      debugPrint(
        'Supabase storage upload skipped: missing authenticated user id for chat image.',
      );
      return null;
    }

    try {
      const bucket = 'chat-images';
      final path = '$normalizedUserId/$messageId.jpg';
      await _client.storage.from(bucket).uploadBinary(
            path,
            Uint8List.fromList(bytes),
            fileOptions:
                const FileOptions(contentType: 'image/jpeg', upsert: true),
          );
      return _client.storage.from(bucket).getPublicUrl(path);
    } catch (error) {
      debugPrint(
        'Supabase storage upload failed for chat-images. '
        'Check that the bucket exists and that authenticated INSERT access '
        'is allowed for the user folder. Error: $error',
      );
      return null;
    }
  }

  // ─── Chat Sessions ────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getChatSessions(String userId) async {
    return _client
        .from('chat_sessions')
        .select()
        .eq('user_id', userId)
        .eq('is_deleted', false)
        .order('last_message_at', ascending: false);
  }

  Future<void> upsertChatSession(Map<String, dynamic> session) async {
    await _client.from('chat_sessions').upsert(session);
  }

  // ─── Chat Messages ────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getChatMessages(String sessionId) async {
    return _client
        .from('chat_messages')
        .select()
        .eq('session_id', sessionId)
        .order('created_at', ascending: true);
  }

  Future<void> insertChatMessage(Map<String, dynamic> message) async {
    await _client.from('chat_messages').insert(message);
  }

  Future<void> upsertChatMessage(Map<String, dynamic> message) async {
    await _client.from('chat_messages').upsert(message);
  }

  // ─── Notifications ────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getNotifications(String userId) async {
    return _client
        .from('notifications')
        .select()
        .eq('user_id', userId)
        .order('scheduled_for', ascending: true);
  }

  Future<void> insertNotification(Map<String, dynamic> notification) async {
    await _client.from('notifications').insert(notification);
  }

  Future<void> markNotificationRead(String notificationId) async {
    final userId = currentUser?.id;
    if (userId == null) return;
    await _client
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', userId)
        .eq('id', notificationId);
  }

  Future<void> deleteNotification(String notificationId) async {
    await deleteRecord(table: 'notifications', id: notificationId);
  }

  // ─── Disease Knowledge Base ───────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getDiseaseKnowledge({
    String? cropType,
  }) async {
    var query =
        _client.from('disease_knowledge_base').select().eq('is_active', true);
    if (cropType != null) {
      query = query.eq('crop_type', cropType);
    }
    return query.order('disease_name', ascending: true);
  }

  Future<List<Map<String, dynamic>>> getDiseaseTreatmentDaySteps(
    String diseaseKnowledgeBaseId,
  ) {
    return _client
        .from('disease_treatment_day_steps')
        .select()
        .eq('disease_knowledge_base_id', diseaseKnowledgeBaseId)
        .eq('is_active', true)
        .order('day_number', ascending: true);
  }

  Future<List<Map<String, dynamic>>> getChatSessionsByCrop(
      String cropId) async {
    return _client
        .from('chat_sessions')
        .select()
        .eq('crop_id', cropId)
        .eq('is_deleted', false)
        .order('last_message_at', ascending: true);
  }

  Future<void> upsertDiseaseKnowledgeBatch(
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return;

    const batchSize = 100;
    for (var start = 0; start < rows.length; start += batchSize) {
      final end =
          (start + batchSize) > rows.length ? rows.length : start + batchSize;
      await _client.from('disease_knowledge_base').upsert(rows
          .sublist(start, end)
          .map((row) => _sanitizeRemoteData('disease_knowledge_base', row))
          .toList());
    }
  }

  Map<String, dynamic> _sanitizeRemoteData(
    String table,
    Map<String, dynamic> data,
  ) {
    final sanitized = sanitizeOptionalUuidReferences(
      table,
      normalizeRemoteTimestamps(data),
    );
    if (table == 'diagnoses' || table == 'disease_knowledge_base') {
      sanitized.remove('label_key');
    }
    return sanitized;
  }

  @visibleForTesting
  static Map<String, dynamic> sanitizeOptionalUuidReferences(
    String table,
    Map<String, dynamic> data,
  ) {
    final sanitized = Map<String, dynamic>.from(data);
    final optionalUuidFields = switch (table) {
      'chat_sessions' => const ['crop_id'],
      'diagnoses' => const ['chat_session_id'],
      'treatments' => const ['diagnosis_id'],
      'progress_updates' => const ['treatment_id', 'diagnosis_id'],
      'notifications' => const ['crop_id', 'treatment_id'],
      _ => const <String>[],
    };
    for (final field in optionalUuidFields) {
      final value = sanitized[field];
      if (value is String && value.trim().isEmpty) {
        sanitized[field] = null;
      }
    }
    return sanitized;
  }

  static Map<String, dynamic> normalizeRemoteTimestamps(
    Map<String, dynamic> data,
  ) {
    final normalized = Map<String, dynamic>.from(data);
    for (final field in _timestampFields) {
      final value = normalized[field];
      if (value is DateTime) {
        normalized[field] = value.toUtc().toIso8601String();
      } else if (value is String) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) {
          normalized[field] = parsed.toUtc().toIso8601String();
        }
      }
    }
    return normalized;
  }

  static const Set<String> _timestampFields = {
    'created_at',
    'updated_at',
    'diagnosed_at',
    'started_at',
    'ended_at',
    'last_checked_at',
    'update_date',
    'due_at',
    'completed_at',
    'scheduled_for',
    'last_message_at',
  };
}
