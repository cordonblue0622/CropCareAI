import '../core/constants/app_enums.dart';
import '../data/models/diagnosis_model.dart';
import '../data/models/treatment_task_model.dart';

class HealthScoreService {
  HealthScoreService._();

  /// Pure combinator used when the AI progress backend is unreachable: derives
  /// both the current health score and a status (improving/stable/worsening)
  /// relative to the previous score. Returns [previousScore] as the comparison
  /// baseline; if null, the new score is treated as the baseline (stable).
  static HealthScoreSnapshot computeScoreAndStatus({
    required List<TreatmentTaskModel> tasks,
    required List<DiagnosisModel> diagnoses,
    required double? previousScore,
    required DateTime now,
  }) {
    final score = computeCurrentScore(
      tasks: tasks,
      diagnoses: diagnoses,
      now: now,
    );
    final scoreDouble = score.toDouble();
    final status = statusForScoreChange(
      previousScore: previousScore ?? scoreDouble,
      currentScore: scoreDouble,
    );
    return HealthScoreSnapshot(score: score, status: status);
  }

  static int computeCurrentScore({
    required List<TreatmentTaskModel> tasks,
    required List<DiagnosisModel> diagnoses,
    required DateTime now,
  }) {
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    final dueTasks =
        tasks.where((task) => !task.dueAt.isAfter(endOfToday)).toList();
    final completedTasks = dueTasks
        .where((task) =>
            task.completedAt != null && !task.completedAt!.isAfter(endOfToday))
        .toList();

    final baseScore = dueTasks.isEmpty
        ? 100
        : ((completedTasks.length / dueTasks.length) * 100).round();
    final penalty = _penaltyFor(_latestSeverity(diagnoses, endOfToday));
    return (baseScore - penalty).clamp(0, 100);
  }

  static ProgressStatus statusForScoreChange({
    required double previousScore,
    required double currentScore,
  }) {
    final delta = currentScore - previousScore;
    if (delta >= 5) return ProgressStatus.improving;
    if (delta <= -5) return ProgressStatus.worsening;
    return ProgressStatus.stable;
  }

  static Severity? _latestSeverity(
    List<DiagnosisModel> diagnoses,
    DateTime endOfDay,
  ) {
    DiagnosisModel? latest;
    for (final diagnosis in diagnoses) {
      if (diagnosis.diagnosedAt.isAfter(endOfDay)) continue;
      if (latest == null || diagnosis.diagnosedAt.isAfter(latest.diagnosedAt)) {
        latest = diagnosis;
      }
    }
    return latest?.severity;
  }

  static int _penaltyFor(Severity? severity) {
    switch (severity) {
      case Severity.mild:
        return 10;
      case Severity.moderate:
        return 25;
      case Severity.severe:
        return 45;
      default:
        return 0;
    }
  }
}

/// Bundled result from [HealthScoreService.computeScoreAndStatus].
class HealthScoreSnapshot {
  final int score;
  final ProgressStatus status;

  const HealthScoreSnapshot({
    required this.score,
    required this.status,
  });
}
