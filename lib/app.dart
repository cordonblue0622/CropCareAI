import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'data/local/database_helper.dart';
import 'data/remote/ai_backend_service.dart';
import 'data/remote/supabase_service.dart';
import 'data/repositories/auth_repository.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/crops/providers/crops_provider.dart';
import 'features/notifications/providers/notifications_provider.dart';
import 'features/chat/providers/chat_provider.dart';
import 'features/splash/splash_screen.dart';
import 'services/connectivity_service.dart';
import 'services/local_classifier_service.dart';
import 'services/sync_service.dart';

class CropCareApp extends StatelessWidget {
  const CropCareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Core services
        Provider<SupabaseService>(create: (_) => SupabaseService()),
        ProxyProvider<SupabaseService, AiBackendService>(
          update: (_, supabase, __) => AiBackendService(supabase: supabase),
        ),
        Provider<LocalClassifierService>(
          create: (_) => LocalClassifierService(),
        ),
        Provider<DatabaseHelper>(create: (_) => DatabaseHelper.instance),
        Provider<ConnectivityService>(create: (_) => ConnectivityService()),

        // Repository
        ProxyProvider2<SupabaseService, DatabaseHelper, AuthRepository>(
          update: (_, svc, db, __) =>
              AuthRepository(supabaseService: svc, dbHelper: db),
        ),

        // Sync service (auto-listens for connectivity)
        ProxyProvider2<SupabaseService, DatabaseHelper, SyncService>(
          update: (_, svc, db, previous) =>
              previous ?? SyncService(supabaseService: svc, dbHelper: db),
        ),

        // Auth state
        ChangeNotifierProxyProvider<AuthRepository, AuthProvider>(
          create: (ctx) =>
              AuthProvider(authRepository: ctx.read<AuthRepository>()),
          update: (_, repo, prev) => prev ?? AuthProvider(authRepository: repo),
        ),

        // Crops
        ChangeNotifierProxyProvider2<SupabaseService, DatabaseHelper,
            CropsProvider>(
          create: (ctx) => CropsProvider(
            supabase: ctx.read<SupabaseService>(),
            db: ctx.read<DatabaseHelper>(),
          ),
          update: (_, svc, db, prev) =>
              prev ?? CropsProvider(supabase: svc, db: db),
        ),

        // Notifications
        ChangeNotifierProxyProvider2<SupabaseService, DatabaseHelper,
            NotificationsProvider>(
          create: (ctx) => NotificationsProvider(
            supabase: ctx.read<SupabaseService>(),
            db: ctx.read<DatabaseHelper>(),
          ),
          update: (_, svc, db, prev) =>
              prev ?? NotificationsProvider(supabase: svc, db: db),
        ),

        // Chat / AI
        ChangeNotifierProxyProvider3<SupabaseService, DatabaseHelper,
            AiBackendService, ChatProvider>(
          create: (ctx) => ChatProvider(
            supabase: ctx.read<SupabaseService>(),
            db: ctx.read<DatabaseHelper>(),
            aiBackend: ctx.read<AiBackendService>(),
          ),
          update: (_, svc, db, aiBackend, prev) =>
              prev ?? ChatProvider(supabase: svc, db: db, aiBackend: aiBackend),
        ),
      ],
      child: MaterialApp(
        title: 'CropCare AI',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.theme,
        home: const SplashScreen(),
      ),
    );
  }
}
