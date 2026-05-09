import 'package:cropcare_ai/core/constants/app_enums.dart';
import 'package:cropcare_ai/data/models/diagnosis_model.dart';
import 'package:cropcare_ai/data/models/treatment_task_model.dart';
import 'package:cropcare_ai/services/health_score_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HealthScoreService.computeCurrentScore', () {
    final today = DateTime(2026, 5, 9);

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

    test(
        'reflects completed treatment tasks instead of staying at severity baseline',
        () {
      final score = HealthScoreService.computeCurrentScore(
        tasks: [
          task(
            id: 'done',
            dueAt: today,
            completedAt: today,
          ),
          task(id: 'pending', dueAt: today),
        ],
        diagnoses: [
          diagnosis(
            severity: Severity.moderate,
            diagnosedAt: today.subtract(const Duration(days: 1)),
          ),
        ],
        now: today,
      );

      expect(score, 25);
    });
  });
}
