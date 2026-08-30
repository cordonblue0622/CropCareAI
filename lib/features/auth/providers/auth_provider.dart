import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/user_model.dart';
import '../../../data/remote/ai_backend_service.dart';
import '../../../data/repositories/auth_repository.dart';

enum AuthStatus { unknown, authenticated, unauthenticated, loading }

class AuthProvider extends ChangeNotifier {
  final AuthRepository authRepository;

  AuthStatus _status = AuthStatus.unknown;
  UserModel? _currentUser;
  String? _errorMessage;
  String? _infoMessage;
  StreamSubscription<AuthState>? _authStateSubscription;
  bool _passwordRecoveryRequested = false;

  AuthProvider({required this.authRepository}) {
    _init();
  }

  AuthStatus get status => _status;
  UserModel? get currentUser => _currentUser;
  String? get errorMessage => _errorMessage;
  String? get infoMessage => _infoMessage;
  bool get isLoading => _status == AuthStatus.loading;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get isResolved => _status != AuthStatus.unknown;
  bool get passwordRecoveryRequested => _passwordRecoveryRequested;

  Future<void> _restoreSession() async {
    _status = AuthStatus.loading;
    notifyListeners();

    try {
      final restoredUser = authRepository.isSignedIn
          ? await authRepository.loadCurrentUser()
          : null;
      _currentUser = restoredUser ?? authRepository.currentUser;
      _status = _currentUser != null
          ? AuthStatus.authenticated
          : AuthStatus.unauthenticated;
    } catch (_) {
      _currentUser = authRepository.currentUser;
      _status = _currentUser != null
          ? AuthStatus.authenticated
          : AuthStatus.unauthenticated;
    }

    notifyListeners();
  }

  // ─── Init ─────────────────────────────────────────────────────────────────

  void _init() {
    // Listen to Supabase auth state changes
    _authStateSubscription =
        authRepository.authStateChanges.listen((AuthState state) async {
      if (state.event == AuthChangeEvent.passwordRecovery) {
        _currentUser = null;
        _status = AuthStatus.unauthenticated;
        _passwordRecoveryRequested = true;
        _errorMessage = null;
      } else if (state.event == AuthChangeEvent.signedIn &&
          state.session != null) {
        try {
          _currentUser = await authRepository.loadCurrentUser() ??
              authRepository.currentUser;
        } catch (_) {
          _currentUser = authRepository.currentUser;
        }
        _status = _currentUser != null
            ? AuthStatus.authenticated
            : AuthStatus.unauthenticated;
      } else if (state.event == AuthChangeEvent.signedOut) {
        _currentUser = null;
        _status = AuthStatus.unauthenticated;
      }
      notifyListeners();
    });

    // Restore existing session
    _restoreSession();
  }

  @override
  void dispose() {
    _authStateSubscription?.cancel();
    super.dispose();
  }

  // ─── Email Auth ───────────────────────────────────────────────────────────

  Future<bool> signUp({
    required String email,
    required String password,
    required String fullName,
    String? barangay,
    required String municipality,
    required String province,
    required String country,
  }) async {
    _setLoading();
    final result = await authRepository.signUp(
      email: email,
      password: password,
      fullName: fullName,
      emailRedirectTo: _emailConfirmationRedirectUrl,
      barangay: barangay,
      municipality: municipality,
      province: province,
      country: country,
    );
    return _handleSignUpResult(result);
  }

  Future<bool> updateProfile({
    String? fullName,
    String? displayName,
    String? phone,
    String? barangay,
    required String municipality,
    required String province,
    required String country,
  }) async {
    try {
      final user = await authRepository.updateProfile(
        fullName: fullName,
        displayName: displayName,
        phone: phone,
        barangay: barangay,
        municipality: municipality,
        province: province,
        country: country,
      );
      _currentUser = user;
      _errorMessage = null;
      _infoMessage = 'Profile updated.';
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage =
          e is AuthException ? e.message : 'Could not update profile.';
      _infoMessage = null;
      notifyListeners();
      return false;
    }
  }

