// Converts disease guidance into dated, checkable treatment tasks.
// A task is created for every required occurrence instead of storing a
// recurrence rule that could be missed while the device is offline.
import '../data/models/disease_treatment_day_step_model.dart';
import 'treatment_action_parser.dart';

class TreatmentPlanService {
  TreatmentPlanService._();

  static TreatmentPlan build({
    required List<String> treatmentSteps,
    required DateTime startDate,
    int? expectedDurationDays,
  }) {
    final durationDays = (expectedDurationDays ?? 14).clamp(1, 42);
    final normalizedSteps = _uniqueSteps(treatmentSteps);
    final actions = <_PlanAction>[];

    for (final step in normalizedSteps) {
      if (_isMonitoring(step) ||
          _isMoistureCare(step) ||
          _isContinuousCare(step)) {
        actions.add(_PlanAction.daily(step));
      } else if (_isProductApplication(step)) {
        actions.add(
          _PlanAction.repeating(
            step,
            intervalDays: _intervalFromStep(step) ?? 7,
            productApplication: true,
          ),
        );
      } else {
        actions.add(_PlanAction.once(step));
      }
    }

    if (!actions.any((action) => action.isDailyObservation)) {
      actions.add(
        _PlanAction.daily(
          'Inspect the plant for new spots, pests, wilt, or spreading damage.',
          isDailyObservation: true,
        ),
      );
    }

    final occurrences = <TreatmentPlanTask>[];
    for (final action in actions) {
      for (var day = 1; day <= durationDays; day += action.intervalDays) {
        occurrences.add(
          TreatmentPlanTask(
            day: day,
            dueAt: _dateForDay(startDate, day),
            title: action.title,
            description: _descriptionFor(
              action: action,
              day: day,
              durationDays: durationDays,
            ),
          ),
        );
        if (action.onceOnly) break;
      }
    }

    occurrences.sort((left, right) {
      final dateCompare = left.dueAt.compareTo(right.dueAt);
      if (dateCompare != 0) return dateCompare;
      return left.title.compareTo(right.title);
    });

    return TreatmentPlan(
      durationDays: durationDays,
      sourceSteps: normalizedSteps,
      tasks: occurrences,
    );
  }

  /// Creates one checkable task for every action in a reviewed daily protocol.
  static TreatmentPlan buildFromDaySteps({
    required List<DiseaseTreatmentDayStepModel> daySteps,
    required DateTime startDate,
    int? expectedDurationDays,
  }) {
    final activeSteps = daySteps
        .where((step) => step.isActive && step.dayNumber > 0)
        .toList()
      ..sort((left, right) => left.dayNumber.compareTo(right.dayNumber));
    final lastProtocolDay = activeSteps.fold<int>(
      1,
      (latestDay, step) =>
          step.dayNumber > latestDay ? step.dayNumber : latestDay,
    );
    final durationDays =
        (expectedDurationDays ?? lastProtocolDay).clamp(lastProtocolDay, 42);

    final tasks = <TreatmentPlanTask>[];
    for (final step in activeSteps) {
      final actions = TreatmentActionParser.normalize(step.tasks);
      final taskActions = actions.isEmpty ? [step.dayTitle.trim()] : actions;
      for (final action in taskActions) {
        if (!TreatmentActionParser.isMeaningful(action)) continue;
        tasks.add(
          TreatmentPlanTask(
            day: step.dayNumber,
            dueAt: _dateForDay(startDate, step.dayNumber),
            title: action,
            description: _protocolActionDescription(
              step: step,
              durationDays: durationDays,
            ),
          ),
        );
      }
    }

    tasks.sort((left, right) {
      final dateCompare = left.dueAt.compareTo(right.dueAt);
      if (dateCompare != 0) return dateCompare;
      return left.title.compareTo(right.title);
    });

    return TreatmentPlan(
      durationDays: durationDays,
      sourceSteps: activeSteps.map((step) => step.dayTitle).toList(),
      tasks: tasks,
    );
  }

  static bool coversExpectedDuration({
    required List<DiseaseTreatmentDayStepModel> daySteps,
    int? expectedDurationDays,
  }) {
    if (daySteps.isEmpty) return false;
    final activeDays = daySteps
        .where((step) => step.isActive && step.dayNumber > 0)
        .map((step) => step.dayNumber)
        .toSet();
    final lastProtocolDay = activeDays.fold<int>(
        0, (latestDay, day) => day > latestDay ? day : latestDay);
    final durationDays = expectedDurationDays ?? lastProtocolDay;
    if (durationDays < 1 || lastProtocolDay < durationDays) return false;
    return Iterable<int>.generate(durationDays, (index) => index + 1)
        .every(activeDays.contains);
  }

