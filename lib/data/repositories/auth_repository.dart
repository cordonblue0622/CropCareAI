import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../local/database_helper.dart';
import '../models/user_model.dart';
import '../remote/supabase_service.dart';

class AuthResult {
  final bool success;
  final UserModel? user;
  final String? error;
  final bool requiresEmailConfirmation;
  final String? message;

  const AuthResult({
    required this.success,
    this.user,
    this.error,
    this.requiresEmailConfirmation = false,
    this.message,
  });
}

/// Coordinates authentication between Supabase (remote) and SQLite (local cache).
class AuthRepository {
  final SupabaseService supabaseService;
  final DatabaseHelper dbHelper;

  const AuthRepository({
    required this.supabaseService,
    required this.dbHelper,
  });

  String? _cleanString(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  DateTime? _tryParseDate(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value);
  }

  UserModel _buildUserModel(
    User supabaseUser, {
    Map<String, dynamic>? profile,
  }) {
    return UserModel(
      id: supabaseUser.id,
      fullName: _cleanString(profile?['full_name']) ??
          _cleanString(supabaseUser.userMetadata?['full_name']),
      displayName: _cleanString(profile?['display_name']) ??
          _cleanString(supabaseUser.userMetadata?['display_name']),
      email: supabaseUser.email ?? (_cleanString(profile?['email']) ?? ''),
      phone: _cleanString(profile?['phone']) ??
          _cleanString(supabaseUser.userMetadata?['phone']) ??
          supabaseUser.phone,
      avatarUrl: _cleanString(profile?['avatar_url']) ??
          _cleanString(supabaseUser.userMetadata?['avatar_url']),
      barangay: _cleanString(profile?['barangay']) ??
          _cleanString(supabaseUser.userMetadata?['barangay']),
      municipality: _cleanString(profile?['municipality']) ??
          _cleanString(supabaseUser.userMetadata?['municipality']),
      province: _cleanString(profile?['province']) ??
          _cleanString(supabaseUser.userMetadata?['province']),
      country: _cleanString(profile?['country']) ??
          _cleanString(supabaseUser.userMetadata?['country']),
      role: _cleanString(profile?['role']) ??
          _cleanString(supabaseUser.userMetadata?['role']) ?? 'farmer',
      isApproved: (profile?['is_approved'] as int?) == 1 ||
          (profile?['is_approved'] as bool?) == true ||
          (supabaseUser.userMetadata?['is_approved'] as bool?) == true,
      provider: supabaseUser.appMetadata['provider'] as String? ?? 'email',
      createdAt: _tryParseDate(profile?['created_at']),
      updatedAt: _tryParseDate(profile?['updated_at']) ?? DateTime.now(),
    );
  }

  Future<UserModel?> loadCurrentUser() async {
    final supabaseUser = supabaseService.currentUser;
    if (supabaseUser == null) return null;

    try {
      var profile = await supabaseService.getProfile(supabaseUser.id);
      if (profile != null) {
        final user = _buildUserModel(supabaseUser, profile: profile);
        await dbHelper.upsertUser(user.toMap());
        return user;
      }

      await _ensureRemoteProfile(
        userId: supabaseUser.id,
        email: supabaseUser.email ?? '',
        fullName: _cleanString(supabaseUser.userMetadata?['full_name']),
        avatarUrl: _cleanString(supabaseUser.userMetadata?['avatar_url']),
        barangay: _cleanString(supabaseUser.userMetadata?['barangay']),
        municipality: _cleanString(supabaseUser.userMetadata?['municipality']),
        province: _cleanString(supabaseUser.userMetadata?['province']),
        country: _cleanString(supabaseUser.userMetadata?['country']),
      );

      profile = await supabaseService.getProfile(supabaseUser.id);
      if (profile != null) {
        final user = _buildUserModel(supabaseUser, profile: profile);
        await dbHelper.upsertUser(user.toMap());
        return user;
      }
    } catch (_) {}

    final cached = await dbHelper.getUserById(supabaseUser.id) ??
        (supabaseUser.email != null
            ? await dbHelper.getUserByEmail(supabaseUser.email!)
            : null);
    if (cached != null) {
      return UserModel.fromMap(cached);
    }

    return _buildUserModel(supabaseUser);
  }

