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
                final color = _markerColorForTasks(
                    events.cast<TreatmentTaskModel>(), day);
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
          tasks: tasksByDay[DateTime(
                  selectedDate.year, selectedDate.month, selectedDate.day)] ??
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
      final localDueAt = t.dueAt.toLocal();
      final key = DateTime(localDueAt.year, localDueAt.month, localDueAt.day);
      (map[key] ??= []).add(t);
    }
    return map;
  }

  static Color _markerColorForTasks(
      List<TreatmentTaskModel> dayTasks, DateTime day) {
    final now = DateTime.now();
    final overdueAt = DateTime(day.year, day.month, day.day, 19);
    final isPast = !now.isBefore(overdueAt);

    final allCompleted =
        dayTasks.every((t) => t.status == TaskStatus.completed);
    if (allCompleted) return AppColors.primary; // green
    final anyMissed =
        isPast && dayTasks.any((t) => t.status != TaskStatus.completed);
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
              border:
                  Border.all(color: AppColors.textLightGray.withOpacity(0.4)),
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
    final hasOverdueTask = tasks.any((task) =>
        task.status != TaskStatus.completed && !now.isBefore(task.overdueAt));
    final allCompleted =
        tasks.every((task) => task.status == TaskStatus.completed);
    final groupColor = allCompleted
        ? AppColors.primary
        : hasOverdueTask
            ? Colors.red
            : Colors.orange;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border(left: BorderSide(color: groupColor, width: 4)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              for (var index = 0; index < tasks.length; index++) ...[
                _ProgressTaskRow(
                  task: tasks[index],
                  onTap: () => onTaskToggled(tasks[index]),
                ),
                if (index < tasks.length - 1)
                  const Divider(height: 1, indent: 16, endIndent: 16),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ProgressTaskRow extends StatelessWidget {
  final TreatmentTaskModel task;
  final VoidCallback onTap;

  const _ProgressTaskRow({required this.task, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDone = task.status == TaskStatus.completed;
    final now = DateTime.now();
    final overdue = !isDone && !now.isBefore(task.overdueAt);
    final statusColor = isDone
        ? AppColors.primary
        : overdue
            ? Colors.red
            : Colors.orange;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isDone ? Icons.task_alt : Icons.circle_outlined,
                size: 22,
                color: statusColor,
              ),
              const SizedBox(width: 12),
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
                        decoration: isDone ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isDone
                          ? 'Completed ${task.completedAt != null ? DateFormat.jm().format(task.completedAt!) : ''}'
                          : (overdue
                              ? 'OVERDUE'
                              : 'Due ${DateFormat.jm().format(task.dueAt)}'),
                      style: TextStyle(fontSize: 12, color: statusColor),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textLightGray),
            ],
          ),
        ),
      ),
    );
  }
}
