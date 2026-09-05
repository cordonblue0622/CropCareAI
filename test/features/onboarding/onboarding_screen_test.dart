import 'package:cropcare_ai/features/onboarding/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('moves through onboarding with button and swipe', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: OnboardingScreen()),
    );

    expect(find.text('See crop problems\nmore clearly.'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Onboarding step 1 of 3'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('onboarding_next_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    expect(
      find.text('Your crop assistant,\nready in the field.'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Onboarding step 2 of 3'),
      findsOneWidget,
    );

    await tester.fling(
      find.byType(PageView),
      const Offset(-800, 0),
      1200,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    expect(
      find.text('Turn guidance into\nsteady recovery.'),
      findsOneWidget,
    );
    expect(find.text('Start growing'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Onboarding step 3 of 3'),
      findsOneWidget,
    );
  });
}
