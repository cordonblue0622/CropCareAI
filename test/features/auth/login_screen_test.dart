import 'package:cropcare_ai/core/constants/app_constants.dart';
import 'package:cropcare_ai/data/local/database_helper.dart';
import 'package:cropcare_ai/data/models/user_model.dart';
import 'package:cropcare_ai/data/remote/supabase_service.dart';
import 'package:cropcare_ai/data/repositories/auth_repository.dart';
import 'package:cropcare_ai/features/auth/providers/auth_provider.dart';
import 'package:cropcare_ai/features/auth/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _SuccessfulAuthRepository extends AuthRepository {
  _SuccessfulAuthRepository()
      : super(
          supabaseService: SupabaseService(),
          dbHelper: DatabaseHelper.instance,
        );

  @override
  Stream<AuthState> get authStateChanges => const Stream<AuthState>.empty();

  @override
  bool get isSignedIn => false;

  @override
  UserModel? get currentUser => null;

  @override
  Future<UserModel?> loadCurrentUser() async => null;

  @override
  Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async =>
      const AuthResult(
        success: true,
        user: UserModel(id: 'test-user', email: 'farmer@example.com'),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      anonKey: AppConstants.supabaseAnonKey,
    );
  });

  testWidgets('offers email authentication without social providers',
      (tester) async {
    final authProvider = AuthProvider(
      authRepository: AuthRepository(
        supabaseService: SupabaseService(),
        dbHelper: DatabaseHelper.instance,
      ),
    );
    addTearDown(authProvider.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: authProvider,
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Sign In'), findsOneWidget);
    expect(find.text('Create an account'), findsOneWidget);
    expect(find.text('Google'), findsNothing);
    expect(find.text('Facebook'), findsNothing);
    expect(find.text('OR CONTINUE WITH'), findsNothing);
  });

  testWidgets('routes each successful login to one dashboard', (tester) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final authProvider = AuthProvider(
        authRepository: _SuccessfulAuthRepository(),
      );
      addTearDown(authProvider.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>.value(
          value: authProvider,
          child: MaterialApp(
            home: LoginScreen(
              homeScreenBuilder: (_) => const Scaffold(
                body: Text('Dashboard test destination'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        await authProvider.signIn(
          email: 'farmer@example.com',
          password: 'password',
        ),
        isTrue,
      );
      await tester.pumpAndSettle();

      expect(find.text('Dashboard test destination'), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
    }
  });
}
