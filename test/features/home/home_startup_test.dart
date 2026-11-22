import 'package:cropcare_ai/data/models/crop_model.dart';
import 'package:cropcare_ai/data/models/disease_knowledge_model.dart';
import 'package:cropcare_ai/data/models/treatment_task_model.dart';
import 'package:cropcare_ai/data/models/user_model.dart';
import 'package:cropcare_ai/features/auth/providers/auth_provider.dart';
import 'package:cropcare_ai/features/chat/providers/chat_provider.dart';
import 'package:cropcare_ai/features/crops/providers/crops_provider.dart';
import 'package:cropcare_ai/features/home/home_screen.dart';
import 'package:cropcare_ai/features/notifications/providers/notifications_provider.dart';
import 'package:cropcare_ai/features/scan/scan_screen.dart';
import 'package:cropcare_ai/services/connectivity_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Auth extends ChangeNotifier implements AuthProvider {
  @override
  UserModel get currentUser =>
      const UserModel(id: 'first-user', email: 'test@example.com');
  @override
  bool get isLoading => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Crops extends ChangeNotifier implements CropsProvider {
  @override
  List<CropModel> get activeCrops => [];
  @override
  List<CropModel> get completedCrops => [];
  @override
  bool get isLoading => false;
  @override
  Future<void> fetchCrops(String userId) async {}
  @override
  Future<List<DiseaseKnowledgeModel>> fetchDiseaseKnowledge(
          {String? cropType}) async =>
      [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Notifications extends ChangeNotifier implements NotificationsProvider {
  @override
  int get unreadCount => 0;
  @override
  List<TreatmentTaskModel> get todayTasks => [];
  @override
  List<TreatmentTaskModel> get missedTasks => [];
  @override
  Future<void> fetchAll(String userId) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Chat extends ChangeNotifier implements ChatProvider {
  @override
  Future<void> fetchSessions(String userId) async {}
  @override
  Future<void> loadKnowledgeBase() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Connectivity implements ConnectivityService {
  @override
  Stream<bool> get onConnectivityChanged => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('fresh dashboard displays tour without creating a hidden scanner',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth()),
      ChangeNotifierProvider<CropsProvider>(create: (_) => _Crops()),
      ChangeNotifierProvider<NotificationsProvider>(
          create: (_) => _Notifications()),
      ChangeNotifierProvider<ChatProvider>(create: (_) => _Chat()),
      Provider<ConnectivityService>(create: (_) => _Connectivity()),
    ], child: const MaterialApp(home: HomeScreen())));
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(ScanScreen, skipOffstage: false), findsNothing);
    expect(find.text('Welcome to CropCare AI'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
