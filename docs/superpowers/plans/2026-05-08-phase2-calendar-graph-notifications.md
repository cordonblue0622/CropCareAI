# Phase 2 — Calendar + Health Graph + Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **DO NOT auto-commit.** The repo owner reviews and commits manually. Every "stage for review" step says exactly that — leave changes unstaged or use `git add` only, never `git commit`. This rule overrides any default workflow step in any skill.

**Goal:** Build the Crop Detail Progress tab as a connected feature: a `table_calendar` widget showing daily task status, an `fl_chart` line graph of a 14-day health-score curve, and notification scheduling extended to the next 7 days with tap-to-deep-link. All three components share one `_selectedDate` state.

**Architecture:** Pure-function `HealthScoreService` derives a 14-day score curve from existing `treatment_tasks` and `diagnoses`. A new `CalendarTracker` widget owns the calendar UI; a new `HealthScoreGraph` widget owns the graph. `CropDetailScreen.Progress` tab composes both around a single `_selectedDate` field. A new `CropsProvider.markTaskDone(taskId)` centralizes task completion. `NotificationsProvider` is widened to schedule the next 7 days. `CropCareApp` becomes stateful to subscribe to `NotificationService.instance.tapStream` and deep-link via a `GlobalKey<NavigatorState>`.

**Tech Stack:** Flutter SDK >=3.2, Dart 3.x, Provider state-mgmt, sqflite, Supabase (no schema changes), `table_calendar: ^3.x` (new), `fl_chart` (already in pubspec), `flutter_local_notifications` (Phase 1).

**Spec:** [docs/superpowers/specs/2026-05-08-phase2-calendar-graph-notifications-design.md](../specs/2026-05-08-phase2-calendar-graph-notifications-design.md)

**Predecessor state:** Phase 1 is staged (17 files). The Phase 2 work continues from that staging baseline. Subagents should treat existing staged files as approved context and not modify them outside their assigned task.

---

## Task 1: HealthScoreService + HealthScorePoint with TDD

**Files:**
- Create: `lib/services/health_score_service.dart` (contains `HealthScorePoint` + `HealthScoreService`)
- Test: `test/services/health_score_service_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/services/health_score_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cropcare_ai/core/constants/app_enums.dart';
import 'package:cropcare_ai/data/models/diagnosis_model.dart';
import 'package:cropcare_ai/data/models/treatment_task_model.dart';
import 'package:cropcare_ai/services/health_score_service.dart';

void main() {
  group('HealthScoreService.compute14DayCurve', () {
    final today = DateTime(2026, 5, 8);

    TreatmentTaskModel _task({
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

    DiagnosisModel _diagnosis({
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
          _diagnosis(
              id: 'dx', severity: Severity.severe, diagnosedAt: today.subtract(const Duration(days: 13))),
        ],
        now: today,
      );
      expect(curve.every((p) => p.score == 55), isTrue,
          reason: 'baseScore 100 minus severe penalty 45 = 55');
    });

    test('100% completion, mild diagnosis → score climbs from 90 to 90', () {
      final tasks = [
        _task(
            id: 't1',
            dueAt: today.subtract(const Duration(days: 10)),
            completedAt: today.subtract(const Duration(days: 10))),
        _task(
            id: 't2',
            dueAt: today.subtract(const Duration(days: 5)),
            completedAt: today.subtract(const Duration(days: 5))),
      ];
      final diagnoses = [
        _diagnosis(
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
        _task(
            id: 't1',
            dueAt: today.subtract(const Duration(days: 5)),
            completedAt: today.subtract(const Duration(days: 5))),
        _task(
            id: 't2',
            dueAt: today.subtract(const Duration(days: 5))),
        _task(
            id: 't3',
            dueAt: today.subtract(const Duration(days: 5))),
        _task(
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
        _task(id: 't', dueAt: DateTime(2026, 5, 1)),
      ];
      final curve = HealthScoreService.compute14DayCurve(
        tasks: tasks,
        diagnoses: [
          _diagnosis(
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
          (i) => _task(
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
```

- [ ] **Step 2: Run the test to verify it fails**

```
flutter test test/services/health_score_service_test.dart
```
Expected: import-not-found errors on `health_score_service.dart`.

- [ ] **Step 3: Implement the service**

Create `lib/services/health_score_service.dart`:

```dart
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
```

- [ ] **Step 4: Run the test to verify it passes**

```
flutter test test/services/health_score_service_test.dart
```
Expected: `+6: All tests passed!` (6 test cases).

- [ ] **Step 5: Sanity-check static analysis**

```
flutter analyze lib/services/health_score_service.dart test/services/health_score_service_test.dart
```
Expected: no issues.

- [ ] **Step 6: Stage for review (DO NOT commit)**

