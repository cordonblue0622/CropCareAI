import '../core/constants/app_enums.dart';
import '../data/models/diagnosis_model.dart';
import '../data/models/treatment_task_model.dart';

/// One day in the 14-day health-score curve.
class HealthScorePoint {
  final DateTime date; // truncated to local 00:00 of that day
  final int score; // 0–100
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

/// Pure-function health-score derivation. No DB, no network.
///
/// Formula per day D in `[now - 13d, now]`:
///   baseScore   = totalTasks == 0 ? 100 : round(completedTasks/totalTasks * 100)
///   penalty     = mild → 10, moderate → 25, severe → 45, null → 0
///   score(D)    = clamp(baseScore - penalty, 0, 100)
///
/// Limitation accepted for thesis Phase 2: severity penalty does NOT decay
/// as the crop recovers — a once-severe diagnosis caps the score at 55 until
/// a follow-up scan downgrades severity.
class HealthScoreService {
  HealthScoreService._();

  static List<HealthScorePoint> compute14DayCurve({
    required List<TreatmentTaskModel> tasks,
    required List<DiagnosisModel> diagnoses,
    required DateTime now,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final points = <HealthScorePoint>[];

    for (int i = 13; i >= 0; i--) {
      final day = today.subtract(Duration(days: i));
      final endOfDay =
          DateTime(day.year, day.month, day.day, 23, 59, 59, 999);

      // Tasks counted on this day.
      final dueByDay =
          tasks.where((t) => !t.dueAt.isAfter(endOfDay)).toList();
      final completedByDay = dueByDay
          .where((t) =>
              t.completedAt != null && !t.completedAt!.isAfter(endOfDay))
          .toList();

      final baseScore = dueByDay.isEmpty
          ? 100
          : ((completedByDay.length / dueByDay.length) * 100).round();

      // Latest diagnosis at-or-before end-of-day.
      DiagnosisModel? latestDx;
      for (final dx in diagnoses) {
        if (!dx.diagnosedAt.isAfter(endOfDay)) {
          if (latestDx == null ||
              dx.diagnosedAt.isAfter(latestDx.diagnosedAt)) {
            latestDx = dx;
          }
        }
      }
      final penalty = _penaltyFor(latestDx?.severity);
      final rawScore = baseScore - penalty;
      final score = rawScore.clamp(0, 100);

      points.add(HealthScorePoint(
        date: day,
        score: score,
        status: ProgressStatus.insufficientData, // recomputed below
        totalTasks: dueByDay.length,
        completedTasks: completedByDay.length,
        latestSeverity: latestDx?.severity,
      ));
    }

    // Compute status by comparing each day to the score 3 days earlier.
    final result = <HealthScorePoint>[];
    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      ProgressStatus status;
      if (p.totalTasks == 0 || i < 3) {
        status = ProgressStatus.insufficientData;
      } else {
        final delta = p.score - points[i - 3].score;
        if (delta >= 5) {
          status = ProgressStatus.improving;
        } else if (delta <= -5) {
          status = ProgressStatus.worsening;
        } else {
          status = ProgressStatus.stable;
        }
      }
      result.add(HealthScorePoint(
        date: p.date,
        score: p.score,
        status: status,
        totalTasks: p.totalTasks,
        completedTasks: p.completedTasks,
        latestSeverity: p.latestSeverity,
      ));
    }
    return result;
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
