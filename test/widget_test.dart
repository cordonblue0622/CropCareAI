// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cropcare_ai/app.dart';
import 'package:cropcare_ai/core/constants/app_constants.dart';
import 'package:cropcare_ai/data/local/database_helper.dart';
import 'package:cropcare_ai/data/remote/supabase_service.dart';
import 'package:cropcare_ai/data/repositories/auth_repository.dart';
import 'package:cropcare_ai/features/auth/providers/auth_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      anonKey: AppConstants.supabaseAnonKey,
    );
  });

  testWidgets('App builds smoke test', (WidgetTester tester) async {
    final authProvider = AuthProvider(
      authRepository: AuthRepository(
        supabaseService: SupabaseService(),
        dbHelper: DatabaseHelper.instance,
      ),
    );
    await tester.pumpWidget(CropCareApp(authProvider: authProvider));
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
