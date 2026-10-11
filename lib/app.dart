import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'data/local/database_helper.dart';
import 'data/models/crop_model.dart';
import 'data/models/treatment_task_model.dart';
import 'data/remote/ai_backend_service.dart';
import 'data/remote/supabase_service.dart';
import 'data/repositories/auth_repository.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/auth/screens/reset_password_screen.dart';
import 'features/chat/providers/chat_provider.dart';
import 'features/crops/providers/crops_provider.dart';
import 'features/crops/screens/crop_detail_screen.dart';
import 'features/notifications/providers/notifications_provider.dart';
import 'features/splash/splash_screen.dart';
import 'services/connectivity_service.dart';
import 'services/local_classifier_service.dart';
import 'services/notification_service.dart';
import 'services/sync_service.dart';
import 'services/video_cleanup_service.dart';

class CropCareApp extends StatefulWidget {
  const CropCareApp({super.key, required this.authProvider});

  final AuthProvider authProvider;

  @override
  State<CropCareApp> createState() => _CropCareAppState();
}

class _CropCareAppState extends State<CropCareApp> {
  static final GlobalKey<NavigatorState> _navigatorKey =
      GlobalKey<NavigatorState>();

  StreamSubscription<String>? _tapSub;
  StreamSubscription<bool>? _backendConnectivitySub;
  StreamSubscription<bool>? _connectivityToastSub;
  AuthProvider? _authProvider;
  VoidCallback? _authWarmUpListener;
  OverlayEntry? _connectivityToast;
  Timer? _connectivityToastTimer;
  bool? _lastConnectivityState;
  bool _offlineBannerDismissed = false;
  bool _notificationPermissionRequested = false;
  String? _pendingNotificationPayload;
  bool _passwordRecoveryRouteOpen = false;