```
git add lib/services/health_score_service.dart test/services/health_score_service_test.dart
```
Stop. Report "Task 1 staged — ready for review."

---

## Task 2: HealthScoreGraph widget

**Files:**
- Create: `lib/features/crops/widgets/health_score_graph.dart`

- [ ] **Step 1: Implement the stateless widget**

Create `lib/features/crops/widgets/health_score_graph.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../services/health_score_service.dart';

/// Renders a 14-day health-score line chart. Stateless — selection state
/// is owned by the parent screen and passed in via [selectedDate].
class HealthScoreGraph extends StatelessWidget {
  final List<HealthScorePoint> points;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onPointTap;

  const HealthScoreGraph({
    required this.points,
    required this.selectedDate,
    required this.onPointTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return _emptyState();
    }

    final hasAnyTasks =
        points.any((p) => p.totalTasks > 0 || p.latestSeverity != null);
    if (!hasAnyTasks) {
      return _emptyState();
    }

    final selectedIdx = _indexForDate(selectedDate);

    final spots = <FlSpot>[
      for (int i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].score.toDouble()),
    ];

    return Container(
      height: 220,
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (points.length - 1).toDouble(),
          minY: 0,
          maxY: 100,
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: 25,
            getDrawingHorizontalLine: (_) => FlLine(
              color: AppColors.textLightGray.withOpacity(0.3),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 25,
                reservedSize: 30,
                getTitlesWidget: (v, _) => Text(
                  v.toInt().toString(),
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.textGray),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 3,
                reservedSize: 22,
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= points.length) return const SizedBox.shrink();
                  return Text(
                    DateFormat('M/d').format(points[i].date),
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.textGray),
                  );
                },
              ),
            ),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => AppColors.primaryDark,
              getTooltipItems: (spots) => spots.map((s) {
                final i = s.x.toInt();
                final p = points[i];
                return LineTooltipItem(
                  '${DateFormat('MMM d').format(p.date)}\n'
                  'Score ${p.score} · ${_statusLabel(p.status)}',
                  const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                );
              }).toList(),
            ),
            touchCallback: (event, response) {
              if (event is FlTapUpEvent &&
                  response?.lineBarSpots != null &&
                  response!.lineBarSpots!.isNotEmpty) {
                final i = response.lineBarSpots!.first.x.toInt();
                if (i >= 0 && i < points.length) {
                  onPointTap(points[i].date);
                }
              }
            },
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.25,
              color: AppColors.primary,
              barWidth: 3,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, bar, index) {
                  final isSelected = index == selectedIdx;
                  return FlDotCirclePainter(
                    radius: isSelected ? 6 : 3,
                    color: isSelected ? AppColors.primaryDark : AppColors.primary,
                    strokeColor: Colors.white,
                    strokeWidth: isSelected ? 2 : 1,
                  );
                },
              ),
              belowBarData: BarAreaData(
                show: true,
                color: AppColors.primary.withOpacity(0.08),
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _indexForDate(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    for (int i = 0; i < points.length; i++) {
      if (points[i].date == d) return i;
    }
    return points.length - 1; // fall back to "today"
  }

  String _statusLabel(ProgressStatus s) {
    switch (s) {
      case ProgressStatus.improving:
        return 'Improving';
      case ProgressStatus.worsening:
        return 'Worsening';
      case ProgressStatus.stable:
        return 'Stable';
      default:
        return 'Tracking';
    }
  }

  Widget _emptyState() {
    return Container(
      height: 140,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.textLightGray.withOpacity(0.4)),
      ),
      child: const Padding(
        padding: EdgeInsets.all(20),
        child: Text(
          'Add a diagnosis or complete tasks to start tracking your crop’s health.',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: AppColors.textGray, fontSize: 13, height: 1.4),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Run static analysis**

```
flutter analyze lib/features/crops/widgets/health_score_graph.dart
```
Expected: no errors. The widget uses `intl`, `fl_chart`, and `AppColors` — all already in the project.

- [ ] **Step 3: Stage for review (DO NOT commit)**

```
git add lib/features/crops/widgets/health_score_graph.dart
```
Stop. Report "Task 2 staged — ready for review."

---

## Task 3: Add `table_calendar` package

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add the dependency**

In `pubspec.yaml`, find the `# Charts` section (around line 44-45). Insert immediately after the existing `fl_chart` line:

```yaml
  table_calendar: ^3.1.2
```

So the section reads:

```yaml
  # Charts
  fl_chart: ^0.69.0
  table_calendar: ^3.1.2
```

- [ ] **Step 2: Run `flutter pub get`**

```
flutter pub get
```
Expected: resolves cleanly. `pubspec.lock` updates. If pub fails, STOP and report BLOCKED.

- [ ] **Step 3: Stage for review (DO NOT commit)**

```
git add pubspec.yaml pubspec.lock
```
Stop. Report "Task 3 staged — ready for review."

