import 'package:cropcare_ai/core/constants/app_constants.dart';
import 'package:cropcare_ai/services/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('orders parent records before treatment tasks', () {
    final pending = [
      {'table_name': AppConstants.treatmentTasksTable, 'record_id': 'task-1'},
      {'table_name': AppConstants.treatmentsTable, 'record_id': 'treatment-1'},
      {'table_name': AppConstants.diagnosesTable, 'record_id': 'diagnosis-1'},
      {'table_name': AppConstants.cropsTable, 'record_id': 'crop-1'},
    ];

    final ordered = SyncService.orderPendingSyncItems(pending);

    expect(
      ordered.map((item) => item['table_name']),
      [
        AppConstants.cropsTable,
        AppConstants.diagnosesTable,
        AppConstants.treatmentsTable,
        AppConstants.treatmentTasksTable,
      ],
    );
  });
}
