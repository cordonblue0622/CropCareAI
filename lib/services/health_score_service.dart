import '../core/constants/app_enums.dart';
import '../data/models/diagnosis_model.dart';
import '../data/models/treatment_task_model.dart';

/// One day in the 14-day health-score curve.
class HealthScorePoint {
  final DateTime date;
  final int score;
  final ProgressStatus status;
  final int totalTasks;
  final int completedTasks;
  final Severity? latestSeverity;

  const HealthScorePoint({
    required this.date,
    required this.score,
    required this.status,
    required this.totalTasks,
    required this.completedTasks,
    required this.latestSeverity,
  });
}

class HealthScoreService {
  HealthScoreService._();

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

  static List<HealthScorePoint> compute14DayCurve({
    required List<TreatmentTaskModel> tasks,
    required List<DiagnosisModel> diagnoses,
    required DateTime now,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final points = <HealthScorePoint>[];

    for (int i = 13; i >= 0; i--) {
      final day = today.subtract(Duration(days: i));
      final endOfDay = DateTime(day.year, day.month, day.day, 23, 59, 59, 999);

      final dueByDay = tasks.where((task) => !task.dueAt.isAfter(endOfDay)).toList();
      final completedByDay = dueByDay
          .where((task) =>
              task.completedAt != null && !task.completedAt!.isAfter(endOfDay))
          .toList();

      final baseScore = dueByDay.isEmpty
          ? 100
          : ((completedByDay.length / dueByDay.length) * 100).round();
      final penalty = _penaltyFor(_latestSeverity(diagnoses, endOfDay));
      final score = (baseScore - penalty).clamp(0, 100);

      points.add(HealthScorePoint(
        date: day,
        score: score,
        status: ProgressStatus.insufficientData,
        totalTasks: dueByDay.length,
        completedTasks: completedByDay.length,
        latestSeverity: _latestSeverity(diagnoses, endOfDay),
      ));
    }

    final result = <HealthScorePoint>[];
    for (int i = 0; i < points.length; i++) {
      final point = points[i];
      ProgressStatus status;
      if (point.totalTasks == 0 || i < 3) {
        status = ProgressStatus.insufficientData;
      } else {
        final delta = point.score - points[i - 3].score;
        if (delta >= 5) {
          status = ProgressStatus.improving;
        } else if (delta <= -5) {
          status = ProgressStatus.worsening;
        } else {
          status = ProgressStatus.stable;
        }
      }
      result.add(HealthScorePoint(
        date: point.date,
        score: point.score,
        status: status,
        totalTasks: point.totalTasks,
        completedTasks: point.completedTasks,
        latestSeverity: point.latestSeverity,
      ));
    }

    return result;
  }

  static int computeCurrentScore({
    required List<TreatmentTaskModel> tasks,
    required List<DiagnosisModel> diagnoses,
    required DateTime now,
  }) {
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    final dueTasks = tasks.where((task) => !task.dueAt.isAfter(endOfToday)).toList();
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

class HealthScoreSnapshot {
  final int score;
  final ProgressStatus status;

  const HealthScoreSnapshot({
    required this.score,
    required this.status,
  });
}
