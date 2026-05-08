import 'package:flutter_test/flutter_test.dart';
import 'package:cropcare_ai/services/local_notifications_adapter.dart';

void main() {
  group('reminderIdFor', () {
    test('returns deterministic ids for the same input', () {
      final a = reminderIdFor('task-123', '30min');
      final b = reminderIdFor('task-123', '30min');
      expect(a, b);
    });

    test('returns different ids for different reminder types', () {
      final id30 = reminderIdFor('task-123', '30min');
      final idDue = reminderIdFor('task-123', 'due');
      final idOver = reminderIdFor('task-123', 'overdue');
      expect({id30, idDue, idOver}.length, 3);
    });

    test('returns different ids for different task ids', () {
      final a = reminderIdFor('task-aaa', 'due');
      final b = reminderIdFor('task-bbb', 'due');
      expect(a, isNot(b));
    });

    test('always returns a non-negative 32-bit signed int', () {
      final ids = [
        reminderIdFor('a', '30min'),
        reminderIdFor('a', 'due'),
        reminderIdFor('a', 'overdue'),
        reminderIdFor('long-task-id-with-uuid-shape-9b8c7d6e', 'due'),
      ];
      for (final id in ids) {
        expect(id, greaterThanOrEqualTo(0));
        expect(id, lessThanOrEqualTo(0x7FFFFFFF));
      }
    });
  });
}