  @override
  void initState() {
    super.initState();
    // Subscribe lazily so the singleton has been created.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tapSub = NotificationService.instance.tapStream.listen(_handleTap);
      unawaited(_handleNotificationLaunch());
      _runVideoCleanup();
      _initializeBackendWarmUp();
      _initializeConnectivityStatus();
    });
  }

  Future<void> _handleNotificationLaunch() async {
    final payload =
        await NotificationService.instance.initializeAndGetLaunchPayload();
    if (payload != null && mounted) {
      _pendingNotificationPayload = payload;
      _schedulePendingNotificationTap();
    }
  }

  void _schedulePendingNotificationTap() {
    if (_pendingNotificationPayload == null ||
        !(_authProvider?.isAuthenticated ?? false)) {
      return;
    }
    Future<void>.delayed(const Duration(milliseconds: 850), () async {
      if (!mounted || !(_authProvider?.isAuthenticated ?? false)) return;
      final payload = _pendingNotificationPayload;
      _pendingNotificationPayload = null;
      if (payload != null) await _handleTap(payload);
    });
  }

  @override
  void dispose() {
    _tapSub?.cancel();
    _backendConnectivitySub?.cancel();
    _connectivityToastSub?.cancel();
    _connectivityToastTimer?.cancel();
    _connectivityToast?.remove();
    if (_authProvider != null && _authWarmUpListener != null) {
      _authProvider!.removeListener(_authWarmUpListener!);
    }
    super.dispose();
  }

  Future<void> _runVideoCleanup() async {
    try {
      final ctx = _navigatorKey.currentContext;
      if (ctx == null) return;
      final db = ctx.read<DatabaseHelper>();
      // Fire-and-forget; we never block UI on this.
      // ignore: discarded_futures
      VideoCleanupService(db: db).runIfDue();
    } catch (_) {/* defensive — never break app start */}
  }

  void _initializeBackendWarmUp() {
    final ctx = _navigatorKey.currentContext;
    if (ctx == null) return;

    final aiBackend = ctx.read<AiBackendService>();
    final connectivity = ctx.read<ConnectivityService>();
    final auth = ctx.read<AuthProvider>();

    Future<void> warmUpIfOnline({bool force = false}) async {
      if (!auth.isAuthenticated) {
        return;
      }
      if (!await connectivity.isConnected) {
        return;
      }
      await aiBackend.warmUpIfNeeded(force: force);
    }

    Future<void> initializeNotificationsIfAuthenticated() async {
      if (!auth.isAuthenticated || _notificationPermissionRequested) {
        return;
      }
      _notificationPermissionRequested = true;
      await NotificationService.instance.requestPermission();
    }

    _authProvider = auth;
    _authWarmUpListener = () {
      if (auth.passwordRecoveryRequested) {
        unawaited(_openPasswordRecovery(auth));
        return;
      }
      if (auth.isAuthenticated) {
        _schedulePendingNotificationTap();
        Future<void>.microtask(warmUpIfOnline);
        Future<void>.microtask(initializeNotificationsIfAuthenticated);
      }
    };
    auth.addListener(_authWarmUpListener!);

    _backendConnectivitySub =
        connectivity.onConnectivityChanged.listen((online) {
      if (!online || !auth.isAuthenticated) {
        return;
      }
      Future<void>.microtask(() => warmUpIfOnline(force: true));
    });

    Future<void>.microtask(warmUpIfOnline);
    Future<void>.microtask(initializeNotificationsIfAuthenticated);
    _schedulePendingNotificationTap();
    if (auth.passwordRecoveryRequested) {
      unawaited(_openPasswordRecovery(auth));
    }
  }

  Future<void> _openPasswordRecovery(AuthProvider auth) async {
    if (_passwordRecoveryRouteOpen) return;
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;

    _passwordRecoveryRouteOpen = true;
    auth.clearPasswordRecoveryRequest();
    await navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ResetPasswordScreen()),
      (_) => false,
    );
    _passwordRecoveryRouteOpen = false;
  }

  void _initializeConnectivityStatus() {
    final ctx = _navigatorKey.currentContext;
    if (ctx == null) return;
    final connectivity = ctx.read<ConnectivityService>();

    connectivity.isConnected.then((online) {
      if (!mounted) return;
      _lastConnectivityState = online;
      if (!online) {
        _showConnectivityToast(online: false);
      }
    });
    _connectivityToastSub = connectivity.onConnectivityChanged.listen((online) {
      if (!mounted || _lastConnectivityState == online) return;
      _lastConnectivityState = online;
      if (!online) _offlineBannerDismissed = false;
      _showConnectivityToast(online: online);
    });
  }

  void _showConnectivityToast({required bool online}) {
    if (!online && _offlineBannerDismissed) return;
    _connectivityToastTimer?.cancel();
    _connectivityToast?.remove();

    final overlay = _navigatorKey.currentState?.overlay;
    if (overlay == null) return;

    final color = online ? const Color(0xFF2E7D32) : const Color(0xFF3F4A43);
    _connectivityToast = OverlayEntry(
      builder: (context) => SafeArea(
        child: IgnorePointer(
          ignoring: online,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Align(
              alignment: Alignment.topCenter,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: const [
                      BoxShadow(color: Color(0x26000000), blurRadius: 6),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(
                        online ? Icons.cloud_done_outlined : Icons.cloud_off,
                        color: Colors.white,
                        size: 17,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        online ? 'Back online' : 'You are offline',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (!online) ...[
                        const Spacer(),
                        IconButton(
                          onPressed: _dismissOfflineBanner,
                          icon: const Icon(Icons.close),
                          tooltip: 'Dismiss offline status',
                          color: Colors.white,
                          iconSize: 18,
                          constraints: const BoxConstraints.tightFor(
                            width: 36,
                            height: 36,
                          ),
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_connectivityToast!);
    if (online) {
      _connectivityToastTimer = Timer(const Duration(seconds: 3), () {
        _connectivityToast?.remove();
        _connectivityToast = null;
      });
    }
  }

  void _dismissOfflineBanner() {
    _offlineBannerDismissed = true;
    _connectivityToast?.remove();
    _connectivityToast = null;
  }

  Future<void> _handleTap(String payload) async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    final ctx = navigator.context;

    // Read all providers synchronously before any await.
    final db = ctx.read<DatabaseHelper>();
    final cropsProvider = ctx.read<CropsProvider>();
    final auth = ctx.read<AuthProvider>();
    if (!auth.isAuthenticated) {
      _pendingNotificationPayload = payload;
      return;
    }

    if (payload.startsWith('crop:')) {
      final cropId = payload.substring('crop:'.length);
      if (cropId.isEmpty) return;
      CropModel? crop;
      for (final candidate in cropsProvider.crops) {
        if (candidate.id == cropId) {
          crop = candidate;
          break;
        }
      }
      if (crop == null) {
        final userId = auth.currentUser?.id;
        if (userId != null) await cropsProvider.fetchCrops(userId);
        if (!navigator.mounted) return;
        try {
          crop = cropsProvider.crops.firstWhere(
            (candidate) => candidate.id == cropId,
          );
        } catch (_) {
          _showSnack(navigator.context, 'Crop not found.');
          return;
        }
      }
      final resolvedCrop = crop;
      navigator.push(MaterialPageRoute(
        builder: (_) =>
            CropDetailScreen(crop: resolvedCrop, initialTabIndex: 1),
      ));
      return;
    }

    if (!payload.startsWith('task:')) return;
    final taskId = payload.substring('task:'.length);
    if (taskId.isEmpty) return;

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
    CropModel? crop;
    for (final candidate in cropsProvider.crops) {
      if (candidate.id == task.cropId && !candidate.isDeleted) {
        crop = candidate;
        break;
      }
    }
    if (crop == null) {
      final userId = auth.currentUser?.id;
      if (userId != null) await cropsProvider.fetchCrops(userId);
      if (!navigator.mounted) return;
      for (final candidate in cropsProvider.crops) {
        if (candidate.id == task.cropId && !candidate.isDeleted) {
          crop = candidate;
          break;
        }
      }
      if (crop == null) {
        _showSnack(navigator.context, 'Crop not found.');
        return;
      }
    }

    final resolvedCrop = crop;
    final localDueAt = task.dueAt.toLocal();

    navigator.push(
      MaterialPageRoute(
        builder: (_) => CropDetailScreen(
          crop: resolvedCrop,
          initialTabIndex: 1, // Progress tab
          initialSelectedDate: DateTime(
            localDueAt.year,
            localDueAt.month,
            localDueAt.day,
          ),
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
        ChangeNotifierProvider<AuthProvider>.value(
          value: widget.authProvider,
        ),

        // Crops
        ChangeNotifierProxyProvider3<SupabaseService, DatabaseHelper,
            SyncService, CropsProvider>(
          create: (ctx) => CropsProvider(
            supabase: ctx.read<SupabaseService>(),
            db: ctx.read<DatabaseHelper>(),
            sync: ctx.read<SyncService>(),
          ),
          update: (_, svc, db, sync, prev) =>
              prev ??
              CropsProvider(
                supabase: svc,
                db: db,
                sync: sync,
              ),
        ),

        // Notifications
        ChangeNotifierProxyProvider3<SupabaseService, DatabaseHelper,
            SyncService, NotificationsProvider>(
          create: (ctx) => NotificationsProvider(
            supabase: ctx.read<SupabaseService>(),
            db: ctx.read<DatabaseHelper>(),
            sync: ctx.read<SyncService>(),
          ),
          update: (_, svc, db, sync, prev) =>
              prev ??
              NotificationsProvider(
                supabase: svc,
                db: db,
                sync: sync,
              ),
        ),

        // Chat / AI
        ChangeNotifierProxyProvider5<SupabaseService, DatabaseHelper,
            AiBackendService, ConnectivityService, SyncService, ChatProvider>(
          create: (ctx) => ChatProvider(
            supabase: ctx.read<SupabaseService>(),
            db: ctx.read<DatabaseHelper>(),
            aiBackend: ctx.read<AiBackendService>(),
            connectivity: ctx.read<ConnectivityService>(),
            sync: ctx.read<SyncService>(),
          ),
          update: (_, svc, db, aiBackend, connectivity, sync, prev) =>
              prev ??
              ChatProvider(
                supabase: svc,
                db: db,
                aiBackend: aiBackend,
                connectivity: connectivity,
                sync: sync,
              ),
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