  Future<bool> requestEmailChange(String email) async {
    try {
      await authRepository.requestEmailChange(
        email,
        emailRedirectTo: _emailConfirmationRedirectUrl,
      );
      _errorMessage = null;
      _infoMessage = 'Check your email to confirm the new address.';
      notifyListeners();
      return true;
    } on AuthException catch (error) {
      _errorMessage = error.message;
      _infoMessage = null;
      notifyListeners();
      return false;
    } catch (_) {
      _errorMessage = 'Could not request the email change.';
      _infoMessage = null;
      notifyListeners();
      return false;
    }
  }

  Future<bool> signIn({
    required String email,
    required String password,
  }) async {
    _setLoading();
    final result =
        await authRepository.signIn(email: email, password: password);
    return _handleResult(result);
  }

  // ─── Sign Out ─────────────────────────────────────────────────────────────

  Future<void> signOut() async {
    _setLoading();
    await authRepository.signOut();
    _currentUser = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  Future<bool> deleteAccount(AiBackendService backend) async {
    _setLoading();
    try {
      await backend.deleteAccount();
      await authRepository.clearDeletedAccountFromDevice();
      _currentUser = null;
      _status = AuthStatus.unauthenticated;
      _errorMessage = null;
      _infoMessage = null;
      notifyListeners();
      return true;
    } catch (error) {
      _status = AuthStatus.authenticated;
      _errorMessage = error.toString();
      _infoMessage = null;
      notifyListeners();
      return false;
    }
  }

  // ─── Password Reset ───────────────────────────────────────────────────────

  Future<bool> sendPasswordReset(String email) async {
    _setLoading();
    try {
      await authRepository.sendPasswordReset(
        email,
        redirectTo: _passwordResetRedirectUrl,
      );
      _status = AuthStatus.unauthenticated;
      _errorMessage = null;
      _infoMessage = 'Check your email for the password reset link.';
      notifyListeners();
      return true;
    } on AuthException catch (error) {
      _setError(error.message);
      return false;
    } catch (_) {
      _setError('Could not send the password reset email. Please try again.');
      return false;
    }
  }

  Future<bool> updatePassword(String password) async {
    _setLoading();
    try {
      await authRepository.updatePassword(password);
      _currentUser =
          await authRepository.loadCurrentUser() ?? authRepository.currentUser;
      _status = _currentUser != null
          ? AuthStatus.authenticated
          : AuthStatus.unauthenticated;
      _passwordRecoveryRequested = false;
      _errorMessage = null;
      _infoMessage = 'Password updated successfully.';
      notifyListeners();
      return true;
    } on AuthException catch (error) {
      _setError(error.message);
      return false;
    } catch (_) {
      _setError('Could not update the password. Please request a new link.');
      return false;
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  String get _webRedirectUrl {
    final uri = Uri.base;
    final path = uri.path.isEmpty ? '/' : uri.path;
    return uri.replace(path: path, query: null, fragment: null).toString();
  }

  String get _passwordResetRedirectUrl =>
      kIsWeb ? _webRedirectUrl : AppConstants.passwordResetRedirectUrl;

  String get _emailConfirmationRedirectUrl =>
      kIsWeb ? _webRedirectUrl : AppConstants.emailConfirmationRedirectUrl;

  void _setLoading() {
    _status = AuthStatus.loading;
    _errorMessage = null;
    _infoMessage = null;
    notifyListeners();
  }

  void _setError(String message) {
    _status = AuthStatus.unauthenticated;
    _errorMessage = message;
    _infoMessage = null;
    notifyListeners();
  }

  bool _handleSignUpResult(AuthResult result) {
    if (result.success && result.requiresEmailConfirmation) {
      _currentUser = null;
      _status = AuthStatus.unauthenticated;
      _errorMessage = null;
      _infoMessage = result.message;
      notifyListeners();
      return true;
    }

    _infoMessage = null;
    return _handleResult(result);
  }

  bool _handleResult(AuthResult result) {
    if (result.success) {
      _currentUser = result.user;
      _status = AuthStatus.authenticated;
      _errorMessage = null;
      _infoMessage = result.message;
    } else {
      _status = AuthStatus.unauthenticated;
      _errorMessage = result.error;
      _infoMessage = null;
    }
    notifyListeners();
    return result.success;
  }

  void clearError() {
    _errorMessage = null;
    _infoMessage = null;
    notifyListeners();
  }

  void clearPasswordRecoveryRequest() {
    _passwordRecoveryRequested = false;
    notifyListeners();
  }
}
