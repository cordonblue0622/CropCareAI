import 'package:cropcare_ai/features/onboarding/guided_tour/guided_tour_host.dart';
import 'package:cropcare_ai/features/onboarding/guided_tour/guided_tour_overlay.dart';
import 'package:cropcare_ai/features/onboarding/guided_tour/guided_tour_service.dart';
import 'package:cropcare_ai/features/onboarding/guided_tour/guided_tour_targets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Next and Back change steps and tabs; Skip persists dismissal',
      (tester) async {
    final selectedTabs = <int>[];
    await _pumpTour(tester, onSelectTab: selectedTabs.add);

    expect(find.text('Welcome to CropCare AI'), findsOneWidget);
    for (var index = 0; index < 4; index++) {
      await _advance(tester);
    }
    expect(find.text('Manage My Crops'), findsOneWidget);
    expect(selectedTabs.last, 1);

    await _advance(tester);
    expect(find.text('Follow daily tasks'), findsOneWidget);
    expect(selectedTabs.last, 0);

    await tester.tap(find.byKey(GuidedTourOverlay.backButtonKey));
    await tester.pumpAndSettle();
    expect(find.text('Manage My Crops'), findsOneWidget);
    expect(selectedTabs.last, 1);

    await tester.tap(find.byKey(GuidedTourOverlay.skipButtonKey));
    await tester.pumpAndSettle();
    expect(find.byKey(GuidedTourOverlay.cardKey), findsNothing);
    expect(await const GuidedTourService().isComplete('test-user'), isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await _pumpTour(tester, onSelectTab: selectedTabs.add);
    expect(find.byKey(GuidedTourOverlay.cardKey), findsNothing);
  });

  testWidgets('Get Started completes and manual replay starts over',
      (tester) async {
    final hostKey = GlobalKey<GuidedTourHostState>();
    await _pumpTour(tester, hostKey: hostKey);

    for (var index = 0; index < GuidedTourSteps.values.length - 1; index++) {
      await _advance(tester);
    }
    expect(find.text('You’re all set!'), findsOneWidget);
    expect(find.byKey(GuidedTourOverlay.skipButtonKey), findsNothing);

    await tester.tap(find.byKey(GuidedTourOverlay.finishButtonKey));
    await tester.pumpAndSettle();
    expect(find.byKey(GuidedTourOverlay.cardKey), findsNothing);
    expect(await const GuidedTourService().isComplete('test-user'), isTrue);

    final replay = hostKey.currentState!.startTour();
    await tester.pumpAndSettle();
    await replay;
    expect(find.text('Welcome to CropCare AI'), findsOneWidget);
    expect(find.text('Step 1 of 9'), findsOneWidget);
  });

  testWidgets('a completed user does not see the automatic tour',
      (tester) async {
    await const GuidedTourService().markComplete('test-user');

    await _pumpTour(tester);

    expect(find.byKey(GuidedTourOverlay.cardKey), findsNothing);
  });

  testWidgets('cards stay on a small screen and clear every highlighted target',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pumpTour(tester, textScale: 1.15);

    for (var index = 0; index < GuidedTourSteps.values.length; index++) {
      final card = tester.getRect(find.byKey(GuidedTourOverlay.cardKey));
      expect(card.left, greaterThanOrEqualTo(0));
      expect(card.top, greaterThanOrEqualTo(0));
      expect(card.right, lessThanOrEqualTo(320));
      expect(card.bottom, lessThanOrEqualTo(568));

      final buttonKey = index == GuidedTourSteps.values.length - 1
          ? GuidedTourOverlay.finishButtonKey
          : GuidedTourOverlay.nextButtonKey;
      final button = tester.getRect(find.byKey(buttonKey));
      expect(button.top, greaterThanOrEqualTo(card.top));
      expect(button.bottom, lessThanOrEqualTo(card.bottom));

      final targetKey = GuidedTourSteps.values[index].targetKey;
      if (targetKey != null) {
        final target = tester.getRect(find.byKey(targetKey));
        expect(
          card.overlaps(target),
          isFalse,
          reason: 'Step ${index + 1} card overlaps its target',
        );
      }

      if (index < GuidedTourSteps.values.length - 1) {
        await _advance(tester);
      }
    }
  });
}

Future<void> _advance(WidgetTester tester) async {
  await tester.tap(find.byKey(GuidedTourOverlay.nextButtonKey));
  await tester.pumpAndSettle();
}

Future<void> _pumpTour(
  WidgetTester tester, {
  GlobalKey<GuidedTourHostState>? hostKey,
  ValueChanged<int>? onSelectTab,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: GuidedTourHost(
          key: hostKey,
          userId: 'test-user',
          onSelectTab: onSelectTab ?? (_) {},
          child: Scaffold(body: _TourTargets()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _TourTargets extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: 24,
          left: 16,
          right: 16,
          child: _target(AppTourKeys.dashboardWelcome, height: 56),
        ),
        Positioned(
          top: 190,
          left: 24,
          right: 24,
          child: _target(AppTourKeys.dashboardOverview, height: 90),
        ),
        Positioned(
          left: 125,
          bottom: 16,
          child: _target(AppTourKeys.scanNavigation, width: 70, height: 60),
        ),
        Positioned(
          right: 20,
          bottom: 100,
          child: _target(AppTourKeys.cropDoctor, width: 56, height: 56),
        ),
        Positioned(
          top: 24,
          left: 20,
          right: 20,
          child: _target(AppTourKeys.myCropsAppBar, height: 56),
        ),
        Positioned(
          top: 350,
          left: 24,
          right: 24,
          child: _target(AppTourKeys.dailyTasks, height: 80),
        ),
        Positioned(
          top: 32,
          right: 24,
          child: _target(AppTourKeys.notifications, width: 48, height: 48),
        ),
        Positioned(
          top: 100,
          left: 20,
          right: 20,
          child: _target(AppTourKeys.accountHeader, height: 70),
        ),
      ],
    );
  }

  Widget _target(
    GlobalKey key, {
    double? width,
    required double height,
  }) {
    return Container(
      key: key,
      width: width,
      height: height,
      color: const Color(0xFFD4EDCD),
    );
  }
}