  // ─── Sign Up ──────────────────────────────────────────────────────────────

  Future<AuthResult> signUp({
    required String email,
    required String password,
    required String fullName,
    required String emailRedirectTo,
    String? barangay,
    required String municipality,
    required String province,
    required String country,
  }) async {
    try {
      final response = await supabaseService.signUpWithEmail(
        email: email,
        password: password,
        fullName: fullName,
        emailRedirectTo: emailRedirectTo,
        barangay: barangay,
        municipality: municipality,
        province: province,
        country: country,
        legalAcceptedAt: DateTime.now(),
        termsVersion: AppConstants.termsVersion,
        privacyPolicyVersion: AppConstants.privacyPolicyVersion,
      );

      final supabaseUser = response.user;
      if (supabaseUser == null) {
        return const AuthResult(
          success: false,
          error: 'Registration failed. Please try again or verify your email.',
        );
      }

      final now = DateTime.now();
      final user = UserModel(
        id: supabaseUser.id,
        fullName: fullName,
        email: email,
        barangay: _cleanString(barangay),
        municipality: _cleanString(municipality),
        province: _cleanString(province),
        country: _cleanString(country),
        provider: 'email',
        createdAt: now,
        updatedAt: now,
      );

      // Cache locally
      await dbHelper.upsertUser(user.toMap());

      final hasAuthenticatedSession =
          response.session != null && supabaseService.isSignedIn;

      if (!hasAuthenticatedSession) {
        return const AuthResult(
          success: true,
          requiresEmailConfirmation: true,
          message:
              'Account created. Check your email for the verification link, then sign in.',
        );
      }

      await _ensureRemoteProfile(
        userId: supabaseUser.id,
        email: email,
        fullName: fullName,
        barangay: barangay,
        municipality: municipality,
        province: province,
        country: country,
      );

      return AuthResult(success: true, user: user);
    } on AuthException catch (e) {
      return AuthResult(success: false, error: e.message);
    } catch (_) {
      return const AuthResult(
        success: false,
        error:
            'Could not create your account. Check your internet connection and try again.',
      );
    }
  }

  // ─── Admin Sign Up (pending superadmin approval) ─────────────────────────

  /// Creates an admin profile pending superadmin approval.
  /// The Supabase Auth user is NOT created yet — it is created when the
  /// superadmin approves the account via [approveAdmin].
  Future<AuthResult> signUpAdmin({
    required String email,
    required String password,
    required String fullName,
    String? barangay,
    required String municipality,
    required String province,
    required String country,
  }) async {
    try {
      // First check if a Supabase Auth user already exists for this email
      final existingProfile = await supabaseService.getProfileByEmail(email);
      if (existingProfile != null) {
        return const AuthResult(
          success: false,
          error: 'An account with this email already exists.',
        );
      }

      // Create profile locally only (Supabase Auth user + profile created on approval)
      final now = DateTime.now();
      final user = UserModel(
        id: const Uuid().v4(), // Temporary ID; replaced on approval
        fullName: fullName,
        email: email,
        barangay: _cleanString(barangay),
        municipality: _cleanString(municipality),
        province: _cleanString(province),
        country: _cleanString(country),
        provider: 'email',
        role: 'admin',
        isApproved: false,
        createdAt: now,
        updatedAt: now,
      );

      await dbHelper.upsertUser(user.toMap());

      return const AuthResult(
        success: true,
        requiresEmailConfirmation: false,
        message:
            'Admin account created. Pending superadmin approval before you can sign in.',
      );
    } on AuthException catch (e) {
      return AuthResult(success: false, error: e.message);
    } catch (_) {
      return const AuthResult(
        success: false,
        error:
            'Could not create admin account. Check your internet connection and try again.',
      );
    }
  }

  // ─── Admin Approval (Superadmin only) ────────────────────────────────────

