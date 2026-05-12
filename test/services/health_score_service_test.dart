import 'package:flutter_test/flutter_test.dart';
import 'package:cropcare_ai/core/constants/app_enums.dart';
import 'package:cropcare_ai/data/models/diagnosis_model.dart';
import 'package:cropcare_ai/data/models/treatment_task_model.dart';
import 'package:cropcare_ai/services/health_score_service.dart';

void main() {
  group('HealthScoreService.compute14DayCurve', () {
    final today = DateTime(2026, 5, 8);

    TreatmentTaskModel task({
      required String id,
      required DateTime dueAt,
      DateTime? completedAt,
    }) =>
        TreatmentTaskModel(
          id: id,
          treatmentId: 't',
          cropId: 'c',
          userId: 'u',
          title: 'Task $id',
          dueAt: dueAt,
          completedAt: completedAt,
          status: completedAt != null ? TaskStatus.completed : TaskStatus.pending,
          createdAt: dueAt,
          updatedAt: completedAt ?? dueAt,
        );

    DiagnosisModel diagnosis({
      required String id,
      required Severity severity,
      required DateTime diagnosedAt,
    }) =>
        DiagnosisModel(
          id: id,
          cropId: 'c',
          userId: 'u',
          diagnosisMode: DiagnosisMode.online,
          diseaseName: 'd',
          severity: severity,
          diagnosedAt: diagnosedAt,
          createdAt: diagnosedAt,
          updatedAt: diagnosedAt,
        );

    test('empty inputs → 14 points all at 100, status insufficientData', () {
      final curve = HealthScoreService.compute14DayCurve(
        tasks: const [],
        diagnoses: const [],
        now: today,
      );
      expect(curve.length, 14);
      expect(curve.every((p) => p.score == 100), isTrue);
      expect(curve.every((p) => p.status == ProgressStatus.insufficientData),
          isTrue);
      expect(curve.first.date, today.subtract(const Duration(days: 13)));
      expect(curve.last.date, today);
    });

    test('one severe diagnosis on day 0, no tasks → all 14 points at 55', () {
      final curve = HealthScoreService.compute14DayCurve(
        tasks: const [],
        diagnoses: [
          diagnosis(
              id: 'dx', severity: Severity.severe, diagnosedAt: today.subtract(const Duration(days: 13))),
        ],
        now: today,
      );
      expect(curve.every((p) => p.score == 55), isTrue,
          reason: 'baseScore 100 minus severe penalty 45 = 55');
    });

    test('100% completion, mild diagnosis → score climbs from 90 to 90', () {
      final tasks = [
        task(
            id: 't1',
            dueAt: today.subtract(const Duration(days: 10)),
            completedAt: today.subtract(const Duration(days: 10))),
        task(
            id: 't2',
            dueAt: today.subtract(const Duration(days: 5)),
            completedAt: today.subtract(const Duration(days: 5))),
      ];
      final diagnoses = [
        diagnosis(
            id: 'dx', severity: Severity.mild, diagnosedAt: today.subtract(const Duration(days: 13))),
      ];
      final curve = HealthScoreService.compute14DayCurve(
        tasks: tasks,
        diagnoses: diagnoses,
        now: today,
      );
      // Days before first due: totalTasks=0 → baseScore=100, minus mild 10 → 90.
      // Days after first due (with all completed): baseScore=100, minus 10 → 90.
      expect(curve.every((p) => p.score == 90), isTrue);
    });

    test('mix of completed and missed → score reflects ratio', () {
      final tasks = [
        task(
            id: 't1',
            dueAt: today.subtract(const Duration(days: 5)),
            completedAt: today.subtract(const Duration(days: 5))),
        task(
            id: 't2',
            dueAt: today.subtract(const Duration(days: 5))),
        task(
            id: 't3',
            dueAt: today.subtract(const Duration(days: 5))),
        task(
            id: 't4',
            dueAt: today.subtract(const Duration(days: 5))),
      ];
      final curve = HealthScoreService.compute14DayCurve(
        tasks: tasks,
        diagnoses: const [],
        now: today,
      );
      // From day-5 onward: 1 completed of 4 due → 25.
      final last = curve.last;
      expect(last.score, 25);
      expect(last.completedTasks, 1);
      expect(last.totalTasks, 4);
    });

    test('score is clamped to [0, 100]', () {
      // Severe diagnosis (-45) + 0% completion (-100 from base = 0) cannot go negative.
      final tasks = [
        task(id: 't', dueAt: DateTime(2026, 5, 1)),
      ];
      final curve = HealthScoreService.compute14DayCurve(
        tasks: tasks,
        diagnoses: [
          diagnosis(
              id: 'dx', severity: Severity.severe, diagnosedAt: DateTime(2026, 4, 26)),
        ],
        now: today,
      );
      expect(curve.every((p) => p.score >= 0 && p.score <= 100), isTrue);
    });

    test('progress status reflects 3-day delta', () {
      // 4 tasks all completed by day -3, then no new tasks. Curve should be flat → stable.
      final tasks = List.generate(
          4,
          (i) => task(
              id: 't$i',
              dueAt: today.subtract(const Duration(days: 5)),
              completedAt: today.subtract(const Duration(days: 5))));
      final curve = HealthScoreService.compute14DayCurve(
        tasks: tasks,
        diagnoses: const [],
        now: today,
      );
      expect(curve.last.status, ProgressStatus.stable);
    });
  });
}
