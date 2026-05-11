# Phase 2 — Calendar + Health Graph + Notifications (Days 3–6)

**Status:** Approved design. Predecessor: [2026-05-08-phase1-foundation-design.md](2026-05-08-phase1-foundation-design.md).

**Context:** Thesis defense in <2 weeks. Phase 1 shipped: disease labels are humanized, `LocalNotificationsAdapter` is in place with Android `flutter_local_notifications` wired. This phase builds the most defense-impactful single deliverable — three connected components that share state and demo end-to-end inside the Crop Detail Progress tab.

## Constraints (carry-over from Phase 1)

- **No Supabase schema changes.** All work uses existing tables (`treatment_tasks`, `progress_updates`, `diagnoses`, `notifications`).
- **All compute is client-side** — health score is derived in Dart from existing rows; no server function or trigger.
- **Defensive remote calls** continue using the `_runOrFallback` pattern.
- **Android-primary, web fallback.** No iOS work.

## Goal

Inside `CropDetailScreen` Progress tab, replace the current placeholder content with three components sharing one selected-date state:

1. A **calendar** showing daily task status per crop.
2. A **health-score line graph** for the last 14 days that highlights the calendar's selected date.
3. A **notification scheduler** that pushes reminders for the next 7 days of pending tasks and writes an in-app row when each fires.

Tapping a calendar date highlights the matching graph point. Tapping a graph point selects the same calendar date. Marking a task done updates both views and reschedules notifications.

## 2.1 Health Score Service

### Decision: Simple % completed formula (chosen by repo owner)

```dart
// lib/services/health_score_service.dart

class HealthScorePoint {
  final DateTime date;          // truncated to day at 00:00 local
  final int score;              // 0–100, integer
  final ProgressStatus status;  // existing enum: improving | stable | worsening | insufficientData
  final int totalTasks;
  final int completedTasks;
  final Severity? latestSeverity;
}

class HealthScoreService {
  /// Compute a 14-day curve ending today (inclusive).
  /// Pure function — no DB, no network. Trivially unit-testable.
  static List<HealthScorePoint> compute14DayCurve({
    required List<TreatmentTaskModel> tasks,
    required List<DiagnosisModel> diagnoses,
    required DateTime now,
  });
}
```

### Formula per day D in `[now - 13d, now]`

```
totalTasks(D)     = tasks where dueAt <= end-of-day(D)
completedTasks(D) = tasks where completedAt != null AND completedAt <= end-of-day(D)
                       AND dueAt <= end-of-day(D)
baseScore(D)      = totalTasks == 0 ? 100 : round((completedTasks / totalTasks) * 100)

latestSeverity(D) = severity of the most recent diagnosis where diagnosedAt <= D, or null
severityPenalty   = mild → 10, moderate → 25, severe → 45, null → 0

score(D)          = clamp(baseScore - severityPenalty, 0, 100)
```

### `ProgressStatus` derivation

Compare today's score to the score 3 days ago:
- `+5` or more → `improving`
- `-5` or less → `worsening`
- between → `stable`
- fewer than 3 days of data with any tasks → `insufficientData`

### Why this formula

Defensible at thesis defense: the panel can ask "why is the score 65?" and the answer is "the user completed 80% of treatment tasks (= 80 base) and the latest diagnosis was moderate severity (-25 = 55 round) — wait, miscount, let me show the test." The arithmetic is transparent. A multi-factor formula would score better technically but invites questions we don't have time to defend.

Limitation we accept: the severity penalty doesn't decay as the crop recovers — a once-severe diagnosis caps the score at 55 forever until a follow-up scan downgrades severity. We document this in the doc comment as known behavior. (Phase 4 polish or thesis future-work could add severity decay or follow-up-scan boost.)

### Persistence

For Phase 2: **compute on render**, do NOT persist into `progress_updates.health_score`. Persistence is unnecessary for the demo (computation is fast, ~14 iterations over a small task list) and avoids a second write path that could conflict with future schema needs. The `health_score` column stays unused for now.

### Tests

`test/services/health_score_service_test.dart` — at minimum:
- empty inputs → 14 points all at 100, status `insufficientData`
- one severe diagnosis on day 0, no tasks → 14 points at 55
- 100% task completion, no diagnosis → score climbs to 100 as tasks accumulate
- mix of completed and missed → score reflects the ratio
- score clamping (no negative, no >100)
- progress status transitions (improving / stable / worsening)

## 2.2 Calendar Tracker UI

### Package: `table_calendar: ^3.x`

Add to `pubspec.yaml` under a new `# Calendar` section. Single dependency, no native code, no permissions, no Android manifest changes.

### Where it lives

