import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'data/local/database_helper.dart';
import 'data/models/treatment_task_model.dart';
import 'data/remote/ai_backend_service.dart';
import 'data/remote/supabase_service.dart';
import 'data/repositories/auth_repository.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/chat/providers/chat_provider.dart';
import 'features/crops/providers/crops_provider.dart';
import 'features/crops/screens/crop_detail_screen.dart';
import 'features/notifications/providers/notifications_provider.dart';
import 'features/splash/splash_screen.dart';
import 'services/connectivity_service.dart';
import 'services/local_classifier_service.dart';
import 'services/notification_service.dart';
import 'services/sync_service.dart';

class CropCareApp extends StatefulWidget {
  const CropCareApp({super.key});

  @override
  State<CropCareApp> createState() => _CropCareAppState();
}

class _CropCareAppState extends State<CropCareApp> {
  static final GlobalKey<NavigatorState> _navigatorKey =
      GlobalKey<NavigatorState>();

  StreamSubscription<String>? _tapSub;

  @override
  void initState() {
    super.initState();
    // Subscribe lazily so the singleton has been created.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tapSub = NotificationService.instance.tapStream.listen(_handleTap);
    });
  }

  @override
  void dispose() {
    _tapSub?.cancel();
    super.dispose();
  }

  Future<void> _handleTap(String payload) async {
    // Phase 1 payload format: "task:<taskId>"
    if (!payload.startsWith('task:')) return;
    final taskId = payload.substring('task:'.length);
    if (taskId.isEmpty) return;

    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    final ctx = navigator.context;

    // Read all providers synchronously before any await.
    final db = ctx.read<DatabaseHelper>();
    final cropsProvider = ctx.read<CropsProvider>();
    final auth = ctx.read<AuthProvider>();

    Map<String, dynamic>? row;
    try {
      final database = await db.database;
      final rows = await database.query(
        AppConstants.treatmentTasksTable,
        where: 'id = ?',
        whereArgs: [taskId],
        limit: 1,
      );
      if (rows.isNotEmpty) row = rows.first;
    } catch (_) {/* fall through */}

    if (!navigator.mounted) return;
    if (row == null) {
      _showSnack(navigator.context, 'Task not found.');
      return;
    }
    final task = TreatmentTaskModel.fromMap(row);

    // Find the crop. Refresh once if not present.
    var crop = cropsProvider.activeCrops.firstWhere(
      (c) => c.id == task.cropId,
      orElse: () => cropsProvider.crops.firstWhere(
        (c) => c.id == task.cropId,
        orElse: () => cropsProvider.crops.isNotEmpty
            ? cropsProvider.crops.first
            : throw StateError('No crops loaded'),
      ),
    );
    if (crop.id != task.cropId) {
      // The fallback returned an unrelated crop; try a refresh.
      final userId = auth.currentUser?.id;
      if (userId != null) {
        await cropsProvider.fetchCrops(userId);
      }
      if (!navigator.mounted) return;
      try {
        crop = cropsProvider.crops.firstWhere((c) => c.id == task.cropId);
      } catch (_) {
        _showSnack(navigator.context, 'Crop not found.');
        return;
      }
    }

    navigator.push(
      MaterialPageRoute(
        builder: (_) => CropDetailScreen(
          crop: crop,
          initialTabIndex: 1, // Progress tab
          initialSelectedDate: DateTime(
              task.dueAt.year, task.dueAt.month, task.dueAt.day),
        ),
      ),
    );
  }

  void _showSnack(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

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
        navigatorKey: _navigatorKey,
        home: const SplashScreen(),
      ),
    );
  }
}
