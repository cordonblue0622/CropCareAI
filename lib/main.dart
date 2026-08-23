import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'core/constants/app_constants.dart';
import 'data/local/database_helper.dart';
import 'data/remote/supabase_service.dart';
import 'data/repositories/auth_repository.dart';
import 'features/auth/providers/auth_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise Supabase (replace URL and key in app_constants.dart)
  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    anonKey: AppConstants.supabaseAnonKey,
  );

  final authProvider = AuthProvider(
    authRepository: AuthRepository(
      supabaseService: SupabaseService(),
      dbHelper: DatabaseHelper.instance,
    ),
  );

  // SQLite is disabled on web; mobile/desktop still warm up the local cache.
  if (!kIsWeb) {
    await DatabaseHelper.instance.database;
  }

  runApp(CropCareApp(authProvider: authProvider));
}
