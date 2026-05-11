import 'package:cropcare_ai/core/constants/app_enums.dart';
import 'package:cropcare_ai/data/models/diagnosis_model.dart';
import 'package:cropcare_ai/data/models/treatment_task_model.dart';
import 'package:cropcare_ai/services/health_score_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HealthScoreService.computeScoreAndStatus', () {
    final today = DateTime(2026, 5, 10, 9);

    TreatmentTaskModel task({
      required String id,
      required DateTime dueAt,
      DateTime? completedAt,
    }) {
      return TreatmentTaskModel(
        id: id,
        treatmentId: 'treatment',
        cropId: 'crop',
        userId: 'user',
        title: 'Task $id',
        dueAt: dueAt,
        status: completedAt == null ? TaskStatus.pending : TaskStatus.completed,
        completedAt: completedAt,
        createdAt: dueAt,
        updatedAt: completedAt ?? dueAt,
      );
    }

    DiagnosisModel diagnosis({
      required Severity severity,
      required DateTime diagnosedAt,
    }) {
      return DiagnosisModel(
        id: 'dx',
        cropId: 'crop',
        userId: 'user',
        diagnosisMode: DiagnosisMode.online,
        diseaseName: 'Tomato Early Blight',
        severity: severity,
        diagnosedAt: diagnosedAt,
        createdAt: diagnosedAt,
        updatedAt: diagnosedAt,
      );
    }

    test('returns improving status when score rises from baseline', () {
      final result = HealthScoreService.computeScoreAndStatus(
        tasks: [
          task(id: 'a', dueAt: today, completedAt: today),
          task(id: 'b', dueAt: today, completedAt: today),
          task(id: 'c', dueAt: today),
        ],
        diagnoses: [
          diagnosis(
            severity: Severity.moderate,
            diagnosedAt: today.subtract(const Duration(days: 1)),
          ),
        ],
        previousScore: 50.0,
        now: today,
      );

      // 2 of 3 tasks completed → 67% base, minus 25 moderate penalty = 42.
      expect(result.score, 42);
      // 42 vs previous 50 → delta -8 → worsening (>=5 magnitude).
      expect(result.status, ProgressStatus.worsening);
    });

    test('returns improving status when score climbs significantly', () {
      final result = HealthScoreService.computeScoreAndStatus(
        tasks: [
          task(id: 'a', dueAt: today, completedAt: today),
          task(id: 'b', dueAt: today, completedAt: today),
          task(id: 'c', dueAt: today, completedAt: today),
        ],
        diagnoses: [
          diagnosis(
            severity: Severity.mild,
            diagnosedAt: today.subtract(const Duration(days: 1)),
          ),
        ],
        previousScore: 50.0,
        now: today,
      );

      // 3/3 → 100 base, minus 10 mild penalty = 90.
      expect(result.score, 90);
      // 90 vs 50 → delta +40 → improving.
      expect(result.status, ProgressStatus.improving);
    });

    test('treats null previousScore as no-change baseline (stable)', () {
      final result = HealthScoreService.computeScoreAndStatus(
        tasks: [
          task(id: 'a', dueAt: today, completedAt: today),
          task(id: 'b', dueAt: today),
        ],
        diagnoses: [
          diagnosis(
            severity: Severity.moderate,
            diagnosedAt: today.subtract(const Duration(days: 1)),
          ),
        ],
        previousScore: null,
        now: today,
      );

      // 1/2 → 50 base, minus 25 moderate penalty = 25.
      expect(result.score, 25);
      // No previous score → treat new score as the baseline → stable.
      expect(result.status, ProgressStatus.stable);
    });
  });
}