---

## Task 4: Add `CropsProvider.markTaskDone(taskId)`

**Files:**
- Modify: `lib/features/crops/providers/crops_provider.dart`

- [ ] **Step 1: Read the existing provider to find the right insertion point**

Use Read with offset/limit to inspect `lib/features/crops/providers/crops_provider.dart`. Find the existing `updateCropHealthScore` method (search for `updateCropHealthScore`). The new `markTaskDone` should go right after it — both methods are crop-state mutations.

- [ ] **Step 2: Add the method**

Insert this method after `updateCropHealthScore`:

```dart
  /// Mark a treatment task as completed both remotely (via Supabase) and
  /// in the local SQLite cache. Falls back to local-only if the remote
  /// call fails.
  ///
  /// Returns the updated task on success, or `null` on full failure.
  Future<TreatmentTaskModel?> markTaskDone(String taskId) async {
    final now = DateTime.now();
    try {
      await _supabase.markTreatmentTaskCompleted(taskId, completedAt: now);
    } catch (_) {
      // Continue with local update even if remote fails — sync_service
      // will push it later.
    }

    // Update local cache. DatabaseHelper exposes its underlying Database
    // via the `database` getter (see database_helper.dart:16).
    try {
      final database = await _db.database;
      final rows = await database.query(
        AppConstants.treatmentTasksTable,
        where: 'id = ?',
        whereArgs: [taskId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final original = TreatmentTaskModel.fromMap(rows.first);
      final updated = original.copyWith(
        status: TaskStatus.completed,
        completedAt: now,
        updatedAt: now,
      );
      await _db.upsertRow(AppConstants.treatmentTasksTable, updated.toMap());
      notifyListeners();
      return updated;
    } catch (_) {
      return null;
    }
  }
```

- [ ] **Step 3: Run static analysis**

```
flutter analyze lib/features/crops/providers/crops_provider.dart
```
Expected: no errors.

- [ ] **Step 4: Stage for review (DO NOT commit)**

```
git add lib/features/crops/providers/crops_provider.dart
```
Stop. Report "Task 4 staged — ready for review."

---

## Task 5: CalendarTracker widget

**Files:**
- Create: `lib/features/crops/widgets/calendar_tracker.dart`

The widget renders the month calendar (with daily status markers) plus a per-day task list. It is stateless — selection state is owned by the parent screen.

- [ ] **Step 1: Implement the widget**