  /// Moves an unfinished task to the same treatment-day offset from a new
  /// Day 1 while preserving its planned time of day.
  static DateTime rebaseTaskDate({
    required DateTime originalDueAt,
    required DateTime originalStartAt,
    required DateTime newStartAt,
  }) {
    final originalDay = DateTime(
      originalDueAt.year,
      originalDueAt.month,
      originalDueAt.day,
    );
    final originalStartDay = DateTime(
      originalStartAt.year,
      originalStartAt.month,
      originalStartAt.day,
    );
    final newStartDay = DateTime(
      newStartAt.year,
      newStartAt.month,
      newStartAt.day,
    );
    final dayOffset = originalDay.difference(originalStartDay).inDays;
    return DateTime(
      newStartDay.year,
      newStartDay.month,
      newStartDay.day,
      originalDueAt.hour,
      originalDueAt.minute,
      originalDueAt.second,
      originalDueAt.millisecond,
      originalDueAt.microsecond,
    ).add(Duration(days: dayOffset < 0 ? 0 : dayOffset));
  }

  static List<String> _uniqueSteps(List<String> steps) {
    return TreatmentActionParser.normalize(steps);
  }

  static DateTime _dateForDay(DateTime startDate, int day) {
    if (day <= 1) {
      return startDate;
    }
    final startOfDay = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
      9,
    );
    return startOfDay.add(Duration(days: day - 1));
  }

  static bool _isMonitoring(String step) {
    return RegExp(r'\b(monitor|scout|inspect|observe|check)\b',
            caseSensitive: false)
        .hasMatch(step);
  }

  static bool _isMoistureCare(String step) {
    return RegExp(r'\b(water|watering|irrigation|moisture|drought)\b',
            caseSensitive: false)
        .hasMatch(step);
  }

  static bool _isContinuousCare(String step) {
    return RegExp(
      r'\b(avoid|keep|maintain|protect|improve airflow|reduce humidity)\b',
      caseSensitive: false,
    ).hasMatch(step);
  }

  static bool _isProductApplication(String step) {
    return RegExp(
      r'\b(apply|spray|fungicide|bactericide|miticide|insecticidal|neem oil|abamectin|labeled insect)\b',
      caseSensitive: false,
    ).hasMatch(step);
  }

  static int? _intervalFromStep(String step) {
    final match = RegExp(
      r'every\s+(\d+)(?:\s*(?:-|to)\s*(\d+))?\s+days?',
      caseSensitive: false,
    ).firstMatch(step);
    if (match == null) return null;

    // When a label gives a range, use the later day to avoid unnecessary
    // applications. The product label and local extension guidance prevail.
    return int.tryParse(match.group(2) ?? match.group(1)!);
  }

  static String _descriptionFor({
    required _PlanAction action,
    required int day,
    required int durationDays,
  }) {
    final cadence = action.onceOnly
        ? 'Complete this setup step today.'
        : action.intervalDays == 1
            ? 'Repeat this daily through Day $durationDays.'
            : 'Repeat every ${action.intervalDays} days through Day $durationDays.';
    final productSafety = action.productApplication
        ? ' Use only a locally registered product and follow its label for rate, protective equipment, and harvest interval.'
        : '';
    return 'Day $day of $durationDays. $cadence$productSafety';
  }

  static String _protocolActionDescription({
    required DiseaseTreatmentDayStepModel step,
    required int durationDays,
  }) {
    final notes = step.notes?.trim();
    return [
      'Day ${step.dayNumber} of $durationDays.',
      if (notes != null && notes.isNotEmpty) 'Why this matters: $notes',
    ].join('\n\n');
  }
}

class TreatmentPlan {
  final int durationDays;
  final List<String> sourceSteps;
  final List<TreatmentPlanTask> tasks;

  const TreatmentPlan({
    required this.durationDays,
    required this.sourceSteps,
    required this.tasks,
  });
}

class TreatmentPlanTask {
  final int day;
  final DateTime dueAt;
  final String title;
  final String description;

  const TreatmentPlanTask({
    required this.day,
    required this.dueAt,
    required this.title,
    required this.description,
  });
}

class _PlanAction {
  final String title;
  final int intervalDays;
  final bool onceOnly;
  final bool productApplication;
  final bool isDailyObservation;

  const _PlanAction({
    required this.title,
    required this.intervalDays,
    required this.onceOnly,
    this.productApplication = false,
    this.isDailyObservation = false,
  });

  factory _PlanAction.once(String title) => _PlanAction(
        title: title,
        intervalDays: 1,
        onceOnly: true,
      );

  factory _PlanAction.daily(
    String title, {
    bool isDailyObservation = false,
  }) =>
      _PlanAction(
        title: title,
        intervalDays: 1,
        onceOnly: false,
        isDailyObservation: isDailyObservation,
      );

  factory _PlanAction.repeating(
    String title, {
    required int intervalDays,
    required bool productApplication,
  }) =>
      _PlanAction(
        title: title,
        intervalDays: intervalDays,
        onceOnly: false,
        productApplication: productApplication,
      );
}
