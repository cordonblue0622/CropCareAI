import 'package:cropcare_ai/services/treatment_action_parser.dart';
import 'package:cropcare_ai/services/treatment_plan_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TreatmentActionParser', () {
    test('keeps numbered instructions and their additional sentences together',
        () {
      final actions = TreatmentActionParser.split(
        '1. Remove infected lower leaves. Bag them and discard them; do not compost them. '
        '2. Inspect fresh leaves every day. '
        '3. Apply the labeled treatment only as directed.',
      );

      expect(actions, [
        '1. Remove infected lower leaves. Bag them and discard them; do not compost them.',
        '2. Inspect fresh leaves every day.',
        '3. Apply the labeled treatment only as directed.',
      ]);
      expect(actions, isNot(contains('1.')));
      expect(actions, isNot(contains('2.')));
      expect(actions, isNot(contains('3.')));
    });

    test('supports numbered parentheses and legacy unnumbered prose', () {
      expect(
        TreatmentActionParser.split(
          '1) Remove damaged leaves.\n2) Water at the base.\n3) Inspect new growth.',
        ),
        [
          '1) Remove damaged leaves.',
          '2) Water at the base.',
          '3) Inspect new growth.',
        ],
      );
      expect(
        TreatmentActionParser.split(
          'Remove damaged leaves. Avoid overhead watering!',
        ),
        ['Remove damaged leaves.', 'Avoid overhead watering!'],
      );
    });

    test('normalization rejects placeholders but preserves real history', () {
      expect(
        TreatmentActionParser.normalize(const [
          '1.',
          'Remove infected leaves.',
          '2)',
          '  Remove   infected leaves. ',
          '3. Inspect leaves daily.',
        ]),
        ['Remove infected leaves.', '3. Inspect leaves daily.'],
      );
    });

    test('plan creation never emits number-only task titles or empty details',
        () {
      final plan = TreatmentPlanService.build(
        treatmentSteps: const [
          '1.',
          '2.',
          '3.',
          'Bag them and discard them; do not compost them.',
        ],
        startDate: DateTime(2026, 11, 1, 9),
        expectedDurationDays: 7,
      );

      expect(plan.tasks, isNotEmpty);
      for (final task in plan.tasks) {
        expect(TreatmentActionParser.isMeaningful(task.title), isTrue);
        expect(task.description.trim(), isNotEmpty);
      }
      expect(
        plan.tasks.any((task) => task.title.startsWith('Bag them and discard')),
        isTrue,
      );
    });
  });
}