Create `lib/features/crops/widgets/calendar_tracker.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/constants/app_enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/treatment_task_model.dart';

class CalendarTracker extends StatelessWidget {
  final List<TreatmentTaskModel> tasks;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;
  final ValueChanged<TreatmentTaskModel> onTaskToggled;

  const CalendarTracker({
    required this.tasks,
    required this.selectedDate,
    required this.onDateSelected,
    required this.onTaskToggled,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tasksByDay = _bucketTasksByDay(tasks);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2)),
            ],
          ),
          padding: const EdgeInsets.all(8),
          child: TableCalendar<TreatmentTaskModel>(
            firstDay: DateTime.now().subtract(const Duration(days: 365)),
            lastDay: DateTime.now().add(const Duration(days: 365)),
            focusedDay: selectedDate,
            selectedDayPredicate: (day) => isSameDay(day, selectedDate),
            startingDayOfWeek: StartingDayOfWeek.sunday,
            calendarFormat: CalendarFormat.month,
            availableGestures: AvailableGestures.horizontalSwipe,
            headerStyle: const HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
              titleTextStyle: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: AppColors.textDark),
            ),
            calendarStyle: CalendarStyle(
              outsideDaysVisible: false,
              selectedDecoration: const BoxDecoration(
                  color: AppColors.primary, shape: BoxShape.circle),
              todayDecoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.25),
                shape: BoxShape.circle,
              ),
            ),
            eventLoader: (day) =>
                tasksByDay[DateTime(day.year, day.month, day.day)] ?? const [],
            calendarBuilders: CalendarBuilders(
              markerBuilder: (context, day, events) {
                if (events.isEmpty) return null;
                final color =
                    _markerColorForTasks(events.cast<TreatmentTaskModel>(), day);
                return Positioned(
                  bottom: 4,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                );
              },
            ),
            onDaySelected: (day, _) {
              onDateSelected(DateTime(day.year, day.month, day.day));
            },
          ),
        ),
        const SizedBox(height: 16),
        _DayTaskList(
          date: selectedDate,
          tasks: tasksByDay[
                  DateTime(selectedDate.year, selectedDate.month, selectedDate.day)] ??
              const [],
          onTaskToggled: onTaskToggled,
        ),
      ],
    );
  }

  static Map<DateTime, List<TreatmentTaskModel>> _bucketTasksByDay(
      List<TreatmentTaskModel> tasks) {
    final map = <DateTime, List<TreatmentTaskModel>>{};
    for (final t in tasks) {
      final key = DateTime(t.dueAt.year, t.dueAt.month, t.dueAt.day);
      (map[key] ??= []).add(t);
    }
    return map;
  }

  static Color _markerColorForTasks(
      List<TreatmentTaskModel> dayTasks, DateTime day) {
    final now = DateTime.now();
    final dayEnd = DateTime(day.year, day.month, day.day, 23, 59, 59);
    final fourHoursAfterDay =
        dayEnd.add(const Duration(hours: 4));
    final isPast = now.isAfter(fourHoursAfterDay);

    final allCompleted = dayTasks.every((t) => t.status == TaskStatus.completed);
    if (allCompleted) return AppColors.primary; // green
    final anyMissed = isPast &&
        dayTasks.any((t) => t.status != TaskStatus.completed);
    if (anyMissed) return Colors.red;
    return Colors.orange; // some pending, none missed
  }
}

class _DayTaskList extends StatelessWidget {
  final DateTime date;
  final List<TreatmentTaskModel> tasks;
  final ValueChanged<TreatmentTaskModel> onTaskToggled;

  const _DayTaskList({
    required this.date,
    required this.tasks,
    required this.onTaskToggled,
  });

  @override
  Widget build(BuildContext context) {
    final header = Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        DateFormat('EEEE, MMM d').format(date),
        style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            color: AppColors.textDark),
      ),
    );

    if (tasks.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.textLightGray.withOpacity(0.4)),
            ),
            child: const Text(
              'No tasks scheduled for this day.',
              style: TextStyle(color: AppColors.textGray, fontSize: 13),
            ),
          ),
        ],
      );
    }

    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        ...tasks.map((task) {
          final isDone = task.status == TaskStatus.completed;
          final overdue = !isDone &&
              task.dueAt.add(const Duration(hours: 4)).isBefore(now);
          final canToggle = !isDone && !date.isAfter(now);
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border(
                left: BorderSide(
                  color: isDone
                      ? AppColors.primary
                      : (overdue ? Colors.red : Colors.orange),
                  width: 4,
                ),
              ),
            ),
            child: Row(
              children: [
                Checkbox(
                  value: isDone,
                  onChanged: canToggle
                      ? (_) => onTaskToggled(task)
                      : null,
                  activeColor: AppColors.primary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textDark,
                          decoration:
                              isDone ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      Text(
                        isDone
                            ? 'Done ${DateFormat.jm().format(task.completedAt!)}'
                            : (overdue
                                ? 'OVERDUE'
                                : 'Due ${DateFormat.jm().format(task.dueAt)}'),
                        style: TextStyle(
                          fontSize: 12,
                          color: isDone
                              ? AppColors.textGray
                              : (overdue ? Colors.red : AppColors.textGray),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
```

- [ ] **Step 2: Run static analysis**

```
flutter analyze lib/features/crops/widgets/calendar_tracker.dart
```
Expected: no errors.

- [ ] **Step 3: Stage for review (DO NOT commit)**

```
git add lib/features/crops/widgets/calendar_tracker.dart
```
Stop. Report "Task 5 staged — ready for review."

---

## Task 6: Wire CalendarTracker + HealthScoreGraph into the Progress tab

**Files:**
- Modify: `lib/features/crops/screens/crop_detail_screen.dart`

This task wires the two new widgets into the existing Progress tab inside `CropDetailScreen`, with shared `_selectedDate` state and bidirectional sync between calendar and graph.

- [ ] **Step 1: Add state field, imports, and helper getter**

In `lib/features/crops/screens/crop_detail_screen.dart`:

Add these imports near the existing widget/data imports (search for the existing `import 'add_crop_screen.dart';` line and add the new imports immediately after):

```dart
import '../../../services/health_score_service.dart';
import '../widgets/calendar_tracker.dart';
import '../widgets/health_score_graph.dart';
```

Inside `_CropDetailScreenState` (the existing State class), add this field below the existing `_chatHistory` field:

```dart
  DateTime _selectedDate = _todayDate();

  static DateTime _todayDate() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  List<HealthScorePoint> get _healthCurve => HealthScoreService.compute14DayCurve(
        tasks: _tasks,
        diagnoses: _diagnoses,
        now: DateTime.now(),
      );
```

- [ ] **Step 2: Locate the Progress tab body and identify what to replace**

Search the file for the TabBarView's "Progress" tab. The existing Progress tab body uses `_sparklineSpots` (existing field) and renders an inline LineChart. Read the surrounding context (use Read with offset/limit) to find the exact code block — typically a Column with health-score header, sparkline chart, and progress list.

The new content should REPLACE that entire block with the new layout:

