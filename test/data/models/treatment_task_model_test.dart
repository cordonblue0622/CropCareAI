import 'package:cropcare_ai/core/constants/app_enums.dart';
import 'package:cropcare_ai/data/models/treatment_task_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TreatmentTaskModel.overdueAt', () {
    test('uses 7 PM on the task due date in local time', () {
      final dueAt = DateTime(2026, 10, 11, 9);
      final task = TreatmentTaskModel(
        id: 'task-1',
        treatmentId: 'treatment-1',
        cropId: 'crop-1',
        userId: 'user-1',
        title: 'Water the crop',
        dueAt: dueAt,
        status: TaskStatus.pending,
        createdAt: dueAt,
        updatedAt: dueAt,
      );

      expect(task.overdueAt, DateTime(2026, 10, 11, 19));
    });

    test('does not treat tomorrow tasks as overdue today', () {
      final now = DateTime(2026, 10, 11, 20);
      final dueAt = DateTime(2026, 10, 12, 9);
      final task = TreatmentTaskModel(
        id: 'task-1',
        treatmentId: 'treatment-1',
        cropId: 'crop-1',
        userId: 'user-1',
        title: 'Water the crop',
        dueAt: dueAt,
        status: TaskStatus.pending,
        createdAt: now,
        updatedAt: now,
      );

      expect(task.isOverdueAt(now), isFalse);
      expect(task.isOverdueAt(DateTime(2026, 10, 12, 18, 59)), isFalse);
      expect(task.isOverdueAt(DateTime(2026, 10, 12, 19)), isTrue);
    });

    test('applies the 7 PM cutoff to pending tasks due today', () {
      final now = DateTime(2026, 10, 11, 18, 59);
      final task = TreatmentTaskModel(
        id: 'task-1',
        treatmentId: 'treatment-1',
        cropId: 'crop-1',
        userId: 'user-1',
        title: 'Water the crop',
        dueAt: DateTime(2026, 10, 11, 9),
        status: TaskStatus.pending,
        createdAt: now,
        updatedAt: now,
      );

      expect(task.isOverdueAt(now), isFalse);
      expect(task.isOverdueAt(DateTime(2026, 10, 11, 19)), isTrue);
    });
  });
}
