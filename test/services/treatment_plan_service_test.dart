import 'package:cropcare_ai/data/models/disease_treatment_day_step_model.dart';
import 'package:cropcare_ai/services/treatment_plan_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TreatmentPlanService', () {
    final start = DateTime(2026, 7, 27, 14, 30);

    test('expands labeled product timing and daily care across the full plan',
        () {
      final plan = TreatmentPlanService.build(
        startDate: start,
        expectedDurationDays: 14,
        treatmentSteps: const [
          'Apply a copper-based bactericide every 5 to 7 days.',
          'Keep irrigation at the base of the plant instead of overhead watering.',
        ],
      );

      final productTasks = plan.tasks
          .where((task) => task.title.startsWith('Apply a copper-based'))
          .toList();
      final irrigationTasks = plan.tasks
          .where((task) => task.title.startsWith('Keep irrigation'))
          .toList();

      expect(plan.durationDays, 14);
      expect(productTasks.map((task) => task.day), [1, 8]);
      expect(irrigationTasks, hasLength(14));
      expect(irrigationTasks.last.day, 14);
      expect(productTasks.first.description, contains('follow its label'));
    });

    test('keeps one-time sanitation work on the first treatment day only', () {
      final plan = TreatmentPlanService.build(
        startDate: start,
        expectedDurationDays: 7,
        treatmentSteps: const [
          'Remove and destroy infected leaves.',
        ],
      );

      final sanitationTasks = plan.tasks
          .where((task) => task.title.startsWith('Remove and destroy'))
          .toList();
      final observationTasks = plan.tasks
          .where((task) => task.title.startsWith('Inspect the plant'))
          .toList();

      expect(sanitationTasks, hasLength(1));
      expect(sanitationTasks.single.day, 1);
      expect(observationTasks, hasLength(7));
    });

    test('groups each reviewed protocol day into one detailed task', () {
      final steps = List.generate(
        14,
        (index) {
          final day = index + 1;
          return DiseaseTreatmentDayStepModel(
            id: 'day-$day',
            diseaseKnowledgeBaseId: 'knowledge-1',
            dayNumber: day,
            dayTitle: day == 1
                ? 'Initial inspection'
                : day == 14
                    ? 'Final reassessment'
                    : 'Daily care',
            tasks: day == 1
                ? ['Inspect lower leaves.', 'Take a starting photo.']
                : day == 14
                    ? ['Upload a follow-up image.']
                    : ['Complete the reviewed daily care steps.'],
            notes:
                day == 1 ? 'Record current spread before changing care.' : null,
          );
        },
      );

      final plan = TreatmentPlanService.buildFromDaySteps(
        daySteps: steps,
        startDate: start,
        expectedDurationDays: 14,
      );

      expect(
        TreatmentPlanService.coversExpectedDuration(
          daySteps: steps,
          expectedDurationDays: 14,
        ),
        isTrue,
      );
      expect(plan.tasks, hasLength(14));
      expect(plan.tasks.first.title, 'Day 1: Initial inspection');
      expect(plan.tasks.first.description, contains('Inspect lower leaves.'));
      expect(plan.tasks.first.description, contains('Why this matters:'));
      expect(plan.tasks.last.day, 14);
    });

    test('rejects an incomplete protocol for a longer treatment duration', () {
      const partialSteps = [
        DiseaseTreatmentDayStepModel(
          id: 'day-1',
          diseaseKnowledgeBaseId: 'knowledge-1',
          dayNumber: 1,
          dayTitle: 'Initial inspection',
          tasks: ['Inspect affected leaves.'],
        ),
        DiseaseTreatmentDayStepModel(
          id: 'day-6',
          diseaseKnowledgeBaseId: 'knowledge-1',
          dayNumber: 6,
          dayTitle: 'Sanitation check',
          tasks: ['Remove fallen debris.'],
        ),
      ];

      expect(
        TreatmentPlanService.coversExpectedDuration(
          daySteps: partialSteps,
          expectedDurationDays: 14,
        ),
        isFalse,
      );
    });

    test('rejects a protocol that skips an intermediate treatment day', () {
      const sparseSteps = [
        DiseaseTreatmentDayStepModel(
          id: 'day-1',
          diseaseKnowledgeBaseId: 'knowledge-1',
          dayNumber: 1,
          dayTitle: 'Initial inspection',
          tasks: ['Inspect affected leaves.'],
        ),
        DiseaseTreatmentDayStepModel(
          id: 'day-3',
          diseaseKnowledgeBaseId: 'knowledge-1',
          dayNumber: 3,
          dayTitle: 'Follow-up inspection',
          tasks: ['Check for spreading symptoms.'],
        ),
        DiseaseTreatmentDayStepModel(
          id: 'day-14',
          diseaseKnowledgeBaseId: 'knowledge-1',
          dayNumber: 14,
          dayTitle: 'Final reassessment',
          tasks: ['Upload a follow-up image.'],
        ),
      ];

      expect(
        TreatmentPlanService.coversExpectedDuration(
          daySteps: sparseSteps,
          expectedDurationDays: 14,
        ),
        isFalse,
      );
    });
  });
}