```dart
SingleChildScrollView(
  padding: const EdgeInsets.all(16),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      CalendarTracker(
        tasks: _tasks,
        selectedDate: _selectedDate,
        onDateSelected: (d) => setState(() => _selectedDate = d),
        onTaskToggled: _onTaskToggled,
      ),
      const SizedBox(height: 16),
      HealthScoreGraph(
        points: _healthCurve,
        selectedDate: _selectedDate,
        onPointTap: (d) => setState(() => _selectedDate = d),
      ),
    ],
  ),
)
```

If the existing Progress tab body is large (>100 lines), preserve any auxiliary content (e.g. header summary card, action buttons) above the new `CalendarTracker`. Replace ONLY the sparkline + task list with the new widgets. If unsure, escalate as NEEDS_CONTEXT.

- [ ] **Step 3: Add the `_onTaskToggled` handler**

Add this method to `_CropDetailScreenState` (alongside other private methods like `_runOrFallback` and `_loadData`):

```dart
  Future<void> _onTaskToggled(TreatmentTaskModel task) async {
    if (task.status == TaskStatus.completed) return;

    // Optimistic update.
    final now = DateTime.now();
    setState(() {
      _tasks = _tasks.map((t) {
        if (t.id != task.id) return t;
        return t.copyWith(
          status: TaskStatus.completed,
          completedAt: now,
          updatedAt: now,
        );
      }).toList();
    });

    // Persist via provider.
    final cropsProvider = context.read<CropsProvider>();
    final updated = await cropsProvider.markTaskDone(task.id);
    if (!mounted) return;

    if (updated == null) {
      // Persistence failed — revert.
      setState(() {
        _tasks = _tasks.map((t) {
          if (t.id != task.id) return t;
          return t.copyWith(
            status: TaskStatus.pending,
            completedAt: null,
            updatedAt: now,
          );
        }).toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not mark task done. Try again.')),
      );
      return;
    }

    // Cancel any scheduled reminders for this task.
    // ignore: discarded_futures
    NotificationService.instance.cancelForTask(task.id);
  }
```

Also add this import at the top of the file (near the other service imports):

```dart
import '../../../services/notification_service.dart';
```

- [ ] **Step 4: Run static analysis**

```
flutter analyze lib/features/crops/screens/crop_detail_screen.dart
```
Expected: no errors. Pre-existing warnings about `withOpacity` are fine.

- [ ] **Step 5: Verify the existing widget tests still pass**

```
flutter test
```
Expected: 21 tests pass (the 14 from Phase 1 + the 6 Task 1 added in Phase 2 + the 1 widget test = 21). 1 skipped (pre-existing backend TFLite harness).

If the smoke test fails because the rebuilt Progress tab introduces a runtime exception during hot start, escalate as BLOCKED.

- [ ] **Step 6: Stage for review (DO NOT commit)**

```
git add lib/features/crops/screens/crop_detail_screen.dart
```
Stop. Report "Task 6 staged — ready for review."

---

## Task 7: Extend NotificationsProvider to schedule next 7 days

**Files:**
- Modify: `lib/features/notifications/providers/notifications_provider.dart`

- [ ] **Step 1: Update `_bucketTasks` to include an upcoming bucket**

Read the existing `_bucketTasks` method (around line 82). Modify to also produce a 7-day-ahead upcoming list:

Find:
```dart
  void _bucketTasks(List<TreatmentTaskModel> allTasks) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));

    _todayTasks = allTasks
        .where((task) =>
            !task.dueAt.isBefore(todayStart) &&
            task.dueAt.isBefore(todayEnd) &&
            task.status == TaskStatus.pending)
        .toList();

    _missedTasks = allTasks
        .where((task) =>
            task.dueAt.isBefore(todayStart) &&
            task.status == TaskStatus.pending)
        .toList();
  }
```

Replace with:
```dart
  void _bucketTasks(List<TreatmentTaskModel> allTasks) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    final sevenDaysOut = todayStart.add(const Duration(days: 7));

    _todayTasks = allTasks
        .where((task) =>
            !task.dueAt.isBefore(todayStart) &&
            task.dueAt.isBefore(todayEnd) &&
            task.status == TaskStatus.pending)
        .toList();

    _missedTasks = allTasks
        .where((task) =>
            task.dueAt.isBefore(todayStart) &&
            task.status == TaskStatus.pending)
        .toList();

    _upcomingTasks = allTasks
        .where((task) =>
            !task.dueAt.isBefore(todayStart) &&
            task.dueAt.isBefore(sevenDaysOut) &&
            task.status == TaskStatus.pending)
        .toList();
  }
```

- [ ] **Step 2: Add the new field and getter**

In the same file, find the existing field declarations (around line 14). Add:

```dart
  List<TreatmentTaskModel> _upcomingTasks = [];
```

And the public getter (after the existing `missedTasks` getter):