  /// Approves a pending admin account and creates their Supabase Auth user
  /// so they can log in. Uses the Supabase Admin API (service role key).
  Future<AuthResult> approveAdmin({
    required String email,
    required String password,
    required String fullName,
    String? barangay,
    required String municipality,
    required String province,
    required String country,
  }) async {
    try {
      // Create the Supabase Auth user via Admin API (auto-confirms email)
      final authResponse = await supabaseService.createAdminUser(
        email: email,
        password: password,
        fullName: fullName,
        barangay: barangay,
        municipality: municipality,
        province: province,
        country: country,
      );

      final supabaseUser = authResponse.user;
      if (supabaseUser == null) {
        return const AuthResult(
          success: false,
          error: 'Failed to create Supabase Auth user for admin.',
        );
      }

      // Upsert the profile (role/is_approved stored in userMetadata via Admin API)
      final now = DateTime.now();
      final profileData = <String, dynamic>{
        'id': supabaseUser.id,
        'email': email,
        'full_name': fullName,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
        if (barangay != null && barangay.trim().isNotEmpty)
          'barangay': barangay.trim(),
        'municipality': municipality.trim(),
        'province': province.trim(),
        'country': country.trim(),
      };

      await supabaseService.upsertProfile(profileData);

      // Update local cache
      final user = UserModel(
        id: supabaseUser.id,
        fullName: fullName,
        email: email,
        barangay: _cleanString(barangay),
        municipality: _cleanString(municipality),
        province: _cleanString(province),
        country: _cleanString(country),
        provider: 'email',
        role: 'admin',
        isApproved: true,
        createdAt: now,
        updatedAt: now,
      );

      await dbHelper.upsertUser(user.toMap());

      return AuthResult(success: true, user: user);
    } on AuthException catch (e) {
      return AuthResult(success: false, error: e.message);
    } catch (_) {
      return const AuthResult(
        success: false,
        error:
            'Could not approve admin account. Check your internet connection and try again.',
      );
    }
  }

  // ─── Sign In ──────────────────────────────────────────────────────────────

  Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await supabaseService.signInWithEmail(
        email: email,
        password: password,
      );

      final supabaseUser = response.user;
      if (supabaseUser == null) {
        return const AuthResult(success: false, error: 'Sign-in failed.');
      }

      var profile = await supabaseService.getProfile(supabaseUser.id);
      if (profile == null) {
        await _ensureRemoteProfile(
          userId: supabaseUser.id,
          email: supabaseUser.email ?? email,
          fullName: _cleanString(supabaseUser.userMetadata?['full_name']),
          avatarUrl: _cleanString(supabaseUser.userMetadata?['avatar_url']),
          barangay: _cleanString(supabaseUser.userMetadata?['barangay']),
          municipality:
              _cleanString(supabaseUser.userMetadata?['municipality']),
          province: _cleanString(supabaseUser.userMetadata?['province']),
          country: _cleanString(supabaseUser.userMetadata?['country']),
        );
        profile = await supabaseService.getProfile(supabaseUser.id);
      }

      final user = _buildUserModel(supabaseUser, profile: profile);

      await dbHelper.upsertUser(user.toMap());