[lib/features/crops/screens/crop_detail_screen.dart](../../../lib/features/crops/screens/crop_detail_screen.dart) — replace the current Progress tab body. The screen already loads `_tasks`, `_diagnoses`, `_progress` in `_loadData()` so no new data plumbing is needed.

### Layout

```
┌─ Progress tab ───────────────────────────────────────┐
│  ┌─ Month calendar (table_calendar) ──────────────┐  │
│  │  S  M  T  W  T  F  S                           │  │
│  │  ...    [4]  5🟢  6🟡  7🔴 ...                  │  │
│  │  (selected day = today by default)             │  │
│  └────────────────────────────────────────────────┘  │
│  ┌─ Health Score Graph (14 days, fl_chart) ──────┐  │
│  │   100 ┤                            ╱─•        │  │
│  │       │              ←  selected dot           │  │
│  │     0 └──────────────────────────              │  │
│  └────────────────────────────────────────────────┘  │
│  ┌─ Tasks for <selected date> ───────────────────┐  │
│  │  ☐  Spray copper fungicide                    │  │
│  │  ☑  Remove infected leaves  · done 2:14 PM    │  │
│  │  ❗ Water crop · MISSED                       │  │
│  └────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

### Calendar markers

For each calendar day with at least one task scheduled:
- All tasks completed → green dot
- Some pending, none missed → amber dot
- Any missed (past dueAt + 4h, not completed) → red dot

Built from `_tasks` already in state. Marker function is `Widget? eventLoader(DateTime day)` per `table_calendar`'s API.

### Selected-date state

`CropDetailScreen` adds a single `DateTime _selectedDate = _today();` field. Calendar tap → `setState(_selectedDate = day)`. Same `_selectedDate` drives the graph highlight and the task list.

### Mark-as-done

Each task tile in the day-list has a `Checkbox`. On tap:
1. Optimistic UI update: set local task's `status = completed`, `completedAt = now`.
2. Call new `CropsProvider.markTaskDone(taskId)` — mirrors the existing `NotificationsProvider.markTaskDone` but operates on the screen's task list.
3. Recompute `_healthCurve` via `HealthScoreService.compute14DayCurve(...)`.
4. Reschedule notifications: `NotificationService.instance.cancelForTask(taskId)` (Phase 1 method).

### "Today" boundary

`table_calendar` defaults to enabling future dates. Allow it — users may scrub forward to see upcoming scheduled tasks (no checkbox shown for future-dated tasks; just title + due time).

## 2.3 Health Score Graph

New widget at `lib/features/crops/widgets/health_score_graph.dart`. Uses `fl_chart`'s `LineChart`.

### API

```dart
class HealthScoreGraph extends StatelessWidget {
  final List<HealthScorePoint> points;       // exactly 14
  final DateTime selectedDate;               // selected calendar day
  final ValueChanged<DateTime> onPointTap;   // tap → bubble up to parent