```dart
  List<TreatmentTaskModel> get upcomingTasks => _upcomingTasks;
```

- [ ] **Step 3: Schedule the upcoming bucket, not just today**

Find the two `NotificationService.instance.scheduleForTasks(_todayTasks);` calls (lines ~49 and ~150 — they have `// ignore: discarded_futures` from Phase 1).

Change both from:
```dart
      // ignore: discarded_futures
      NotificationService.instance.scheduleForTasks(_todayTasks);
```

to:
```dart
      // ignore: discarded_futures
      NotificationService.instance.scheduleForTasks(_upcomingTasks);
```

- [ ] **Step 4: Update `clear()` to also reset the new field**

Find:
```dart
  void clear() {
    _notifications = [];
    _todayTasks = [];
    _missedTasks = [];
    notifyListeners();
  }
```

Replace with:
```dart
  void clear() {
    _notifications = [];
    _todayTasks = [];
    _missedTasks = [];
    _upcomingTasks = [];
    notifyListeners();
  }
```

- [ ] **Step 5: Run static analysis**

```
flutter analyze lib/features/notifications/providers/notifications_provider.dart
```
Expected: no errors.

- [ ] **Step 6: Run the test suite**

```
flutter test
```
Expected: still 21 passing.

- [ ] **Step 7: Stage for review (DO NOT commit)**

```
git add lib/features/notifications/providers/notifications_provider.dart
```
Stop. Report "Task 7 staged — ready for review."

---

## Task 8: CropDetailScreen deep-link constructor params

**Files:**
- Modify: `lib/features/crops/screens/crop_detail_screen.dart`

- [ ] **Step 1: Add optional constructor params**

In `CropDetailScreen` (the StatefulWidget class, near the top of the file), find:

```dart
class CropDetailScreen extends StatefulWidget {
  final CropModel crop;
  const CropDetailScreen({super.key, required this.crop});

  @override
  State<CropDetailScreen> createState() => _CropDetailScreenState();
}
```

Replace with:

```dart
class CropDetailScreen extends StatefulWidget {
  final CropModel crop;
  final int? initialTabIndex;          // 0..3 to override default tab
  final DateTime? initialSelectedDate; // for calendar deep-linking from notifications

  const CropDetailScreen({
    super.key,
    required this.crop,
    this.initialTabIndex,
    this.initialSelectedDate,
  });

  @override
  State<CropDetailScreen> createState() => _CropDetailScreenState();
}
```

- [ ] **Step 2: Apply the initial values in `initState`**

Find the existing `initState`:
```dart
  @override
  void initState() {
    super.initState();
    _crop = widget.crop;
    _tabs = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }
```

Replace with:
```dart
  @override
  void initState() {
    super.initState();
    _crop = widget.crop;
    _tabs = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTabIndex?.clamp(0, 3) ?? 0,
    );
    if (widget.initialSelectedDate != null) {
      final d = widget.initialSelectedDate!;
      _selectedDate = DateTime(d.year, d.month, d.day);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }
```

- [ ] **Step 3: Run static analysis**

```
flutter analyze lib/features/crops/screens/crop_detail_screen.dart
```
Expected: no errors.

- [ ] **Step 4: Stage for review (DO NOT commit)**

```
git add lib/features/crops/screens/crop_detail_screen.dart
```
Stop. Report "Task 8 staged — ready for review."

---

## Task 9: Wire NotificationService.tapStream to navigation

**Files:**
- Modify: `lib/app.dart`

This task converts `CropCareApp` to a StatefulWidget so it can subscribe to `NotificationService.instance.tapStream` and deep-link via a `GlobalKey<NavigatorState>`.

- [ ] **Step 1: Replace the `CropCareApp` widget**

Replace the entirety of `lib/app.dart` with:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'data/local/database_helper.dart';
import 'data/models/treatment_task_model.dart';
import 'data/remote/ai_backend_service.dart';
import 'data/remote/supabase_service.dart';
import 'data/repositories/auth_repository.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/chat/providers/chat_provider.dart';
import 'features/crops/providers/crops_provider.dart';
import 'features/crops/screens/crop_detail_screen.dart';
import 'features/notifications/providers/notifications_provider.dart';
import 'features/splash/splash_screen.dart';
import 'services/connectivity_service.dart';
import 'services/local_classifier_service.dart';
import 'services/notification_service.dart';
import 'services/sync_service.dart';

class CropCareApp extends StatefulWidget {
  const CropCareApp({super.key});

  @override
  State<CropCareApp> createState() => _CropCareAppState();
}

class _CropCareAppState extends State<CropCareApp> {
  static final GlobalKey<NavigatorState> _navigatorKey =
      GlobalKey<NavigatorState>();

  StreamSubscription<String>? _tapSub;