      return AuthResult(success: true, user: user);
    } on AuthException catch (e) {
      return AuthResult(success: false, error: e.message);
    } catch (_) {
      return const AuthResult(
        success: false,
        error:
            'Could not sign in. Check your internet connection and try again.',
      );
    }
  }

  Future<UserModel> updateProfile({
    String? fullName,
    String? displayName,
    String? phone,
    String? barangay,
    required String municipality,
    required String province,
    required String country,
  }) async {
    final supabaseUser = supabaseService.currentUser;
    if (supabaseUser == null) {
      throw Exception('No active session.');
    }

    final existingProfile = await supabaseService.getProfile(supabaseUser.id);
    final mergedProfile = <String, dynamic>{
      if (existingProfile != null) ...existingProfile,
      'id': supabaseUser.id,
      'full_name': _cleanString(fullName),
      'display_name': _cleanString(displayName),
      'email':
          supabaseUser.email ?? _cleanString(existingProfile?['email']) ?? '',
      'phone': _cleanString(phone),
      'avatar_url': _cleanString(existingProfile?['avatar_url']) ??
          _cleanString(supabaseUser.userMetadata?['avatar_url']),
      'barangay': _cleanString(barangay),
      'municipality': _cleanString(municipality),
      'province': _cleanString(province),
      'country': _cleanString(country),
      'updated_at': DateTime.now().toIso8601String(),
    };

    await supabaseService.upsertProfile(mergedProfile);

    final user = _buildUserModel(supabaseUser, profile: mergedProfile);
    await dbHelper.upsertUser(user.toMap());
    return user;
  }

  Future<UserModel> updateAvatar({
    required List<int> bytes,
    required String extension,
    required String contentType,
  }) async {
    final supabaseUser = supabaseService.currentUser;
    if (supabaseUser == null) {
      throw Exception('No active session.');
    }

    final avatarUrl = await supabaseService.uploadProfileImage(
      userId: supabaseUser.id,
      bytes: bytes,
      extension: extension,
      contentType: contentType,
    );
    final existingProfile = await supabaseService.getProfile(supabaseUser.id);
    final mergedProfile = <String, dynamic>{
      if (existingProfile != null) ...existingProfile,
      'id': supabaseUser.id,
      'email':
          supabaseUser.email ?? _cleanString(existingProfile?['email']) ?? '',
      'avatar_url': avatarUrl,
      'updated_at': DateTime.now().toIso8601String(),
    };

    await supabaseService.upsertProfile(mergedProfile);
    await supabaseService.updateUserMetadata({'avatar_url': avatarUrl});

    final user = _buildUserModel(supabaseUser, profile: mergedProfile);
    await dbHelper.upsertUser(user.toMap());
    return user;
  }

  Future<void> requestEmailChange(
    String email, {
    required String emailRedirectTo,
  }) =>
      supabaseService.requestEmailChange(
        email,
        emailRedirectTo: emailRedirectTo,
      );

  Future<void> _ensureRemoteProfile({
    required String userId,
    required String email,
    String? fullName,
    String? avatarUrl,
    String? barangay,
    String? municipality,
    String? province,
    String? country,
  }) async {
    final existing = await supabaseService.getProfile(userId);
    if (existing != null) return;

    await supabaseService.upsertProfile({
      'id': userId,
      'full_name': fullName,
      'email': email,
      'avatar_url': avatarUrl,
      'barangay': _cleanString(barangay),
      'municipality': _cleanString(municipality),
      'province': _cleanString(province),
      'country': _cleanString(country),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  // ─── Misc ─────────────────────────────────────────────────────────────────

  Future<void> signOut() => supabaseService.signOut();

  Future<void> clearDeletedAccountFromDevice() async {
    try {
      await supabaseService.signOut();
    } finally {
      await dbHelper.deleteDatabaseFile();
    }
  }

  Future<void> sendPasswordReset(
    String email, {
    required String redirectTo,
  }) =>
      supabaseService.sendPasswordResetEmail(email, redirectTo: redirectTo);

  Future<void> updatePassword(String password) =>
      supabaseService.updatePassword(password);

  // ─── Admin Password Reset (Superadmin only) ──────────────────────────────

  /// Superadmin resets an admin's password via the Supabase Admin API.
  Future<void> resetAdminPassword({
    required String userId,
    String? newPassword,
    required String redirectTo,
  }) async {
    await supabaseService.resetAdminPassword(
      userId: userId,
      newPassword: newPassword,
      redirectTo: redirectTo,
    );
  }

  /// Superadmin sends a password reset email to an admin.
  Future<void> sendAdminPasswordResetEmail({
    required String email,
    required String redirectTo,
  }) async {
    await supabaseService.sendAdminPasswordResetEmail(
      email: email,
      redirectTo: redirectTo,
    );
  }

  UserModel? get currentUser {
    final u = supabaseService.currentUser;
    if (u == null) return null;
    return _buildUserModel(u);
  }

  bool get isSignedIn => supabaseService.isSignedIn;

  Stream<AuthState> get authStateChanges => supabaseService.authStateChanges;
}