  const HealthScoreGraph({
    required this.points,
    required this.selectedDate,
    required this.onPointTap,
    super.key,
  });
}
```

### Visuals

- Single line, primary color, smooth (`LineChartBarData.isCurved: true`).
- Y-axis: 0–100, gridlines at 25/50/75. X-axis: dates, label every 3 days.
- Selected point: larger dot (radius 6 vs 3), color-shifted, with a tooltip showing date + score + status (e.g. "May 5 — Score 72 · Improving").
- Empty / insufficientData state: render the line at y=100 with a faded label "Add diagnosis or complete tasks to start tracking" overlaid.

### Bidirectional sync

- Calendar tap → parent passes new `selectedDate` → graph rebuilds with new highlighted dot.
- Graph tap (`LineTouchData.touchCallback`) → call `onPointTap(points[i].date)` → parent updates its `_selectedDate` → calendar's selection updates.

The graph itself is stateless. Sync logic lives in `CropDetailScreen`.

## 2.4 Notifications Wiring

### Schedule the next 7 days of pending tasks

`NotificationsProvider.fetchAll` currently buckets tasks into `_todayTasks` and `_missedTasks` and only schedules `_todayTasks`. Extend it to schedule a new `_upcomingTasks` bucket: pending tasks where `today <= dueAt <= today + 7d`.

The Phase 1 `NotificationService.scheduleForTasks(List<TreatmentTaskModel>)` already iterates and creates 3 reminders per task — so the only change here is feeding it a wider list.

### Tap-to-deep-link

Phase 1 wired `NotificationService.tapStream` (a `Stream<String>` of payloads). Currently nothing listens. Add a single subscription in `app.dart` (or wherever the navigator key lives) that:

1. Parses `payload = 'task:<taskId>'` (Phase 1 payload format).
2. Looks up the task in local SQLite to find its `cropId` and `dueAt.day`.
3. Navigates to `CropDetailScreen(crop)` with `initialTabIndex: progressTab` and `initialSelectedDate: dueAt.day`.

Plumbing: `CropDetailScreen` accepts new optional `initialTabIndex` and `initialSelectedDate` constructor params; uses them in `initState()` if provided.

**Edge case — crop not in memory:** if the tap-handler resolves a `cropId` that's not in `CropsProvider.activeCrops` (e.g. app cold-started from notification, before crops were fetched), trigger `CropsProvider.refresh()` and wait once before navigating. If still missing, show a snackbar "Crop not found" and stay on the current screen. Don't crash the app.

### In-app notification list

When a reminder fires, the existing `notifications` table doesn't get a row written — only the Android tray shows it. For the Notifications screen list to reflect fired reminders even after the user clears the tray, we need to write a `notifications` row when each reminder fires.

Implementation: extend `NotificationService._scheduleSingle` to also schedule a `Timer` (web) / use the `flutter_local_notifications` foreground display callback (Android) that calls `SupabaseService.upsertNotification(...)` at fire time.

**Simplification for Phase 2:** drop the in-app-list mirror for now. Reasoning: the Android tray already shows the notification, and the demo focuses on tray + tap-to-deep-link. Writing a notifications row reliably across app-killed states needs background isolate work that's out of scope for a thesis demo. Add a follow-up note in Phase 4 polish if time permits.

So **§2.4 in Phase 2 is just: widen the task list to 7 days + wire `tapStream` to navigation**. The in-app list mirror is explicitly deferred.

## Out of scope for Phase 2

- Health-score persistence into `progress_updates.health_score` (compute-on-render only).
- In-app notification row written when each Android tray reminder fires (deferred to Phase 4 if time).
- Multi-factor health-score formula (severity decay, follow-up-scan boost).
- Calendar shows tasks across MULTIPLE crops at once — current scope is one crop per detail screen.
- iOS notification tap-handling.
- Editing task `dueAt` from the calendar (read-only for now; add task only via existing flows).

## Definition of Done

- [ ] `HealthScoreService.compute14DayCurve` exists with passing unit tests covering the 6 cases listed in §2.1.
- [ ] `table_calendar` added to `pubspec.yaml`; `pubspec.lock` updated.
- [ ] `CropDetailScreen` Progress tab renders calendar + graph + per-day task list with shared `_selectedDate` state.
- [ ] Calendar markers match task status (green/amber/red).
- [ ] Tapping a date filters the task list AND highlights the corresponding graph point.
- [ ] Tapping a graph point updates `_selectedDate` AND moves the calendar's selection.
- [ ] Marking a task done: optimistic UI update + remote save + score recompute + notification cancel for that task.
- [ ] `NotificationsProvider` schedules reminders for the next 7 days of pending tasks (not just today).
- [ ] Tapping an Android notification deep-links into the right crop's Progress tab on the right date.
- [ ] `flutter analyze` clean for new files.
- [ ] All previous Phase 1 unit tests still pass.
- [ ] Manual on-device demo: create a crop with 4 tasks spanning the past 7 days and next 3 days; mark some done, miss some, leave some pending. Verify calendar markers, graph curve, day-list filtering, mark-as-done flow, and a tapped notification deep-links correctly.

## Files this phase will touch

**New:**
- `lib/services/health_score_service.dart` (contains both `HealthScorePoint` and `HealthScoreService` — single-file unit, no separate model file)
- `lib/features/crops/widgets/health_score_graph.dart`
- `lib/features/crops/widgets/calendar_tracker.dart` (extracted from CropDetailScreen for testability)
- `test/services/health_score_service_test.dart`

**Modified:**
- `pubspec.yaml` (add `table_calendar`)
- `lib/features/crops/screens/crop_detail_screen.dart` (new Progress tab content, deep-link constructor params)
- `lib/features/crops/providers/crops_provider.dart` (add `markTaskDone(taskId)` method)
- `lib/features/notifications/providers/notifications_provider.dart` (extend bucket to 7 days)
- `lib/app.dart` or `lib/main.dart` (wire `NotificationService.instance.tapStream` to navigation)

## Sequencing within Phase 2 (suggested by complexity)

1. Day 3 morning — `HealthScoreService` + tests. Pure Dart, fast unit cycle.
2. Day 3 afternoon — `health_score_graph.dart` widget. Static data, easy to verify in a small demo screen.
3. Day 4 — `table_calendar` integration in `CropDetailScreen`, marker logic, day-list filtering.
4. Day 5 morning — bidirectional sync between calendar and graph, mark-as-done flow.
5. Day 5 afternoon — extend notification scheduling to 7 days; wire `tapStream` to navigation.
6. Day 6 — manual on-device demo rehearsal, polish, edge cases (empty crop, only-future tasks, etc.).