  @override
  void initState() {
    super.initState();
    // Subscribe lazily so the singleton has been created.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tapSub = NotificationService.instance.tapStream.listen(_handleTap);
    });
  }

  @override
  void dispose() {
    _tapSub?.cancel();
    super.dispose();
  }

  Future<void> _handleTap(String payload) async {
    // Phase 1 payload format: "task:<taskId>"
    if (!payload.startsWith('task:')) return;
    final taskId = payload.substring('task:'.length);
    if (taskId.isEmpty) return;

    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    final ctx = navigator.context;

    // Look up the task locally to find the crop.
    final db = ctx.read<DatabaseHelper>();
    Map<String, dynamic>? row;
    try {
      final database = await db.database;
      final rows = await database.query(
        AppConstants.treatmentTasksTable,
        where: 'id = ?',
        whereArgs: [taskId],
        limit: 1,
      );
      if (rows.isNotEmpty) row = rows.first;
    } catch (_) {/* fall through */}

    if (row == null) {
      _showSnack(navigator.context, 'Task not found.');
      return;
    }
    final task = TreatmentTaskModel.fromMap(row);

    // Find the crop. Refresh once if not present.
    final cropsProvider = ctx.read<CropsProvider>();
    var crop = cropsProvider.activeCrops.firstWhere(
      (c) => c.id == task.cropId,
      orElse: () => cropsProvider.crops.firstWhere(
        (c) => c.id == task.cropId,
        orElse: () => cropsProvider.crops.isNotEmpty
            ? cropsProvider.crops.first
            : throw StateError('No crops loaded'),
      ),
    );
    if (crop.id != task.cropId) {
      // The fallback returned an unrelated crop; try a refresh.
      final auth = ctx.read<AuthProvider>();
      final userId = auth.currentUser?.id;
      if (userId != null) {
        await cropsProvider.fetchCrops(userId);
      }
      try {
        crop = cropsProvider.crops.firstWhere((c) => c.id == task.cropId);
      } catch (_) {
        _showSnack(navigator.context, 'Crop not found.');
        return;
      }
    }

    navigator.push(
      MaterialPageRoute(
        builder: (_) => CropDetailScreen(
          crop: crop,
          initialTabIndex: 1, // Progress tab
          initialSelectedDate: DateTime(
              task.dueAt.year, task.dueAt.month, task.dueAt.day),
        ),
      ),
    );
  }

  void _showSnack(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Core services
        Provider<SupabaseService>(create: (_) => SupabaseService()),
        ProxyProvider<SupabaseService, AiBackendService>(
          update: (_, supabase, __) => AiBackendService(supabase: supabase),
        ),
        Provider<LocalClassifierService>(
          create: (_) => LocalClassifierService(),
        ),
        Provider<DatabaseHelper>(create: (_) => DatabaseHelper.instance),
        Provider<ConnectivityService>(create: (_) => ConnectivityService()),

        // Repository
        ProxyProvider2<SupabaseService, DatabaseHelper, AuthRepository>(
          update: (_, svc, db, __) =>
              AuthRepository(supabaseService: svc, dbHelper: db),
        ),

        // Sync service (auto-listens for connectivity)
        ProxyProvider2<SupabaseService, DatabaseHelper, SyncService>(
          update: (_, svc, db, previous) =>
              previous ?? SyncService(supabaseService: svc, dbHelper: db),
        ),

        // Auth state
        ChangeNotifierProxyProvider<AuthRepository, AuthProvider>(
          create: (ctx) =>
              AuthProvider(authRepository: ctx.read<AuthRepository>()),
          update: (_, repo, prev) => prev ?? AuthProvider(authRepository: repo),
        ),

        // Crops
        ChangeNotifierProxyProvider2<SupabaseService, DatabaseHelper,
            CropsProvider>(
          create: (ctx) => CropsProvider(
            supabase: ctx.read<SupabaseService>(),
            db: ctx.read<DatabaseHelper>(),
          ),
          update: (_, svc, db, prev) =>
              prev ?? CropsProvider(supabase: svc, db: db),
        ),

        // Notifications
        ChangeNotifierProxyProvider2<SupabaseService, DatabaseHelper,
            NotificationsProvider>(
          create: (ctx) => NotificationsProvider(
            supabase: ctx.read<SupabaseService>(),
            db: ctx.read<DatabaseHelper>(),
          ),
          update: (_, svc, db, prev) =>
              prev ?? NotificationsProvider(supabase: svc, db: db),
        ),

        // Chat / AI
        ChangeNotifierProxyProvider3<SupabaseService, DatabaseHelper,
            AiBackendService, ChatProvider>(
          create: (ctx) => ChatProvider(
            supabase: ctx.read<SupabaseService>(),
            db: ctx.read<DatabaseHelper>(),
            aiBackend: ctx.read<AiBackendService>(),
          ),
          update: (_, svc, db, aiBackend, prev) =>
              prev ?? ChatProvider(supabase: svc, db: db, aiBackend: aiBackend),
        ),
      ],
      child: MaterialApp(
        title: 'CropCare AI',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.theme,
        navigatorKey: _navigatorKey,
        home: const SplashScreen(),
      ),
    );
  }
}
```

- [ ] **Step 2: Run static analysis on app.dart**

```
flutter analyze lib/app.dart
```
Expected: no errors.

- [ ] **Step 3: Run all tests**

```
flutter test
```
Expected: 21 passing, 1 skipped. (No new tests added by this task — it's UI plumbing.)

- [ ] **Step 4: Stage for review (DO NOT commit)**

```
git add lib/app.dart
```
Stop. Report "Task 9 staged — ready for review."

---

## Task 10: Manual on-device demo rehearsal (USER task)

**Files:** _no code changes — verification only_

This task validates the full Phase 2 flow on a real Android device. Cannot be done by a subagent.

- [ ] **Step 1: Build and install the latest debug APK**

```
flutter run -d <android-device-id>
```

- [ ] **Step 2: Seed demo data**

Sign in as the test account from Phase 1. Create a crop. Add 4 treatment tasks via the existing add-task flow:

| Task | Due | Expected status after rehearsal |
|---|---|---|
| Task A | yesterday at 9 AM, mark **completed** before stepping in | green dot on yesterday |
| Task B | yesterday at 6 PM, leave **pending** | red dot on yesterday (overdue) |
| Task C | today at 4 PM, leave **pending** | amber dot on today |
| Task D | tomorrow at 10 AM, leave **pending** | amber dot on tomorrow |

- [ ] **Step 3: Verify Progress tab UI**

Open the crop's detail screen → Progress tab. Confirm:

1. Calendar appears with the four marker colors as above.
2. Health score graph appears below the calendar with a 14-day curve.
3. Tasks-for-today list appears below the graph and shows Task C only.
4. Tap **yesterday** in the calendar — graph point at index 12 should highlight (larger dot, primary-dark color), and the day list should show Tasks A and B.
5. Tap a graph point three days back — calendar selection moves to that date and the day list shows the tasks (or "No tasks scheduled" placeholder).

- [ ] **Step 4: Verify mark-as-done flow**

1. Select **today** in the calendar.
2. Tap the checkbox for Task C.
3. Confirm: optimistic UI flips Task C to "Done <time>" with strikethrough; calendar's today marker flips amber → green; graph point at index 13 (today) updates.
4. Pull-down or briefly leave-and-return to the screen — the change should persist (remote save).
5. Pull notification tray — confirm any future-scheduled reminder for Task C has been cancelled (no "Task Due Now" 1–2 minutes later).

- [ ] **Step 5: Verify deep-link from notification**

1. Add a new task due in 31 minutes (call it Task E).
2. Wait for the 30-min warning notification.
3. Tap the notification.
4. Confirm: app opens directly to the crop's Progress tab with **today** selected, and Task E appears in the day list.

- [ ] **Step 6: Document the result**

Create `docs/superpowers/testing/2026-05-08-phase2-demo-smoke.md` with:
- "All steps passed on `<device model> Android <version>`." OR
- A specific failure description with logcat excerpt.

- [ ] **Step 7: Stage the testing report (DO NOT commit)**

```
git add docs/superpowers/testing/2026-05-08-phase2-demo-smoke.md
```
Stop. Report "Task 10 complete. Demo rehearsal: <pass|fail>."

---

## Definition of Done for Phase 2

- [ ] `HealthScoreService.compute14DayCurve` exists with 6 passing tests.
- [ ] `HealthScoreGraph` widget renders 14-day curve with selected-point highlight and bidirectional tap callback.
- [ ] `CalendarTracker` widget renders monthly calendar with correct status markers (green/amber/red) and per-day task list with mark-as-done checkboxes.
- [ ] `CropDetailScreen` Progress tab composes Calendar + Graph with shared `_selectedDate` state.
- [ ] Tapping a calendar date highlights the matching graph point AND filters the day list.
- [ ] Tapping a graph point updates `_selectedDate` AND moves calendar selection.
- [ ] Mark-as-done flow: optimistic UI + remote save (with revert on failure) + notification cancel for that task.
- [ ] `NotificationsProvider` schedules the next 7 days of pending tasks (not just today).
- [ ] `CropDetailScreen` accepts `initialTabIndex` and `initialSelectedDate` constructor params.
- [ ] Tapping an Android notification deep-links into the right crop's Progress tab on the right date.
- [ ] `flutter test` shows all 21 tests passing (1 skipped).
- [ ] `flutter analyze` clean for new files.
- [ ] Manual on-device rehearsal (Task 10) passes.
- [ ] All changes are staged but not committed — repo owner reviews and commits manually.
