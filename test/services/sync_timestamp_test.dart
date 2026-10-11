import 'package:cropcare_ai/data/remote/supabase_service.dart';
import 'package:cropcare_ai/services/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('remote timestamp synchronization', () {
    test('normalizes local timestamps to explicit UTC before upload', () {
      final localTime = DateTime(2026, 10, 11, 19);

      final normalized = SupabaseService.normalizeRemoteTimestamps({
        'updated_at': localTime.toIso8601String(),
      });

      final uploadedTime = DateTime.parse(normalized['updated_at'] as String);
      expect(uploadedTime.isUtc, isTrue);
      expect(uploadedTime, localTime.toUtc());
    });

    test('compares timestamp instants across local and UTC offsets', () {
      expect(
        SyncService.remoteTimestampIsAtLeastAsNew(
          remoteTimestamp: '2026-10-11T10:30:00Z',
          localTimestamp: '2026-10-11T18:00:00+08:00',
        ),
        isTrue,
      );
      expect(
        SyncService.remoteTimestampIsAtLeastAsNew(
          remoteTimestamp: '2026-10-11T09:59:00Z',
          localTimestamp: '2026-10-11T18:00:00+08:00',
        ),
        isFalse,
      );
    });
  });

  test('converts blank optional UUID references to null before upload', () {
    final sanitized = SupabaseService.sanitizeOptionalUuidReferences(
      'diagnoses',
      {
        'id': 'diagnosis-id',
        'chat_session_id': ' ',
      },
    );

    expect(sanitized['chat_session_id'], isNull);
    expect(sanitized['id'], 'diagnosis-id');
  });
}
